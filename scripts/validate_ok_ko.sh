#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_repo_root="$(cd "$script_dir/.." && pwd)"

repo_root="$default_repo_root"
timeout_s=5
file_timeout_s=60
subset="all"
parallel_jobs=4
single_ok_file=""
single_ko_file=""

usage() {
  cat <<'EOF'
Usage:
  validate_ok_ko.sh [options]

Options:
  --repo-root <path>       Repository root (default: script parent)
  --timeout-goal <sec>     Timeout per VC goal in seconds (default: 5)
  --timeout-file <sec>     Hard timeout per file in seconds (default: 60)
  --jobs <n>               Parallel jobs for file classification (default: 4)
  --subset <all|ok|ko>     Run both suites or only one subset (default: all)
  --single-ok <file>       Classify exactly one expected-green file
  --single-ko <file>       Classify exactly one expected-red file
  --help                   Show this help

Notes:
  - This script now validates only the without_calls corpus.
  - Timeouts are not scaled with parallelism.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
    --timeout-goal)
      timeout_s="${2:-}"
      shift 2
      ;;
    --timeout-file)
      file_timeout_s="${2:-}"
      shift 2
      ;;
    --jobs)
      parallel_jobs="${2:-}"
      shift 2
      ;;
    --subset)
      subset="${2:-}"
      shift 2
      ;;
    --single-ok)
      single_ok_file="${2:-}"
      shift 2
      ;;
    --single-ko)
      single_ko_file="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$single_ok_file" && -n "$single_ko_file" ]]; then
  echo "Use only one of --single-ok or --single-ko." >&2
  exit 2
fi

if ! [[ "$timeout_s" =~ ^[0-9]+$ ]] || (( timeout_s < 1 )); then
  echo "--timeout-goal must be a positive integer." >&2
  exit 2
fi

if ! [[ "$file_timeout_s" =~ ^[0-9]+$ ]] || (( file_timeout_s < 1 )); then
  echo "--timeout-file must be a positive integer." >&2
  exit 2
fi

if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]] || (( parallel_jobs < 1 )); then
  echo "--jobs must be a positive integer." >&2
  exit 2
fi

case "$subset" in
  all|ok|ko) ;;
  *)
    echo "--subset must be one of: all, ok, ko." >&2
    exit 2
    ;;
esac

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

run_cli_dump_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" "$@" --dump-proof-traces-json - --proof-traces-failed-only --timeout-s "$timeout_s"
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

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" --prove --timeout-s "$timeout_s" "$file"
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

collect_suite_files() {
  local dir="$1"
  local mode="$2"
  local file
  case "$mode" in
    ok)
      for file in "$dir"/*.kairos; do
        [ -e "$file" ] || continue
        has_import "$file" && continue
        printf '%s\n' "$file"
      done
      ;;
    ko)
      for file in "$dir"/*__bad_*.kairos; do
        [ -e "$file" ] || continue
        has_import "$file" && continue
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

run_suite() {
  local suite_name="$1"
  local ok_dir="$2"
  local ko_dir="$3"
  local subset="$4"
  local ok_report="$report_dir/${suite_name}_ok_report.tsv"
  local ko_report="$report_dir/${suite_name}_ko_report.tsv"
  local summary_report="$report_dir/${suite_name}_summary.txt"
  local ok_report_tmp="$ok_report.tmp"
  local ko_report_tmp="$ko_report.tmp"
  local summary_report_tmp="$summary_report.tmp"

  if [[ "$subset" == "all" || "$subset" == "ok" ]]; then
    read_files_into_array ok_files collect_suite_files "$ok_dir" ok
    run_classifications_parallel classify_ok "$ok_report_tmp" "${ok_files[@]}"
    mv "$ok_report_tmp" "$ok_report"
  else
    : > "$ok_report"
  fi

  if [[ "$subset" == "all" || "$subset" == "ko" ]]; then
    read_files_into_array ko_files collect_suite_files "$ko_dir" ko
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
    echo "jobs=$parallel_jobs"
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

if [[ -n "$single_ok_file" ]]; then
  classify_ok "$single_ok_file"
  exit 0
fi

if [[ -n "$single_ko_file" ]]; then
  classify_ko "$single_ko_file"
  exit 0
fi

run_suite "without_calls" "$ok_dir" "$ko_dir" "$subset"
