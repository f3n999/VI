.PHONY: secrets up down clean test demo nmap logs ps help

## Affiche cette aide
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""

secrets: ## Génère les secrets + certificat TLS (obligatoire avant up)
	sh scripts/gen-secrets.sh

up: ## Build et démarre tous les services
	sh scripts/gen-secrets.sh
	docker compose up -d --build
	docker compose ps

down: ## Arrête la stack (conserve les volumes)
	docker compose down

clean: ## Arrête la stack et supprime les volumes
	docker compose down -v

test: ## Lance la suite de tests pytest
	pytest thread-api/tests -q

demo: ## Rejoue le scénario de démo complet
	sh scripts/demo.sh

nmap: ## Scanne les ports ouverts sur l'hôte (preuve d'isolation)
	sh scripts/nmap-proof.sh

logs: ## Suit les logs de tous les services
	docker compose logs -f

ps: ## Affiche l'état des services
	docker compose ps
