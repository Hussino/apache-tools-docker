# RUNNING.md — Run subsets of the stack

This file provides ready-to-copy `docker compose` commands for commonly used subsets of the repository's services. When a command references `*-init` services, include them on first runs so HDFS gets formatted and directories are created.

Prepare environment

```bash
cp .env.example .env
# edit .env to set EXTERNAL_IP if needed for NiFi
```

Full stack (all services)

```bash
docker compose up -d --build
```

Hadoop (HDFS + YARN) — recommended order for initial run

```bash
docker compose up -d namenode-init datanode-init namenode datanode resourcemanager historyserver
```

You can scale the number of datanode/worker replicas (e.g., to 3) by running:

```bash
docker compose up -d --scale datanode=3
```

HDFS only (NameNode + DataNode)

If the NameNode is already formatted on disk, you can omit the `*-init` services.

```bash
docker compose up -d namenode-init datanode-init namenode datanode
```

NiFi + HDFS

Start HDFS and NiFi together so NiFi can read/write to HDFS if needed.

```bash
docker compose up -d namenode-init datanode-init namenode datanode nifi
```

Hive (Postgres metastore + metastore + HiveServer2)

Note: in this repository Hive is configured to integrate with Hadoop/HDFS. The metastore and HiveServer2 expect HDFS and Hadoop configuration from the `namenode`/`datanode` services. Start HDFS (NameNode/datanode) along with Postgres and Hive:

```bash
docker compose up -d namenode-init datanode-init namenode datanode postgres hive-metastore hive-server2
```

If you already have HDFS formatted and running, you may omit the `*-init` services and start only `namenode datanode postgres hive-metastore hive-server2`.

Running Hive without Hadoop (non-default)

If you want to run Hive standalone without HDFS (use local filesystem for the warehouse), you'll need to change the Hive configuration in the `hive` build context: remove or override `HIVE_CUSTOM_CONF_DIR`, set `hive.metastore.warehouse.dir` to a local path (e.g. `/opt/hive/data/warehouse` inside the container), and adjust volumes accordingly. This setup is not provided by default in this repo — tell me if you want a ready-to-use compose variant for standalone Hive.

Spark (via YARN) — depends on HDFS and YARN

```bash
docker compose up -d namenode datanode resourcemanager spark-client
```

Spark + Hive

```bash
docker compose up -d namenode-init datanode-init namenode datanode postgres hive-metastore hive-server2 spark-client
```

Kafka only (broker + UI)

```bash
docker compose up -d kafka kafka-ui
```

NiFi + Kafka

```bash
docker compose up -d kafka kafka-ui nifi
```

Minimal developer flows

- Start a single service to iterate on configuration/logs: `docker compose up -d <service>`
- View logs: `docker compose logs -f <service>`
- Run a command inside a container: `docker compose exec -T <service> bash`

Cleanup

Bring everything down and remove volumes created by compose:

```bash
docker compose down -v
```

If you prefer to stop specific services only:

```bash
docker compose stop <service>...
```

Troubleshooting

- If a service fails to start, inspect the logs with `docker compose logs <service>`.
- Use `docker compose ps` to check container states and healthchecks.
- For HDFS ensure `namenode-init` ran successfully (it formats the namenode on first run). If formatting failed and you need to reformat, remove the `namenode_data` volume before re-running the init step.
# Partial runs: start only the services you need

This document shows examples to run subsets of the full compose stack. Use `docker compose up -d <service>...` to start only the services you want. For many services the compose file includes `*-init` helper services — include those when you start HDFS-related services.

General notes

- Always copy `.env.example` to `.env` and update `EXTERNAL_IP` if needed.
- When starting a subset, you may want to include related services that other services depend on (for example, Hive needs `postgres` and `hive-metastore`).
- To stop services started this way: `docker compose stop <service>...` or `docker compose down -v` to remove containers and volumes.

Example: NiFi + HDFS (quick)

This starts HDFS (NameNode + DataNode) and NiFi. The `*-init` services ensure HDFS paths are created/formatted.

```bash
cp .env.example .env
docker compose up -d namenode-init datanode-init namenode datanode nifi
```

Wait for UIs to become available:

- NameNode UI: http://localhost:9870
- NiFi UI: https://localhost:8444/nifi

Example: Hive (metastore + HiveServer2) only

Hive requires PostgreSQL (metastore DB) plus the metastore and server:

```bash
cp .env.example .env
docker compose up -d postgres hive-metastore hive-server2
```

Connect with Beeline/JDBC to `jdbc:hive2://localhost:10003` (HiveServer2 is remapped to port `10003` locally).

Example: Spark (via YARN)

Spark depends on HDFS and YARN for execution; start HDFS, YARN and spark-client:

```bash
docker compose up -d namenode datanode resourcemanager spark-client
```

Example: Kafka + Kafka UI only

```bash
docker compose up -d kafka kafka-ui
```

Cleaning up

To bring everything down and remove volumes:

```bash
docker compose down -v
```

If you need to remove a service and its volumes manually, use `docker compose rm -v <service>` and `docker volume rm <volume>`.

If a partial run fails because a service is unhealthy or missing, check `docker compose ps` and logs with `docker compose logs <service>`.
