.PHONY: help build test smoke cover fmt lint tidy gen-docs ci snapshot changelog
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the wm binary into bin/
	go build -o bin/wm ./cmd/wm

test: ## Run all tests with the race detector
	go test -race ./...

smoke: ## Run the live network smoke test (real Yahoo/CVM)
	go test -tags live -count=1 ./cmd/wm/

cover: ## Run tests and enforce the coverage floor (80%)
	bash scripts/coverage.sh 80

fmt: ## Format the code (gofmt + goimports)
	gofmt -w . && goimports -w .

lint: ## Run golangci-lint
	golangci-lint run

tidy: ## Tidy go.mod / go.sum
	go mod tidy

gen-docs: ## Generate shell completions + man pages into completions/ and manpages/
	go run ./cmd/gen-docs

changelog: ## Regenerate CHANGELOG.md from Conventional Commits
	git cliff -o CHANGELOG.md

snapshot: ## Build a local release snapshot (dist/), no publish
	goreleaser release --snapshot --clean

ci: fmt lint cover build ## Run the full local gate (fmt, lint, cover, build)
