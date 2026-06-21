.PHONY: build test cover fmt lint tidy ci snapshot changelog

build:
	go build -o bin/wm ./cmd/wm

test:
	go test -race ./...

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
