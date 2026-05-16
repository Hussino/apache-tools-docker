#!/usr/bin/env bash
set -Eeuo pipefail

DC="${DC:-docker compose}"
NETWORK="${NETWORK:-bigdata-net}"

FAILURES=()
SMOKE_TOPICS=()

pass() { echo "PASS: $*"; }
record_fail() {
  echo "FAIL: $*" >&2
  FAILURES+=("$*")
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    record_fail "missing host command: $1"
    return 1
  }
}

run_step() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    record_fail "$label"
  fi
}

wait_http() {
  local url="$1"
  local tries="${2:-90}"
  local sleep_s="${3:-2}"

  for ((i=1; i<=tries; i++)); do
    if curl -kfsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_s"
  done

  return 1
}

wait_exec_tcp() {
  local svc="$1"
  local port="$2"
  local tries="${3:-60}"
  local sleep_s="${4:-2}"

  for ((i=1; i<=tries; i++)); do
    if $DC exec -T "$svc" bash -lc "exec 3<>/dev/tcp/localhost/$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_s"
  done

  return 1
}

wait_exec_regex() {
  local svc="$1"
  local cmd="$2"
  local regex="$3"
  local tries="${4:-60}"
  local sleep_s="${5:-2}"

  for ((i=1; i<=tries; i++)); do
    local out
    out="$($DC exec -T "$svc" bash -lc "$cmd" 2>&1 || true)"
    if grep -Eq "$regex" <<<"$out"; then
      return 0
    fi
    sleep "$sleep_s"
  done

  return 1
}

check_compose() {
  $DC config >/dev/null && docker network inspect "$NETWORK" >/dev/null 2>&1
}

check_postgres() {
  wait_exec_tcp postgres 5432 &&
  $DC exec -T postgres pg_isready -U hive -d metastore_db >/dev/null &&
  $DC exec -T postgres psql -U hive -d metastore_db -tAc "SELECT 1;" | grep -qx "1"
}

check_hdfs() {
  wait_http http://localhost:9870/ &&
  wait_exec_regex namenode 'hdfs dfsadmin -report 2>&1' 'Live datanodes \([1-9][0-9]*\):' &&
  $DC exec -T namenode bash -lc '
    set -euo pipefail
    hdfs dfs -mkdir -p /_smoke
    printf "hello\n" | hdfs dfs -put -f - /_smoke/hello.txt
    hdfs dfs -cat /_smoke/hello.txt | grep -qx "hello"
    hdfs dfs -rm -r -f /_smoke >/dev/null
  '
}

check_yarn() {
  wait_http http://localhost:8088/ &&
  wait_http http://localhost:8042/ &&
  $DC exec -T resourcemanager bash -lc 'yarn node -list 2>&1' | grep -Eq 'Total Nodes:[[:space:]]*1\b'
}

check_jobhistory() {
  wait_http http://localhost:19888/
}

check_hive() {
  wait_exec_tcp hive-metastore 9083 &&
  wait_exec_tcp hive-server2 10000 || return 1

  local out
  out="$($DC exec -T hive-server2 bash -lc '
    set -euo pipefail
    command -v beeline >/dev/null 2>&1
    beeline -u "jdbc:hive2://localhost:10000/default" -n hive -p hivepassword -e "SHOW DATABASES;" --silent=true
  ' 2>&1)" || return 1

  grep -qiE '(^|[[:space:]])default([[:space:]]|$)' <<<"$out"
}

check_spark() {
  wait_http http://localhost:8080/ &&
  wait_http http://localhost:8081/ &&
  $DC exec -T spark-worker bash -lc 'test -w /opt/spark/work && test -w /opt/spark/logs' &&
  $DC exec -T spark-master bash -lc '
    set -euo pipefail
    JAR=$(ls /opt/spark/examples/jars/spark-examples*.jar 2>/dev/null | head -n 1 || true)
    [ -n "$JAR" ] || { echo "spark examples jar not found"; exit 1; }
    /opt/spark/bin/spark-submit --master spark://spark-master:7077 \
      --class org.apache.spark.examples.SparkPi \
      "$JAR" 1
  ' | grep -Ei 'Pi is roughly|Result is' >/dev/null
}

check_kafka() {
  wait_exec_regex kafka '/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>&1' 'kafka:9092' &&
  wait_http http://localhost:8093/ &&
  $DC exec -T kafka bash -lc '
    set -euo pipefail
    TOPIC="smoke-$(date +%s)"
    MSG="hello-kafka"

    /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
      --create --topic "$TOPIC" --partitions 1 --replication-factor 1 >/dev/null

    SMOKE_TOPICS+=("$TOPIC")

    /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -qx "$TOPIC"

    printf "%s\n" "$MSG" | /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server localhost:9092 \
      --topic "$TOPIC" >/dev/null

    timeout 20s /opt/kafka/bin/kafka-console-consumer.sh \
      --bootstrap-server localhost:9092 \
      --topic "$TOPIC" \
      --from-beginning \
      --max-messages 1 > /tmp/kafka-consume.out 2>&1

    grep -q "$MSG" /tmp/kafka-consume.out
  '
}

check_nifi() {
  wait_http https://localhost:8444/nifi/ 120 2 &&
  $DC exec -T nifi bash -lc 'test -f /opt/nifi/nifi-current/logs/nifi-app.log'
}

cleanup() {
  for topic in "${SMOKE_TOPICS[@]:-}"; do
    $DC exec -T kafka bash -lc "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic \"$topic\" >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

require_cmd docker
require_cmd curl
require_cmd grep
require_cmd timeout

echo "== Compose / network =="
run_step "compose config + network" check_compose

echo "== PostgreSQL =="
run_step "postgres readiness + query" check_postgres

echo "== HDFS =="
run_step "HDFS UI" wait_http http://localhost:9870/
run_step "HDFS datanode registration" wait_exec_regex namenode 'hdfs dfsadmin -report 2>&1' 'Live datanodes \([1-9][0-9]*\):'
run_step "HDFS read/write" $DC exec -T namenode bash -lc '
  set -euo pipefail
  hdfs dfs -mkdir -p /_smoke
  printf "hello\n" | hdfs dfs -put -f - /_smoke/hello.txt
  hdfs dfs -cat /_smoke/hello.txt | grep -qx "hello"
  hdfs dfs -rm -r -f /_smoke >/dev/null
'

echo "== YARN =="
run_step "YARN ResourceManager UI" wait_http http://localhost:8088/
run_step "YARN NodeManager UI" wait_http http://localhost:8042/
run_step "YARN node registration" check_yarn

echo "== JobHistory =="
run_step "history server UI" check_jobhistory

echo "== Hive metastore + HiveServer2 =="
run_step "hive-metastore:9083" wait_exec_tcp hive-metastore 9083
run_step "hive-server2:10000" wait_exec_tcp hive-server2 10000
run_step "HiveServer2 query" check_hive

echo "== Spark =="
run_step "Spark master UI" wait_http http://localhost:8080/
run_step "Spark worker UI" wait_http http://localhost:8081/
run_step "Spark worker writable work/log dirs" $DC exec -T spark-worker bash -lc 'test -w /opt/spark/work && test -w /opt/spark/logs'
run_step "Spark master/worker + job submission" check_spark

echo "== Kafka =="
run_step "Kafka broker API" wait_exec_regex kafka '/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>&1' 'kafka:9092'
run_step "Kafka UI" wait_http http://localhost:8093/
run_step "Kafka topic + produce + consume" check_kafka

echo "== NiFi =="
run_step "NiFi HTTPS + log presence" check_nifi

echo
if ((${#FAILURES[@]} > 0)); then
  echo "FAILED TESTS:" >&2
  for f in "${FAILURES[@]}"; do
    echo " - $f" >&2
  done
  exit 1
fi

echo "ALL TESTS PASSED"
