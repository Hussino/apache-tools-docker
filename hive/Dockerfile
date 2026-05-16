FROM apache/hive:4.1.0

USER root

ARG POSTGRES_JDBC_VERSION=42.7.7
RUN wget --no-verbose -O /opt/hive/lib/postgres.jar \
       https://jdbc.postgresql.org/download/postgresql-${POSTGRES_JDBC_VERSION}.jar \
    && chown hive:hive /opt/hive/lib/postgres.jar

USER hive
