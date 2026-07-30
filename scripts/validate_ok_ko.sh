#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_repo_root="$(cd "$script_dir/.." && pwd)"

repo_root="$default_repo_root"
cli_override=""
timeout_s=5
negative_timeout_s=1
file_timeout_s=60
file_timeout_exit=200
subset="all"
parallel_jobs=4
single_ok_file=""
single_ko_file=""
frontend_only=false

usage() {
  cat <<'EOF'
Usage:
  validate_ok_ko.sh [options]

Options:
  --repo-root <path>       Repository root (default: script parent)
  --cli <path>             Prebuilt Kairos CLI (default: repository build)
  --timeout-goal <sec>     Timeout per VC goal in seconds (default: 5)
  --timeout-negative-goal <sec>
                           Timeout per proof-negative goal (default: 1)
  --timeout-file <sec>     Hard timeout per file in seconds (default: 60)
  --jobs <n>               Parallel jobs for file classification (default: 4)
  --subset <all|ok|ko>     Run both suites or only one subset (default: all)
  --single-ok <file>       Classify exactly one expected-green file
  --single-ko <file>       Classify exactly one expected-red file
  --frontend-only          Check the whole corpus at the frontend boundary:
                           OK and proof-negative files must be accepted;
                           frontend-negative files must be rejected
  --help                   Show this help

Notes:
  - OK files must complete with every proof goal valid.
  - tests/ko/expectations.tsv declares whether each KO is expected at the
    frontend, pipeline, or proof stage.
  - Proof-negative files must expose an invalid or bounded-timeout goal.
  - Harness timeouts, backend crashes, false greens, and red OK files fail the
    campaign.
  - Timeouts are not scaled with parallelism.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
    --cli)
      cli_override="${2:-}"
      shift 2
      ;;
    --timeout-goal)
      timeout_s="${2:-}"
      shift 2
      ;;
    --timeout-negative-goal)
      negative_timeout_s="${2:-}"
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
    --frontend-only)
      frontend_only=true
      shift
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

if ! [[ "$negative_timeout_s" =~ ^[0-9]+$ ]] || (( negative_timeout_s < 1 )); then
  echo "--timeout-negative-goal must be a positive integer." >&2
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

if [[ -n "$cli_override" ]]; then
  cli="$cli_override"
else
  cli="$repo_root/_build/default/bin/cli/kairos.exe"
fi
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
      exit 200;
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

run_cli_negative_proof_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  local goals_file="$3"
  local file="$4"

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" --prove --proof-jobs=1 \
      --stop-on-first-nonvalid --timeout-s "$negative_timeout_s" \
      --dump-goals="$goals_file" "$file"
  then
    local command_exit=0
    rm -rf "$task_root"
    return "$command_exit"
  else
    local command_exit=$?
    rm -rf "$task_root"
    return "$command_exit"
  fi
}

run_cli_frontend_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  local file="$3"

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" --check-frontend "$file"
  then
    local command_exit=0
    rm -rf "$task_root"
    return "$command_exit"
  else
    local command_exit=$?
    rm -rf "$task_root"
    return "$command_exit"
  fi
}

run_cli_pipeline_with_isolation() {
  local stdout_file="$1"
  local stderr_file="$2"
  local file="$3"

  local task_root
  task_root="$(mktemp -d)"
  mkdir -p "$task_root/tmp" "$task_root/xdg-cache"

  if run_with_file_timeout "$stdout_file" "$stderr_file" \
    env TMPDIR="$task_root/tmp" XDG_CACHE_HOME="$task_root/xdg-cache" \
    opam exec -- "$cli" "$file"
  then
    local command_exit=0
    rm -rf "$task_root"
    return "$command_exit"
  else
    local command_exit=$?
    rm -rf "$task_root"
    return "$command_exit"
  fi
}

ko_stage_for_file() {
  local file="$1"
  local base
  base="$(basename "$file")"
  awk -F '\t' -v base="$base" '
    $0 !~ /^#/ && $1 == base {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$ko_manifest"
}

validate_ko_manifest() {
  local duplicate
  duplicate="$(
    awk -F '\t' '
      $0 !~ /^#/ && NF > 0 {
        count[$1] += 1
      }
      END {
        for (file in count) {
          if (count[file] != 1) {
            print file
            exit
          }
        }
      }
    ' "$ko_manifest"
  )"
  if [[ -n "$duplicate" ]]; then
    echo "Duplicate KO manifest entry: $duplicate" >&2
    return 1
  fi

  local base stage _coverage file
  while IFS=$'\t' read -r base stage _coverage; do
    [[ -n "$base" && "${base:0:1}" != "#" ]] || continue
    case "$stage" in
      frontend|pipeline|proof) ;;
      *)
        echo "Invalid expected stage '$stage' for $base." >&2
        return 1
        ;;
    esac
    if [[ ! -f "$ko_dir/$base" ]]; then
      echo "KO manifest references missing file: $base" >&2
      return 1
    fi
  done < "$ko_manifest"

  for file in "$ko_dir"/*.kairos; do
    [ -e "$file" ] || continue
    if ! ko_stage_for_file "$file" >/dev/null; then
      echo "KO file missing from expectations.tsv: $(basename "$file")" >&2
      return 1
    fi
  done
}

collect_suite_files() {
  local dir="$1"
  local mode="$2"
  local file base stage _coverage
  case "$mode" in
    ok)
      for file in "$dir"/*.kairos; do
        [ -e "$file" ] || continue
        has_import "$file" && continue
        printf '%s\n' "$file"
      done
      ;;
    ko)
      while IFS=$'\t' read -r base stage _coverage; do
        [[ -n "$base" && "${base:0:1}" != "#" ]] || continue
        file="$dir/$base"
        has_import "$file" && continue
        printf '%s\n' "$file"
      done < "$ko_manifest"
      ;;
    ko_proof)
      while IFS=$'\t' read -r base stage _coverage; do
        [[ -n "$base" && "${base:0:1}" != "#" ]] || continue
        [[ "$stage" == "proof" ]] || continue
        file="$dir/$base"
        has_import "$file" && continue
        printf '%s\n' "$file"
      done < "$ko_manifest"
      ;;
    ko_frontend)
      while IFS=$'\t' read -r base stage _coverage; do
        [[ -n "$base" && "${base:0:1}" != "#" ]] || continue
        [[ "$stage" == "frontend" ]] || continue
        file="$dir/$base"
        has_import "$file" && continue
        printf '%s\n' "$file"
      done < "$ko_manifest"
      ;;
    ko_pipeline)
      while IFS=$'\t' read -r base stage _coverage; do
        [[ -n "$base" && "${base:0:1}" != "#" ]] || continue
        [[ "$stage" == "pipeline" ]] || continue
        file="$dir/$base"
        has_import "$file" && continue
        printf '%s\n' "$file"
      done < "$ko_manifest"
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

    if (( ${#pids[@]} >= jobs )); then
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
    if [[ "$status" == "$file_timeout_exit" ]]; then
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
  local stderr_file="$tmp.stderr"
  local goals_file="$tmp.goals.csv"
  local stage
  stage="$(ko_stage_for_file "$file")"

  if [[ "$stage" == "proof" ]]; then
    if run_cli_negative_proof_with_isolation \
      "$tmp" "$stderr_file" "$goals_file" "$file"
    then
      printf '%s\tUNEXPECTED_GREEN\tproof_completed\n' "$file"
    else
      local command_exit=$?
      local first_nonvalid=""
      if [[ -s "$goals_file" ]]; then
        first_nonvalid="$(
          awk -F ',' \
            'NR > 1 && $3 != "valid" && $3 != "proved" {
               print $2 "\t" tolower($3);
               exit
             }' \
            "$goals_file"
        )"
      fi
      if [[ -n "$first_nonvalid" ]]; then
        local goal_name proof_status
        goal_name="${first_nonvalid%%$'\t'*}"
        proof_status="${first_nonvalid##*$'\t'}"
        case "$proof_status" in
          invalid|timeout)
            printf '%s\tPROOF_REJECTED\t%s:%s\n' \
              "$file" "$proof_status" "$goal_name"
            ;;
          *)
            printf '%s\tERROR\tunexpected_solver_status:%s:%s\n' \
              "$file" "$proof_status" "$goal_name"
            ;;
        esac
      elif [[ "$command_exit" == "$file_timeout_exit" ]]; then
        printf '%s\tHARNESS_TIMEOUT\tfile_timeout_%ss\n' \
          "$file" "$file_timeout_s"
      else
        local err
        err="$(stderr_summary "$stderr_file")"
        [[ -n "$err" ]] || err="proof_failed_without_goal_status"
        printf '%s\tERROR\t%s\n' "$file" "$err"
      fi
    fi
  elif [[ "$stage" == "frontend" ]]; then
    if run_cli_frontend_with_isolation "$tmp" "$stderr_file" "$file"; then
      printf '%s\tUNEXPECTED_GREEN\tfrontend_completed\n' "$file"
    else
      local command_exit=$?
      local err
      err="$(stderr_summary "$stderr_file")"
      if [[ "$command_exit" == "$file_timeout_exit" ]]; then
        printf '%s\tHARNESS_TIMEOUT\tfile_timeout_%ss\n' \
          "$file" "$file_timeout_s"
      elif [[ -n "$err" ]] && stderr_has_fatal_error "$stderr_file"; then
        printf '%s\tFRONTEND_REJECTED\t%s\n' "$file" "$err"
      else
        [[ -n "$err" ]] || err="frontend_failed_without_diagnostic"
        printf '%s\tERROR\t%s\n' "$file" "$err"
      fi
    fi
  elif [[ "$stage" == "pipeline" ]]; then
    if run_cli_pipeline_with_isolation "$tmp" "$stderr_file" "$file"; then
      printf '%s\tUNEXPECTED_GREEN\tpipeline_completed\n' "$file"
    else
      local command_exit=$?
      local err
      err="$(stderr_summary "$stderr_file")"
      if [[ "$command_exit" == "$file_timeout_exit" ]]; then
        printf '%s\tHARNESS_TIMEOUT\tfile_timeout_%ss\n' \
          "$file" "$file_timeout_s"
      elif [[ -n "$err" ]] && stderr_has_fatal_error "$stderr_file"; then
        printf '%s\tPIPELINE_REJECTED\t%s\n' "$file" "$err"
      else
        [[ -n "$err" ]] || err="pipeline_failed_without_diagnostic"
        printf '%s\tERROR\t%s\n' "$file" "$err"
      fi
    fi
  else
    printf '%s\tERROR\tunknown_expected_stage:%s\n' "$file" "$stage"
  fi
  rm -f "$tmp" "$stderr_file" "$goals_file"
}

classify_frontend_accept() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  local stderr_file="$tmp.stderr"

  if run_cli_frontend_with_isolation "$tmp" "$stderr_file" "$file"; then
    printf '%s\tFRONTEND_OK\t0\n' "$file"
  else
    local command_exit=$?
    local err
    err="$(stderr_summary "$stderr_file")"
    if [[ "$command_exit" == "$file_timeout_exit" ]]; then
      printf '%s\tHARNESS_TIMEOUT\tfile_timeout_%ss\n' \
        "$file" "$file_timeout_s"
    else
      [[ -n "$err" ]] || err="frontend_failed_without_diagnostic"
      printf '%s\tUNEXPECTED_REJECTION\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$stderr_file"
}

classify_frontend_reject() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  local stderr_file="$tmp.stderr"

  if run_cli_frontend_with_isolation "$tmp" "$stderr_file" "$file"; then
    printf '%s\tUNEXPECTED_FRONTEND_GREEN\tfrontend_completed\n' "$file"
  else
    local command_exit=$?
    local err
    err="$(stderr_summary "$stderr_file")"
    if [[ "$command_exit" == "$file_timeout_exit" ]]; then
      printf '%s\tHARNESS_TIMEOUT\tfile_timeout_%ss\n' \
        "$file" "$file_timeout_s"
    elif [[ -n "$err" ]] && stderr_has_fatal_error "$stderr_file"; then
      printf '%s\tFRONTEND_REJECTED\t%s\n' "$file" "$err"
    else
      [[ -n "$err" ]] || err="frontend_failed_without_diagnostic"
      printf '%s\tERROR\t%s\n' "$file" "$err"
    fi
  fi
  rm -f "$tmp" "$stderr_file"
}

run_frontend_suite() {
  local ok_dir="$1"
  local ko_dir="$2"
  local accepted_report="$report_dir/frontend_expected_accept.tsv"
  local rejected_report="$report_dir/frontend_expected_reject.tsv"
  local summary_report="$report_dir/frontend_summary.txt"
  local -a ok_files proof_ko_files pipeline_ko_files frontend_ko_files
  local -a accepted_files

  read_files_into_array ok_files collect_suite_files "$ok_dir" ok
  read_files_into_array proof_ko_files collect_suite_files "$ko_dir" ko_proof
  read_files_into_array pipeline_ko_files collect_suite_files "$ko_dir" ko_pipeline
  read_files_into_array frontend_ko_files collect_suite_files "$ko_dir" ko_frontend
  accepted_files=(
    "${ok_files[@]}"
    "${proof_ko_files[@]}"
    "${pipeline_ko_files[@]}"
  )

  run_classifications_parallel \
    classify_frontend_accept "$accepted_report" "${accepted_files[@]}"
  run_classifications_parallel \
    classify_frontend_reject "$rejected_report" "${frontend_ko_files[@]}"

  local accept_total accept_ok accept_failed
  local reject_total reject_ok reject_failed
  accept_total="$(wc -l < "$accepted_report" | tr -d ' ')"
  accept_ok="$(
    awk -F '\t' '$2 == "FRONTEND_OK" { c++ } END { print c + 0 }' \
      "$accepted_report"
  )"
  accept_failed=$((accept_total - accept_ok))
  reject_total="$(wc -l < "$rejected_report" | tr -d ' ')"
  reject_ok="$(
    awk -F '\t' '$2 == "FRONTEND_REJECTED" { c++ } END { print c + 0 }' \
      "$rejected_report"
  )"
  reject_failed=$((reject_total - reject_ok))

  {
    echo "mode=frontend"
    echo "jobs=$parallel_jobs"
    echo "expected_accept_total=$accept_total"
    echo "expected_accept_ok=$accept_ok"
    echo "expected_accept_failed=$accept_failed"
    echo "expected_reject_total=$reject_total"
    echo "expected_reject_ok=$reject_ok"
    echo "expected_reject_failed=$reject_failed"
    echo "accepted_report=$accepted_report"
    echo "rejected_report=$rejected_report"
  } > "$summary_report"
  cat "$summary_report"

  if (( accept_failed != 0 || reject_failed != 0 )); then
    return 1
  fi
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
  local -a ok_files ko_files

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

  local ok_total ok_green ok_non_green
  local ko_total ko_proof_rejected ko_frontend_rejected ko_pipeline_rejected
  local ko_harness_timeout ko_error ko_false_green
  ok_total="$(wc -l < "$ok_report" | tr -d ' ')"
  ok_green="$(awk -F '\t' '$2 == "OK" { c++ } END { print c + 0 }' "$ok_report")"
  ok_non_green="$(awk -F '\t' '$2 != "OK" { c++ } END { print c + 0 }' "$ok_report")"

  ko_total="$(wc -l < "$ko_report" | tr -d ' ')"
  ko_proof_rejected="$(
    awk -F '\t' '$2 == "PROOF_REJECTED" { c++ } END { print c + 0 }' \
      "$ko_report"
  )"
  ko_frontend_rejected="$(
    awk -F '\t' '$2 == "FRONTEND_REJECTED" { c++ } END { print c + 0 }' \
      "$ko_report"
  )"
  ko_pipeline_rejected="$(
    awk -F '\t' '$2 == "PIPELINE_REJECTED" { c++ } END { print c + 0 }' \
      "$ko_report"
  )"
  ko_harness_timeout="$(
    awk -F '\t' '$2 == "HARNESS_TIMEOUT" { c++ } END { print c + 0 }' \
      "$ko_report"
  )"
  ko_error="$(awk -F '\t' '$2 == "ERROR" { c++ } END { print c + 0 }' "$ko_report")"
  ko_false_green="$(awk -F '\t' '$2 == "UNEXPECTED_GREEN" { c++ } END { print c + 0 }' "$ko_report")"

  {
    echo "suite=$suite_name"
    echo "subset=$subset"
    echo "timeout_per_goal=$timeout_s"
    echo "timeout_per_negative_goal=$negative_timeout_s"
    echo "timeout_per_file=$file_timeout_s"
    echo "jobs=$parallel_jobs"
    echo "ok_total=$ok_total"
    echo "ok_green=$ok_green"
    echo "ok_non_green=$ok_non_green"
    echo "ko_total=$ko_total"
    echo "ko_proof_rejected=$ko_proof_rejected"
    echo "ko_frontend_rejected=$ko_frontend_rejected"
    echo "ko_pipeline_rejected=$ko_pipeline_rejected"
    echo "ko_harness_timeout=$ko_harness_timeout"
    echo "ko_error=$ko_error"
    echo "ko_false_green=$ko_false_green"
    echo "ok_report=$ok_report"
    echo "ko_report=$ko_report"
  } > "$summary_report_tmp"
  mv "$summary_report_tmp" "$summary_report"

  cat "$summary_report"

  local ko_expected
  ko_expected=$((ko_proof_rejected + ko_frontend_rejected + ko_pipeline_rejected))
  if (( ok_non_green != 0
        || ko_expected != ko_total
        || ko_harness_timeout != 0
        || ko_error != 0
        || ko_false_green != 0 )); then
    return 1
  fi
}

ok_dir="$repo_root/tests/ok"
ko_dir="$repo_root/tests/ko"
ko_manifest="$ko_dir/expectations.tsv"

if [[ ! -f "$ko_manifest" ]]; then
  echo "Missing KO expectations manifest: $ko_manifest" >&2
  exit 1
fi
validate_ko_manifest

if [[ -n "$single_ok_file" ]]; then
  single_result="$(classify_ok "$single_ok_file")"
  printf '%s\n' "$single_result"
  [[ "$(printf '%s\n' "$single_result" | awk -F '\t' '{ print $2 }')" == "OK" ]]
  exit $?
fi

if [[ -n "$single_ko_file" ]]; then
  single_result="$(classify_ko "$single_ko_file")"
  printf '%s\n' "$single_result"
  single_status="$(printf '%s\n' "$single_result" | awk -F '\t' '{ print $2 }')"
  case "$single_status" in
    FRONTEND_REJECTED|PIPELINE_REJECTED|PROOF_REJECTED) exit 0 ;;
    *) exit 1 ;;
  esac
fi

if [[ "$frontend_only" == true ]]; then
  run_frontend_suite "$ok_dir" "$ko_dir"
  exit $?
fi

run_suite "without_calls" "$ok_dir" "$ko_dir" "$subset"
