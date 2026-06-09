# hadoop-spark.Dockerfile
FROM apache/hadoop:3.5.0

USER root

# Install Python3 for PySpark and wget for downloading Spark
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    wget \
    tar \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Spark
ENV SPARK_VERSION=3.5.1
ENV HADOOP_VERSION=3
RUN wget -q "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" \
    && tar -xzf spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz -C /opt/ \
    && mv /opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} /opt/spark \
    && rm spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz

ENV SPARK_HOME=/opt/spark
ENV PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
ENV PYSPARK_PYTHON=/usr/bin/python3
ENV HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
ENV YARN_CONF_DIR=/opt/hadoop/etc/hadoop

RUN cp /opt/spark/conf/spark-defaults.conf.template /opt/spark/conf/spark-defaults.conf \
    && echo "spark.yarn.jars local:/opt/spark/jars/*" >> /opt/spark/conf/spark-defaults.conf

RUN chown -R hadoop:hadoop /opt/spark

# Add the entrypoint script
COPY worker-entrypoint.sh /usr/local/bin/worker-entrypoint.sh
RUN chmod +x /usr/local/bin/worker-entrypoint.sh && chown hadoop:hadoop /usr/local/bin/worker-entrypoint.sh

USER hadoop
