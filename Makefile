# Atalhos para quem tem make (Linux/macOS/WSL). No Windows sem make,
# use os comandos do README diretamente.
PSQL = docker compose exec -T db psql -v ON_ERROR_STOP=1 -U $${POSTGRES_USER:-deposito} -d bd_deposito

.PHONY: up down reset psql test consultas

up:            ## sobe o banco com os dados de exemplo
	docker compose up -d --wait

down:          ## derruba o container (mantem os dados)
	docker compose down

reset:         ## apaga tudo e recria do zero
	docker compose down -v
	docker compose up -d --wait

psql:          ## abre o terminal SQL
	docker compose exec db psql -U $${POSTGRES_USER:-deposito} -d bd_deposito

test:          ## roda os testes das regras de negocio
	$(PSQL) -q -f /tests/testes_regras.sql

consultas:     ## executa todos os relatorios de queries/
	@for f in queries/*.sql; do printf "\n===== %s\n" "$$f"; $(PSQL) -f /$$f; done
