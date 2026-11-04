#!/usr/bin/env bash
# Cria (ou recria) o banco bd_deposito num PostgreSQL ja instalado, sem Docker.
# Uso: ./scripts/criar_banco_local.sh            (usa PGHOST/PGPORT/PGUSER do ambiente)
#      PGUSER=postgres ./scripts/criar_banco_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DB="${DB:-bd_deposito}"

echo ">> Recriando o banco $DB"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"

for f in db/0*.sql; do
  echo ">> $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f" > /dev/null
done

echo ">> Pronto. Conecte com: psql -d $DB"
