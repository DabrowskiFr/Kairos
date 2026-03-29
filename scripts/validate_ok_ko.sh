#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_repo_root="$(cd "$script_dir/.." && pwd)"

repo_root="${1:-$default_repo_root}"
timeout_s="${2:-5}"
suite_mode="${3:-legacy}"
file_timeout_s="${4:-60}"
suite_subset="${5:-all}"
single_file="${6:-}"
cli="$repo_root/_build/default/bin/cli/main.exe"
report_dir="$repo_root/_build/validation"
parallel_jobs="${VALIDATE_JOBS:-4}"
scale_parallel_timeouts="${VALIDATE_SCALE_TIMEOUTS:-1}"

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

effective_goal_timeout_s() {
  local jobs="$parallel_jobs"
  if ! [[ "$jobs" =~ ^[0-9]+$ ]] || (( jobs < 1 )); then
    jobs=1
  fi
  if [[ "$scale_parallel_timeouts" == "0" ]] || (( jobs <= 1 )); then
    printf '%s\n' "$timeout_s"
  else
    printf '%s\n' $((timeout_s * jobs))
  fi
}

run_cli_dump_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"

  local goal_timeout
  goal_timeout="$(effective_goal_timeout_s)"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" "$@" --dump-proof-traces-json - --proof-traces-failed-only --timeout-s "$goal_timeout"
  then
    local status=0
    rm -rf "$task_root"
    return "$status"
  else
    local status=$?
    rm -rf "$task_root"
    return "$status"
  fi
}

run_cli_prove_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  local file="$3"

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"
  local goal_timeout
  goal_timeout="$(effective_goal_timeout_s)"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" --prove --timeout-s "$goal_timeout" "$file"
  then
    local status=0
    rm -rf "$task_root"
    return "$status"
  else
    local status=$?
    rm -rf "$task_root"
    return "$status"
  fi
}

compile_kobjs_for_dir() {
  local dir="$1"
  local filter="${2:-all}"
  if [[ "$filter" == "without_calls" ]]; then
    return 0
  fi
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

collect_suite_files() {
  local dir="$1"
  local filter="$2"
  local mode="$3"
  local file
  case "$mode" in
    ok)
      for file in "$dir"/*.kairos; do
        [ -e "$file" ] || continue
        case "$filter" in
          with_calls)    has_import "$file" || continue ;;
          without_calls) has_import "$file" && continue ;;
        esac
        printf '%s\n' "$file"
      done
      ;;
    ko)
      for file in "$dir"/*__bad_*.kairos; do
        [ -e "$file" ] || continue
        case "$filter" in
          with_calls)    has_import "$file" || continue ;;
          without_calls) has_import "$file" && continue ;;
        esac
        printf '%s\n' "$file"
      done
      ;;
    *)
      echo "Unknown collection mode: $mode" >&2
      exit 2
      ;;
  esac
}

run_classifications_parallel() {
  local classify_fn="$1"
  local report_file="$2"
  shift 2
  local files=("$@")
  local jobs="$parallel_jobs"
  local tmpdir
  tmpdir="$(mktemp -d)"
  local -a pids=()
  local idx=0
  local failed=0
  local file

  if [[ "${#files[@]}" -eq 0 ]]; then
    : > "$report_file"
    rmdir "$tmpdir"
    return 0
  fi

  flush_parts() {
    local part
    for part in "$tmpdir"/*.tsv; do
      [ -e "$part" ] || continue
      cat "$part" >> "$report_file"
      rm -f "$part"
    done
  }

  if ! [[ "$jobs" =~ ^[0-9]+$ ]] || (( jobs < 1 )); then
    jobs=1
  fi

  : > "$report_file"

  for file in "${files[@]}"; do
    local slot
    slot="$(printf '%06d' "$idx")"
    (
      "$classify_fn" "$file" > "$tmpdir/$slot.tsv"
    ) &
    pids+=("$!")
    idx=$((idx + 1))

    if (( ${#pids[@]:-0} >= jobs )); then
      local pid
      for pid in "${pids[@]:-}"; do
        [[ -n "$pid" ]] || continue
        if ! wait "$pid"; then
          failed=1
        fi
      done
      flush_parts
      pids=()
    fi
  done

  local pid
  for pid in "${pids[@]:-}"; do
    [[ -n "$pid" ]] || continue
    if ! wait "$pid"; then
      failed=1
    fi
  done

  flush_parts

  if (( failed != 0 )); then
    rm -rf "$tmpdir"
    echo "Parallel classification failed" >&2
    exit 1
  fi
  rm -rf "$tmpdir"
}

read_files_into_array() {
  local __var_name="$1"
  shift
  local -a __items=()
  while IFS= read -r line; do
    __items+=("$line")
  done < <("$@")
  eval "$__var_name=(\"\${__items[@]}\")"
}

classify_ok() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if run_cli_prove_with_isolation "$tmp" "$tmp.stderr" "$file"; then
    printf '%s\tOK\t0\n' "$file"
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
      if [[ -z "$err" ]]; then
        err="prove_failed"
      fi
      printf '%s\tFAILED\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$tmp.stderr"
}

classify_ko() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if run_cli_prove_with_isolation "$tmp" "$tmp.stderr" "$file"; then
    printf '%s\tUNEXPECTED_GREEN\t0\n' "$file"
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
      if [[ -z "$err" ]]; then
        err="prove_failed"
      fi
      printf '%s\tINVALID\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$tmp.stderr"
}

# run_suite NAME OK_DIR KO_DIR [FILTER] [SUBSET]
# FILTER: "all" (default) | "with_calls" | "without_calls"
# SUBSET: "all" (default) | "ok" | "ko"
run_suite() {
  local suite_name="$1"
  local ok_dir="$2"
  local ko_dir="$3"
  local filter="${4:-all}"
  local subset="${5:-all}"
  local ok_report="$report_dir/${suite_name}_ok_report.tsv"
  local ko_report="$report_dir/${suite_name}_ko_report.tsv"
  local summary_report="$report_dir/${suite_name}_summary.txt"
  local ok_report_tmp="$ok_report.tmp"
  local ko_report_tmp="$ko_report.tmp"
  local summary_report_tmp="$summary_report.tmp"

  case "$subset" in
    all|ok|ko) ;;
    *)
      echo "Unknown subset: $subset" >&2
      echo "Expected one of: all, ok, ko" >&2
      exit 2
      ;;
  esac

  if [[ "$subset" == "all" || "$subset" == "ok" ]]; then
    compile_kobjs_for_dir "$ok_dir" "$filter"
    read_files_into_array ok_files collect_suite_files "$ok_dir" "$filter" ok
    run_classifications_parallel classify_ok "$ok_report_tmp" "${ok_files[@]}"
    mv "$ok_report_tmp" "$ok_report"
  else
    : > "$ok_report"
  fi

  if [[ "$subset" == "all" || "$subset" == "ko" ]]; then
    compile_kobjs_for_dir "$ko_dir" "$filter"
    read_files_into_array ko_files collect_suite_files "$ko_dir" "$filter" ko
    run_classifications_parallel classify_ko "$ko_report_tmp" "${ko_files[@]}"
    mv "$ko_report_tmp" "$ko_report"
  else
    : > "$ko_report"
  fi

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
    echo "subset=$subset"
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
    run_suite "legacy" "$ok_dir" "$ko_dir" "all" "$suite_subset"
    ;;
  with_calls)
    run_suite "with_calls" "$ok_dir" "$ko_dir" "with_calls" "$suite_subset"
    ;;
  without_calls)
    run_suite "without_calls" "$ok_dir" "$ko_dir" "without_calls" "$suite_subset"
    ;;
  split)
    run_suite "with_calls" "$ok_dir" "$ko_dir" "with_calls" "$suite_subset"
    echo
    run_suite "without_calls" "$ok_dir" "$ko_dir" "without_calls" "$suite_subset"
    ;;
  single_ok)
    single_file="${5:-}"
    if [[ -z "$single_file" ]]; then
      echo "single_ok requires a file path as 5th argument" >&2
      exit 2
    fi
    classify_ok "$single_file"
    ;;
  single_ko)
    single_file="${5:-}"
    if [[ -z "$single_file" ]]; then
      echo "single_ko requires a file path as 5th argument" >&2
      exit 2
    fi
    classify_ko "$single_file"
    ;;
  *)
    echo "Unknown suite mode: $suite_mode" >&2
    echo "Expected one of: legacy, with_calls, without_calls, split, single_ok, single_ko" >&2
    echo "Usage: $0 [repo_root] [timeout_per_goal_s] [suite_mode] [timeout_per_file_s] [subset=all|ok|ko]" >&2
    echo "   or: $0 [repo_root] [timeout_per_goal_s] single_ok [timeout_per_file_s] [file]" >&2
    echo "   or: $0 [repo_root] [timeout_per_goal_s] single_ko [timeout_per_file_s] [file]" >&2
    exit 2
    ;;
esac
