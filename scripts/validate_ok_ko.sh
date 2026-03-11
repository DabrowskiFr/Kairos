#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-/Users/fredericdabrowski/Repos/kairos/kairos-dev}"
timeout_s="${2:-5}"
cli="$repo_root/_build/default/bin/cli/main.exe"
ok_dir="$repo_root/tests/ok/inputs"
ko_dir="$repo_root/tests/ko/inputs"
report_dir="$repo_root/_build/validation"

mkdir -p "$report_dir"

ok_report="$report_dir/ok_report.tsv"
ko_report="$report_dir/ko_report.tsv"
summary_report="$report_dir/summary.txt"

compile_kobjs_for_dir() {
  local dir="$1"
  local file
  for pass in 1 2; do
    for file in "$dir"/*.kairos; do
      [ -e "$file" ] || continue
      if [[ "$pass" == "1" ]] && rg -q '^import ' "$file"; then
        continue
      fi
      if [[ "$pass" == "2" ]] && ! rg -q '^import ' "$file"; then
        continue
      fi
      opam exec -- "$cli" "$file" --emit-kobj "${file%.kairos}.kobj" >/dev/null
    done
  done
}

classify_ok() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if opam exec -- "$cli" "$file" --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 200 --timeout-s "$timeout_s" >"$tmp" 2>"$tmp.stderr"; then
    local failed_count
    failed_count="$(jq 'length' < "$tmp")"
    if [[ "$failed_count" == "0" ]]; then
      printf '%s\tOK\t0\n' "$file"
    else
      printf '%s\tFAILED\t%s\n' "$file" "$failed_count"
    fi
  else
    local err
    err="$(tr '\n' ' ' < "$tmp.stderr" | sed 's/[[:space:]]\+/ /g' | sed 's/[[:space:]]*$//')"
    printf '%s\tERROR\t%s\n' "$file" "$err"
  fi
  rm -f "$tmp" "$tmp.stderr"
}

classify_ko() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if opam exec -- "$cli" "$file" --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 200 --timeout-s "$timeout_s" >"$tmp" 2>"$tmp.stderr"; then
    local failed_count
    failed_count="$(jq 'length' < "$tmp")"
    if [[ "$failed_count" == "0" ]]; then
      printf '%s\tUNEXPECTED_GREEN\t0\n' "$file"
    else
      local status
      status="$(jq -r '
        if any(.[]; (.status == "timeout") or (.solver_status == "timeout") or (.solver_detail == "solver_timeout")) then
          "TIMEOUT"
        else
          "INVALID"
        end
      ' < "$tmp")"
      printf '%s\t%s\t%s\n' "$file" "$status" "$failed_count"
    fi
  else
    local err
    err="$(tr '\n' ' ' < "$tmp.stderr" | sed 's/[[:space:]]\+/ /g' | sed 's/[[:space:]]*$//')"
    printf '%s\tINVALID\t%s\n' "$file" "$err"
  fi
  rm -f "$tmp" "$tmp.stderr"
}

{
  compile_kobjs_for_dir "$ok_dir"
  for file in "$ok_dir"/*.kairos; do
    classify_ok "$file"
  done
} > "$ok_report"

{
  compile_kobjs_for_dir "$ko_dir"
  for file in "$ko_dir"/*__bad_*.kairos; do
    classify_ko "$file"
  done
} > "$ko_report"

ok_total="$(wc -l < "$ok_report" | tr -d ' ')"
ok_green="$(awk -F '\t' '$2 == "OK" { c++ } END { print c + 0 }' "$ok_report")"
ok_non_green="$(awk -F '\t' '$2 != "OK" { c++ } END { print c + 0 }' "$ok_report")"

ko_total="$(wc -l < "$ko_report" | tr -d ' ')"
ko_invalid="$(awk -F '\t' '$2 == "INVALID" { c++ } END { print c + 0 }' "$ko_report")"
ko_timeout="$(awk -F '\t' '$2 == "TIMEOUT" { c++ } END { print c + 0 }' "$ko_report")"
ko_false_green="$(awk -F '\t' '$2 == "UNEXPECTED_GREEN" { c++ } END { print c + 0 }' "$ko_report")"

{
  echo "timeout_per_goal=$timeout_s"
  echo "ok_total=$ok_total"
  echo "ok_green=$ok_green"
  echo "ok_non_green=$ok_non_green"
  echo "ko_total=$ko_total"
  echo "ko_invalid=$ko_invalid"
  echo "ko_timeout=$ko_timeout"
  echo "ko_false_green=$ko_false_green"
  echo "ok_report=$ok_report"
  echo "ko_report=$ko_report"
} > "$summary_report"

cat "$summary_report"
