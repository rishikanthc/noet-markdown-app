SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap core build app run test clean

help:
	@printf '%s\n' \
	  'make bootstrap   Install Homebrew dependencies (except Swift/macOS SDK)' \
	  'make core        Build Zig + cmark-gfm into one static library' \
	  'make build       Build the Swift executable with SwiftPM' \
	  'make app         Produce .build/MarkdownLab.app' \
	  'make run         Build and launch; pass FILE=/path/to/file.md' \
	  'make test        Run Swift tests and Zig core tests' \
	  'make clean       Remove generated build output'

bootstrap:
	brew install zig cmake

core:
	./scripts/build-core.sh

build: core
	swift build -c debug

app: core
	./scripts/bundle-app.sh

run: core
	@if [[ -n "$(FILE)" ]]; then \
	  ./scripts/run-app.sh "$(FILE)"; \
	else \
	  ./scripts/run-app.sh; \
	fi

test:
	./scripts/test-all.sh

clean:
	rm -rf .build
	rm -rf Vendor/mdcore-zig/zig-out Vendor/mdcore-zig/.zig-cache
	rm -rf Vendor/mdcore-zig/vendor/cmark-gfm/build Vendor/mdcore-zig/vendor/cmark-gfm/install
