#!/bin/bash
set -e

mkdir -p /opt/spark/work /opt/spark/logs

chown -R spark:spark /opt/spark/work /opt/spark/logs

exec /opt/spark/bin/spark-class \
  org.apache.spark.deploy.worker.Worker \
  spark://spark-master:7077