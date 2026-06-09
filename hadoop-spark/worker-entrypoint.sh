#!/bin/bash
set -e

DATA_ROOT="/hadoop/dfs/data"
mkdir -p "$DATA_ROOT"

# --- Claim a stable numbered slot using flock on the shared volume ---
# Each replica grabs the first available slot (datanode-1, datanode-2, ...).
# flock ensures mutual exclusion; the lock auto-releases when the
# container stops, so the same slot is reused on the next 'up'.
for i in $(seq 1 99); do
  LOCK_FILE="$DATA_ROOT/.slot-$i.lock"
  exec 200>"$LOCK_FILE"
  if flock -n 200; then
    WORKER_DIR="$DATA_ROOT/datanode-$i"
    mkdir -p "$WORKER_DIR"
    echo "Claimed slot datanode-$i (data dir: $WORKER_DIR)"
    break
  fi
done

if [ -z "$WORKER_DIR" ]; then
  echo "ERROR: Could not claim a worker slot" >&2
  exit 1
fi

# Start the DataNode in the background, overriding the storage directory via standard -D flag.
# Direct command line arguments take precedence over configurations specified in XML files.
/opt/hadoop/bin/hdfs datanode -D dfs.datanode.data.dir=file://$WORKER_DIR &
DN_PID=$!

# Start the YARN NodeManager in the background
/opt/hadoop/bin/yarn nodemanager &
NM_PID=$!

# Function to handle shutdown signals gracefully
cleanup() {
  echo "Received SIGTERM/SIGINT. Shutting down..."
  kill "$DN_PID" "$NM_PID" 2>/dev/null || true
  wait "$DN_PID" "$NM_PID" 2>/dev/null || true
  exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

# Wait on both processes
wait "$DN_PID" "$NM_PID"
