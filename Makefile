.PHONY: build run stop logs format

# The Zig compiler runs only in Docker. No host toolchain is required.
build:
	docker compose build compiler
	docker compose run --rm --no-deps compiler sh -c 'work=$$(mktemp -d /tmp/city-build.XXXXXX) && zig build --cache-dir $$work/cache --global-cache-dir $$work/global -Doptimize=ReleaseSafe --prefix $$work/out && artifact=$$(mktemp /output/city.XXXXXX) && cp $$work/out/bin/city.wasm "$$artifact" && chmod 644 "$$artifact" && mv "$$artifact" /output/city.wasm && rm -rf $$work'

run:
	docker compose up -d --build
	@echo "Open http://localhost:8080"

stop:
	docker compose down

logs:
	docker compose logs -f compiler

format:
	docker compose run --rm --no-deps compiler zig fmt build.zig src
