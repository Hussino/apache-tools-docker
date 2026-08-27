# Big data lab stack

This repository provides a multi-service big-data development environment assembled with Docker Compose. It includes:

- Hadoop (HDFS, YARN, NodeManager, ResourceManager, HistoryServer)
- Hive (metastore + HiveServer2) backed by PostgreSQL
- Apache Spark (on YARN)
- Apache NiFi
- Apache Kafka + Kafka UI

The compose file is intended for local development and testing only.

Quickstart — full stack

1. Copy environment variables from `.env.example` to `.env` and adjust `EXTERNAL_IP` if you plan to access NiFi from other hosts.

```bash
cp .env.example .env
# edit .env as needed
docker compose up -d --build
```

To stop and remove containers and volumes created by the compose file:

```bash
docker compose down -v
```

Running selected services

If you don't want the entire stack, you can start only specific services with `docker compose up -d <service> [<service> ...]`.
See [RUNNING.md](RUNNING.md) for tested examples (for example `nifi + HDFS`).

Environment

- Use `.env` (based on `.env.example`) to set `SERVER_IP`, `EXTERNAL_IP`, and `NIFI_PASSWORD`.

Useful UIs / endpoints (host:container-port)

- NameNode: http://localhost:9870
- HDFS RPC: 9000
- YARN ResourceManager: http://localhost:8088
- NodeManager UIs: accessible via YARN ResourceManager → Nodes
- JobHistory: http://localhost:19888
- Spark metrics in YARN ResourceManager UI: http://localhost:8088
- HiveServer2 (JDBC): jdbc:hive2://localhost:10000 (mapped to 10003 locally)
- NiFi (HTTPS): https://localhost:8444/nifi (mapped from 8443 inside container)
- Kafka broker: localhost:9092
- Kafka UI: http://localhost:8093

Smoke tests

This repo contains `smoke-test.sh` that runs a lightweight verification across services (HDFS read/write, Hive beeline query, Spark job submission, Kafka produce/consume, NiFi readiness). To run it locally:

```bash
./smoke-test.sh
```

Notes and troubleshooting

- Services create and use named volumes declared in the compose file. `docker compose down -v` removes them.
- If you want to permanently remove all data, stop the compose and remove the volumes with `docker volume rm <volume>`.
- When launching only subsets of services, start any initializer services listed in the compose file (services named `*-init`) used by HDFS.
- **Dynamic Worker Scaling**: Scale worker nodes (which run HDFS DataNodes and YARN NodeManagers with Spark binaries) dynamically:
  ```bash
  docker compose up -d --scale datanode=3
  ```
  Storage directories are automatically isolated inside the shared volume using numbered slots (`datanode-1`, `datanode-2`, ...) that persist across restarts.
- **Configuration Sync**: Configurations are shared via the `hadoop_shared_conf` volume. If you modify local files in `./hadoop/etc/hadoop/`, apply changes using:
  ```bash
  docker compose up -d --force-recreate namenode-init && docker compose restart
  ```

Contributing

Feel free to open issues or PRs. Keep in mind this project is intended for local labs and is not hardened for production.
