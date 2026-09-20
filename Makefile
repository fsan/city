.PHONY: build run stop logs format

# The Zig compiler runs only in Docker. No host toolchain is required.
build:
	docker compose build compiler
	docker compose run --rm --no-deps compiler sh -c 'zig build -Doptimize=ReleaseSafe --prefix /tmp/city-build && artifact=$$(mktemp /output/city.XXXXXX) && cp /tmp/city-build/bin/city.wasm "$$artifact" && chmod 644 "$$artifact" && mv "$$artifact" /output/city.wasm'

run:
	docker compose up -d --build
	@echo "Open http://localhost:8080"

stop:
	docker compose down

logs:
	docker compose logs -f compiler

format:
	docker compose run --rm --no-deps compiler zig fmt build.zig src
