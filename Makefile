.PHONY: build test e2e e2e-live cover fmt lint tidy ci snapshot changelog

build:
	go build -o bin/wm ./cmd/wm

test:
	go test -race ./...

e2e: build
	bash test/e2e/e2e.sh

e2e-live: build
	bash test/e2e/live_smoke.sh

cover:
	bash scripts/coverage.sh 80

fmt:
	gofmt -w . && goimports -w .

lint:
	golangci-lint run

tidy:
	go mod tidy

changelog:
	git cliff -o CHANGELOG.md

snapshot:
	goreleaser release --snapshot --clean

ci: fmt lint cover build
