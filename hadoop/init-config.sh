#!/bin/bash
# Sync defaults and custom files
chmod 777 /shared_config
cp -r /opt/hadoop/etc/hadoop/* /shared_config/
cp -f /tmp/custom_conf/* /shared_config/
chown -R hadoop:hadoop /shared_config
chmod -R 755 /shared_config

# Set the config directory explicitly for the format command
export HADOOP_CONF_DIR=/shared_config

# Format if needed
chown -R hadoop:hadoop /hadoop/dfs/name
if [ ! -d /hadoop/dfs/name/current ]; then
  echo "Formatting NameNode..."
  su -s /bin/bash hadoop -c "HADOOP_CONF_DIR=$HADOOP_CONF_DIR /opt/hadoop/bin/hdfs namenode -format -nonInteractive"
else
  echo 'NameNode already formatted'
fi
