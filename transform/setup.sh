#!/bin/bash
# EC2 초기 환경 셋업 스크립트
# 실행: bash transform/setup.sh [duckdb_path]
# 예시: bash transform/setup.sh /workspace/nyc-taxi/warehouse.duckdb

set -e

DUCKDB_PATH="${1:-/workspace/nyc-taxi/warehouse.duckdb}"
PROFILES_DIR="$HOME/.dbt"
PROFILES_PATH="$PROFILES_DIR/profiles.yml"

echo "=== NYC Taxi dbt Setup ==="

# 1. profiles.yml 생성
if [ -f "$PROFILES_PATH" ]; then
  echo "[skip] profiles.yml already exists at $PROFILES_PATH"
else
  mkdir -p "$PROFILES_DIR"
  cat > "$PROFILES_PATH" << EOF
nyc_taxi:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: $DUCKDB_PATH
      settings:
        memory_limit: '3GB'
        temp_directory: '/tmp/duckdb_spill'
        threads: 2
        s3_region: 'us-east-1'
        s3_endpoint: 's3.amazonaws.com'
EOF
  echo "[done] profiles.yml created at $PROFILES_PATH"
fi

# 2. dbt deps
echo "[run] dbt deps"
cd "$(dirname "$0")"
dbt deps

echo "=== Setup complete. Run: dbt test ==="
