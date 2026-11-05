#!/usr/bin/env bash
# Roda os testes das regras de negocio contra o banco bd_deposito.
# Sem Docker: ./scripts/rodar_testes.sh
# Com Docker: docker compose exec db psql -U deposito -d bd_deposito -f /tests/testes_regras.sql
set -euo pipefail
cd "$(dirname "$0")/.."
psql -v ON_ERROR_STOP=1 -q -d "${DB:-bd_deposito}" -f tests/testes_regras.sql
