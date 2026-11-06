#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/.."

full=0
[[ "${1:-}" == "--full" ]] && full=1
jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

build_and_test() {
    local preset=$1
    step "Configure + build ($preset)"
    cmake --preset "$preset"
    cmake --build --preset "$preset" -j"$jobs"
    step "Test ($preset)"
    ctest --preset "$preset"
}

step "Format check"
dirs=()
for d in src include tests benchmarks examples; do
    [[ -d $d ]] && dirs+=("$d")
done
find "${dirs[@]}" -type f \( -name '*.c' -o -name '*.h' \) -print0 \
    | xargs -0 -r clang-format --dry-run --Werror

build_and_test ci

step "clang-tidy"
find src -type f -name '*.c' -print0 | xargs -0 -r clang-tidy -p build-ci --quiet

if [[ $full -eq 1 ]]; then
    build_and_test cpu

    ASAN_OPTIONS=detect_leaks=0 build_and_test asan

    step "Install smoke test"
    prefix=$(mktemp -d)
    trap 'rm -rf "$prefix"' EXIT
    cmake --preset release -DNNC_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX="$prefix"
    cmake --build --preset release -j"$jobs"
    cmake --install build-release
    cmake -S examples/consumer -B "$prefix/consumer-build" -DCMAKE_PREFIX_PATH="$prefix"
    cmake --build "$prefix/consumer-build"
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig" pkg-config --cflags --libs nnc
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
