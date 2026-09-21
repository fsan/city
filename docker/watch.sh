#!/bin/sh
# Publish only completed builds; a syntax error keeps the previous playable build.
build() {
  work=$(mktemp -d /tmp/city-watch.XXXXXX)
  if zig build --cache-dir "$work/cache" --global-cache-dir "$work/global" -Doptimize=ReleaseSafe --prefix "$work/out"; then
    artifact=$(mktemp /output/city.XXXXXX)
    cp "$work/out/bin/city.wasm" "$artifact"
    chmod 644 "$artifact"
    mv "$artifact" /output/city.wasm
    date +%s > /output/version.txt
    echo 'City rebuilt. Refresh the browser to load it.'
  else
    echo 'Build failed; keeping the last successful build.' >&2
  fi
  rm -rf "$work"
}
build
while inotifywait -qq -r -e modify,create,delete,move src build.zig; do
  sleep 0.3
  build
done
