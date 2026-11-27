#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

spec_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$spec_dir/../.." && pwd -P)"
cache_dir="${TLA_CACHE_DIR:-$repo_dir/work/tla-cache}"
output_dir="${TLA_OUTPUT_DIR:-$repo_dir/work/tla-results}"
java_bin="${JAVA_BIN:-java}"
version=v1.7.4
checksum=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
mkdir -p -- "$cache_dir" "$output_dir"
cache_dir="$(cd -- "$cache_dir" && pwd -P)"
output_dir="$(cd -- "$output_dir" && pwd -P)"
run_dir="$(mktemp -d "$output_dir/run.XXXXXX")"
jar="$cache_dir/tla2tools-$version.jar"

verify_jar() {
    local digest
    digest="$(shasum -a 256 "$1")" || return 1
    if [[ ${digest%% *} != "$checksum" ]]; then
        printf 'SHA-256 mismatch for %s\n' "$1" >&2
        return 1
    fi
}

printf 'TLC logs and traces: %s\n' "$run_dir"
"$java_bin" -version
if [[ ! -f "$jar" ]]; then
    curl -fsSL --connect-timeout 15 --max-time 90 \
        "https://github.com/tlaplus/tlaplus/releases/download/$version/tla2tools.jar" \
        -o "$run_dir/tla2tools.jar"
    verify_jar "$run_dir/tla2tools.jar"
    mv -- "$run_dir/tla2tools.jar" "$jar"
fi
verify_jar "$jar"
printf 'Verified TLC %s SHA-256 %s\n' "$version" "$checksum"

positive=("$spec_dir"/*.cfg)
negative=("$spec_dir"/negative/*.cfg)
if (( ${#positive[@]} == 0 || ${#negative[@]} == 0 )); then
    printf 'TLC requires both positive and negative configs.\n' >&2
    exit 1
fi

run_config() {
    local config="$1" name module kind property expected expected_exit result=0 log
    name="$(basename -- "$config" .cfg)"
    module="${name%%-*}"
    log="$run_dir/$name.log"
    if [[ "$config" == "$spec_dir"/negative/* ]]; then
        if [[ ! "$name" =~ ^[[:alnum:]_]+-(Invariant|Action)-([[:alnum:]_]+)(-.+)?$ ]]; then
            printf 'Bad negative config name: %s\n' "$name" >&2
            return 1
        fi
        kind="${BASH_REMATCH[1]}"
        property="${BASH_REMATCH[2]}"
        case "$kind" in
            Invariant) expected_exit=12; expected="Invariant $property" ;;
            Action) expected_exit=13; expected="Action property $property" ;;
        esac
    fi
    if [[ ! -f "$spec_dir/$module.tla" ]]; then
        printf 'Missing module for %s: %s.tla\n' "$name" "$module" >&2
        return 1
    fi
    "$java_bin" -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers 1 -deadlock \
        -metadir "$run_dir/$name" -config "$config" "$spec_dir/$module.tla" >"$log" 2>&1 || result=$?
    if [[ ${expected_exit:-0} == 0 ]]; then
        if [[ "$result" == 0 ]] && grep -Fq 'Model checking completed. No error has been found.' "$log"; then
            printf 'PASS %s\n' "$name"
            grep -E 'states generated, [0-9]+ distinct states found.*left on queue\.' "$log" | tail -n 1
            return 0
        fi
    elif [[ "$result" == "$expected_exit" ]] && grep -Fxq \
        -e "Error: $expected is violated." \
        -e "Error: $expected is violated by the initial state:" "$log"; then
        printf 'PASS %s (expected violation: %s, TLC exit %s)\n' "$name" "$property" "$result"
        return 0
    fi
    printf 'FAIL %s (TLC exit %s)\n' "$name" "$result" >&2
    cat "$log" >&2
    return 1
}

cd -- "$run_dir"
failures=0
for config in "${positive[@]}" "${negative[@]}"; do
    run_config "$config" || failures=$((failures + 1))
done
printf 'TLC: %s positive, %s negative, %s unexpected results\n' \
    "${#positive[@]}" "${#negative[@]}" "$failures"
(( failures == 0 ))
