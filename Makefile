.DEFAULT_GOAL := help
.PHONY: help install dev-up dev-down sync release lint

# Set in the environment, for example: export DEPLOY_TARGET=shop-deploy
DEPLOY_TARGET ?=
DEPLOY_PORT   ?=

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "%-12s %s\n", $$1, $$2}'

install: ## Install workspace dependencies
	pnpm install

dev-up: ## Start local Postgres, Redis and Mailpit
	docker compose -f docker-compose.dev.yml up -d

dev-down: ## Stop local dependencies, keeping data
	docker compose -f docker-compose.dev.yml down

lint: ## Lint all workspaces
	pnpm lint

sync: ## Copy the compose file and server scripts to the server
	DEPLOY_TARGET=$(DEPLOY_TARGET) DEPLOY_PORT=$(DEPLOY_PORT) bash infra/scripts/release.sh --sync-only

release: ## Build images locally and deploy them to the server
	DEPLOY_TARGET=$(DEPLOY_TARGET) DEPLOY_PORT=$(DEPLOY_PORT) bash infra/scripts/release.sh
