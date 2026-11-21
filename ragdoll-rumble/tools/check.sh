#!/usr/bin/env bash
# Compile-checks every script with the real Luau compiler and runs the arena sanity tests.
# Needs a Luau runner binary (LUAU_RUNNER, see README) that supports `--check files...`.
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
RUNNER=${LUAU_RUNNER:-luaurun}
"$RUNNER" --check "$DIR"/src/*/*.luau
python3 "$DIR/tools/bundle.py" "$DIR/tests/maps_test.luau" /tmp/rumble_maps_test.luau
"$RUNNER" /tmp/rumble_maps_test.luau
