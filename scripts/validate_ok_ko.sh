#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-/Users/fredericdabrowski/Repos/kairos/kairos-dev}"
timeout_s="${2:-5}"
suite_mode="${3:-legacy}"
file_timeout_s="${4:-60}"
single_file="${5:-}"
cli="$repo_root/_build/default/bin/cli/main.exe"
report_dir="$repo_root/_build/validation"

mkdir -p "$report_dir"

# Returns 0 if the file uses import (with_calls), 1 otherwise (without_calls)
has_import() {
  rg -q '^import ' "$1"
}

stderr_has_fatal_error() {
  local stderr_file="$1"
  rg -q '(^| )kairos: |Field [^[:space:]]+ is used more than once in a record|Fatal error:|exception' "$stderr_file"
}

stderr_summary() {
  local stderr_file="$1"
  awk '
    /^[[:space:]]*$/ { next }
    /^Warning([,:]|[[:space:]])/ { next }
    { print }
  ' "$stderr_file" \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]\+/ /g' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//'
}

run_with_file_timeout() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  perl -e '
    use strict;
    use warnings;
    my ($timeout_s, $stdout_path, $stderr_path, @cmd) = @ARGV;
    open STDOUT, ">", $stdout_path or die "open stdout: $!";
    open STDERR, ">", $stderr_path or die "open stderr: $!";
    my $child = fork();
    die "fork failed: $!" unless defined $child;
    if ($child == 0) {
      exec @cmd or die "exec failed: $!";
    }
    local $SIG{ALRM} = sub {
      kill "TERM", $child;
      select undef, undef, undef, 0.2;
      kill "KILL", $child;
      waitpid($child, 0);
      exit 124;
    };
    alarm($timeout_s);
    my $done = waitpid($child, 0);
    alarm(0);
    if ($done == -1) {
      exit 125;
    }
    if ($? == -1) {
      exit 125;
    }
    if ($? & 127) {
      exit 128 + ($? & 127);
    }
    exit($? >> 8);
  ' "$file_timeout_s" "$stdout_file" "$stderr_file" "$@"
}

compile_kobjs_for_dir() {
  local dir="$1"
  local file
  for pass in 1 2; do
    for file in "$dir"/*.kairos; do
      [ -e "$file" ] || continue
      if [[ "$file" == *"__bad_"* ]]; then
        continue
      fi
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
  if run_with_file_timeout "$tmp" "$tmp.stderr" opam exec -- "$cli" "$file" --dump-proof-traces-json - --proof-traces-failed-only --timeout-s "$timeout_s"; then
    local failed_count
    failed_count="$(jq 'length' < "$tmp")"
    if [[ "$failed_count" == "0" ]]; then
      printf '%s\tOK\t0\n' "$file"
    else
      printf '%s\tFAILED\t%s\n' "$file" "$failed_count"
    fi
  else
    local status=$?
    local err
    err="$(stderr_summary "$tmp.stderr")"
    if [[ "$status" == "124" ]]; then
      if [[ -n "$err" ]] && stderr_has_fatal_error "$tmp.stderr"; then
        printf '%s\tERROR\t%s\n' "$file" "$err"
      else
        printf '%s\tTIMEOUT\tfile_timeout_%ss\n' "$file" "$file_timeout_s"
      fi
    else
      printf '%s\tERROR\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$tmp.stderr"
}

classify_ko() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if run_with_file_timeout "$tmp" "$tmp.stderr" opam exec -- "$cli" "$file" --dump-proof-traces-json - --proof-traces-failed-only --timeout-s "$timeout_s"; then
    local failed_count
    failed_count="$(jq 'length' < "$tmp")"
    if [[ "$failed_count" == "0" ]]; then
      printf '%s\tUNEXPECTED_GREEN\t0\n' "$file"
    else
      local status
      status="$(jq -r '
        if any(.[]; .status == "failure") then
          "INVALID"
        elif any(.[]; (.status == "timeout") or (.solver_status == "timeout") or (.solver_detail == "solver_timeout")) then
          "TIMEOUT"
        else
          "INVALID"
        end
      ' < "$tmp")"
      printf '%s\t%s\t%s\n' "$file" "$status" "$failed_count"
    fi
  else
    local status=$?
    local err
    err="$(stderr_summary "$tmp.stderr")"
    if [[ "$status" == "124" ]]; then
      if [[ -n "$err" ]] && stderr_has_fatal_error "$tmp.stderr"; then
        printf '%s\tINVALID\t%s\n' "$file" "$err"
      else
        printf '%s\tTIMEOUT\tfile_timeout_%ss\n' "$file" "$file_timeout_s"
      fi
    else
      printf '%s\tINVALID\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$tmp.stderr"
}

# run_suite NAME OK_DIR KO_DIR [FILTER]
# FILTER: "all" (default) | "with_calls" | "without_calls"
run_suite() {
  local suite_name="$1"
  local ok_dir="$2"
  local ko_dir="$3"
  local filter="${4:-all}"
  local ok_report="$report_dir/${suite_name}_ok_report.tsv"
  local ko_report="$report_dir/${suite_name}_ko_report.tsv"
  local summary_report="$report_dir/${suite_name}_summary.txt"
  local ok_report_tmp="$ok_report.tmp"
  local ko_report_tmp="$ko_report.tmp"
  local summary_report_tmp="$summary_report.tmp"

  {
    compile_kobjs_for_dir "$ok_dir"
    for file in "$ok_dir"/*.kairos; do
      [ -e "$file" ] || continue
      case "$filter" in
        with_calls)    has_import "$file" || continue ;;
        without_calls) has_import "$file" && continue ;;
      esac
      classify_ok "$file"
    done
  } > "$ok_report_tmp"
  mv "$ok_report_tmp" "$ok_report"

  {
    compile_kobjs_for_dir "$ko_dir"
    for file in "$ko_dir"/*__bad_*.kairos; do
      [ -e "$file" ] || continue
      case "$filter" in
        with_calls)    has_import "$file" || continue ;;
        without_calls) has_import "$file" && continue ;;
      esac
      classify_ko "$file"
    done
  } > "$ko_report_tmp"
  mv "$ko_report_tmp" "$ko_report"

  local ok_total ok_green ok_non_green ko_total ko_invalid ko_timeout ko_false_green
  ok_total="$(wc -l < "$ok_report" | tr -d ' ')"
  ok_green="$(awk -F '\t' '$2 == "OK" { c++ } END { print c + 0 }' "$ok_report")"
  ok_non_green="$(awk -F '\t' '$2 != "OK" { c++ } END { print c + 0 }' "$ok_report")"

  ko_total="$(wc -l < "$ko_report" | tr -d ' ')"
  ko_invalid="$(awk -F '\t' '$2 == "INVALID" { c++ } END { print c + 0 }' "$ko_report")"
  ko_timeout="$(awk -F '\t' '$2 == "TIMEOUT" { c++ } END { print c + 0 }' "$ko_report")"
  ko_false_green="$(awk -F '\t' '$2 == "UNEXPECTED_GREEN" { c++ } END { print c + 0 }' "$ko_report")"

  {
    echo "suite=$suite_name"
    echo "timeout_per_goal=$timeout_s"
    echo "timeout_per_file=$file_timeout_s"
    echo "ok_total=$ok_total"
    echo "ok_green=$ok_green"
    echo "ok_non_green=$ok_non_green"
    echo "ko_total=$ko_total"
    echo "ko_invalid=$ko_invalid"
    echo "ko_timeout=$ko_timeout"
    echo "ko_false_green=$ko_false_green"
    echo "ok_report=$ok_report"
    echo "ko_report=$ko_report"
  } > "$summary_report_tmp"
  mv "$summary_report_tmp" "$summary_report"

  cat "$summary_report"
}

ok_dir="$repo_root/tests/ok"
ko_dir="$repo_root/tests/ko"

case "$suite_mode" in
  legacy)
    run_suite "legacy" "$ok_dir" "$ko_dir"
    ;;
  with_calls)
    run_suite "with_calls" "$ok_dir" "$ko_dir" "with_calls"
    ;;
  without_calls)
    run_suite "without_calls" "$ok_dir" "$ko_dir" "without_calls"
    ;;
  split)
    run_suite "with_calls" "$ok_dir" "$ko_dir" "with_calls"
    echo
    run_suite "without_calls" "$ok_dir" "$ko_dir" "without_calls"
    ;;
  single_ok)
    if [[ -z "$single_file" ]]; then
      echo "single_ok requires a file path as 5th argument" >&2
      exit 2
    fi
    classify_ok "$single_file"
    ;;
  single_ko)
    if [[ -z "$single_file" ]]; then
      echo "single_ko requires a file path as 5th argument" >&2
      exit 2
    fi
    classify_ko "$single_file"
    ;;
  *)
    echo "Unknown suite mode: $suite_mode" >&2
    echo "Expected one of: legacy, with_calls, without_calls, split, single_ok, single_ko" >&2
    echo "Usage: $0 [repo_root] [timeout_per_goal_s] [suite_mode] [timeout_per_file_s] [single_file]" >&2
    exit 2
    ;;
esac
