#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cli_override=""

runs=5
selected_cases=""
build_cli=true
strategy_matrix=false
proof_jobs="${KAIROS_PERFORMANCE_PROOF_JOBS:-10}"
timeout_s="${KAIROS_PERFORMANCE_TIMEOUT_S:-10}"
output_root="${KAIROS_PERFORMANCE_OUTPUT_DIR:-}"
performance_cases="toggle credit-balance resettable-delay safety-alarm traffic-cycle weak-until-window railway-interlocking medical-light"
strategy_cases="toggle resettable-delay platform-door independent-alarms medical-light"
listed_cases="$performance_cases platform-door independent-alarms medical-full"

usage() {
  cat <<'EOF'
Usage:
  validate_performance.sh [options]

Options:
  --repo-root <path>  Repository root (default: script parent)
  --cli <path>        Prebuilt Kairos CLI (default: repository build)
  --runs <n>          Number of measured runs after one warm-up (default: 5)
  --case <name>       Run one named case; may be repeated (default: all)
  --strategy-matrix   Prove the representative strategy corpus using default,
                      monolithic, separate, multi-weak-until, and reference
  --skip-build        Reuse an already built CLI (for Dune aliases)
  --list              List the available scenarios and exit
  --help              Show this help

Environment:
  KAIROS_PERFORMANCE_PROOF_JOBS   Concurrent prover calls (default: 10)
  KAIROS_PERFORMANCE_TIMEOUT_S   Per-goal prover timeout (default: 10)
  KAIROS_PERFORMANCE_OUTPUT_DIR  Parent directory for retained raw reports

The campaign has two deliberately separate checks:
  - structural data and the proved-goal manifest must be exactly stable;
  - wall-clock phase times are reported as medians, without a pass/fail limit.
EOF
}

case_record() {
  case "$1" in
    toggle)
      printf '%s\n' \
        'tests/ok/toggle.kairos|Minimal stateful baseline: initialization and alternating output'
      ;;
    credit-balance)
      printf '%s\n' \
        'tests/ok/credit_balance_monitor.kairos|Account balance: assumptions, local invariant, and output history'
      ;;
    resettable-delay)
      printf '%s\n' \
        'tests/ok/resettable_delay.kairos|Resettable one-tick delay: initialization frontier and prev'
      ;;
    safety-alarm)
      printf '%s\n' \
        'tests/ok/reactive_alarm_cover.kairos|Safety controller: guarded priority, alarm response, and state invariants'
      ;;
    traffic-cycle)
      printf '%s\n' \
        'tests/ok/traffic3.kairos|Three-state traffic light: cyclic control and next-state guarantees'
      ;;
    weak-until-window)
      printf '%s\n' \
        'tests/ok/w_bundle_prev_window.kairos|Open/close window: history combined with weak-until'
      ;;
    railway-interlocking)
      printf '%s\n' \
        'examples/railway_interlocking.kairos|Railway interlocking: indexed data, conflicting routes, and release protocols'
      ;;
    medical-light)
      printf '%s\n' \
        'examples/medical_infusion_light.kairos|Medical infusion controller from the VSTTE light case study'
      ;;
    platform-door)
      printf '%s\n' \
        'tests/ok/platform_door_badge.kairos|Partial assumption and guarantee monitors for an access-controlled door'
      ;;
    independent-alarms)
      printf '%s\n' \
        'tests/ok/independent_alarm_acknowledgement.kairos|Two independent weak-until alarm channels'
      ;;
    medical-full)
      printf '%s\n' \
        'examples/evaluation/case_studies/medical_infusion_controller.kairos|Full medical infusion controller case study'
      ;;
    *)
      return 1
      ;;
  esac
}

list_cases() {
  local case_name record source_rel description
  printf '%-24s %-52s %s\n' "CASE" "SOURCE" "SCENARIO"
  for case_name in $listed_cases; do
    record="$(case_record "$case_name")"
    source_rel="${record%%|*}"
    description="${record#*|}"
    printf '%-24s %-52s %s\n' "$case_name" "$source_rel" "$description"
  done
}

append_case() {
  local case_name="$1"
  if ! case_record "$case_name" >/dev/null; then
    echo "Unknown case: $case_name" >&2
    echo "Use --list to see valid names." >&2
    exit 2
  fi
  case " $selected_cases " in
    *" $case_name "*)
      ;;
    *)
      selected_cases="${selected_cases:+$selected_cases }$case_name"
      ;;
  esac
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
    --runs)
      runs="${2:-}"
      shift 2
      ;;
    --runs=*)
      runs="${1#*=}"
      shift
      ;;
    --case)
      append_case "${2:-}"
      shift 2
      ;;
    --case=*)
      append_case "${1#*=}"
      shift
      ;;
    --strategy-matrix)
      strategy_matrix=true
      shift
      ;;
    --list)
      list_cases
      exit 0
      ;;
    --skip-build)
      build_cli=false
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

if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
  echo "--repo-root must name an existing directory." >&2
  exit 2
fi
repo_root="$(cd "$repo_root" && pwd)"
if [[ -z "$output_root" ]]; then
  output_root="$repo_root/_build/validation/performance"
fi

case "$runs" in
  ''|*[!0-9]*)
    echo "--runs must be a positive integer." >&2
    exit 2
    ;;
esac
if (( runs < 1 )); then
  echo "--runs must be a positive integer." >&2
  exit 2
fi

case "$proof_jobs" in
  ''|*[!0-9]*)
    echo "KAIROS_PERFORMANCE_PROOF_JOBS must be a positive integer." >&2
    exit 2
    ;;
esac
if (( proof_jobs < 1 )); then
  echo "KAIROS_PERFORMANCE_PROOF_JOBS must be a positive integer." >&2
  exit 2
fi

case "$timeout_s" in
  ''|*[!0-9]*)
    echo "KAIROS_PERFORMANCE_TIMEOUT_S must be a positive integer." >&2
    exit 2
    ;;
esac
if (( timeout_s < 1 )); then
  echo "KAIROS_PERFORMANCE_TIMEOUT_S must be a positive integer." >&2
  exit 2
fi

if [[ -z "$selected_cases" ]]; then
  if [[ "$strategy_matrix" == true ]]; then
    selected_cases="$strategy_cases"
  else
    selected_cases="$performance_cases"
  fi
fi

if ! command -v opam >/dev/null 2>&1; then
  echo "opam is required to run the Kairos proof environment." >&2
  exit 2
fi
if ! command -v dune >/dev/null 2>&1; then
  echo "dune is required to build the Kairos CLI." >&2
  exit 2
fi

mkdir -p "$output_root"
campaign_dir="$(mktemp -d "$output_root/run.XXXXXX")"
mkdir -p "$campaign_dir/tmp" "$campaign_dir/xdg-cache"

if [[ -n "$cli_override" ]]; then
  cli="$cli_override"
else
  cli="$repo_root/_build/default/bin/cli/kairos.exe"
fi
if [[ "$build_cli" == true ]]; then
  echo "[performance] building the CLI outside the measured runs"
  dune build --root "$repo_root" bin/cli/kairos.exe
elif [[ ! -x "$cli" ]]; then
  echo "Missing prebuilt CLI: $cli" >&2
  exit 1
fi

read_metric() {
  local file="$1"
  local key="$2"
  awk -v wanted="$key" '
    index($0, ",") {
      name = substr($0, 1, index($0, ",") - 1)
      if (name == wanted) {
        print substr($0, index($0, ",") + 1)
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

metric_or_na() {
  local file="$1"
  local key="$2"
  local value
  if value="$(read_metric "$file" "$key")"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "n/a"
  fi
}

validate_goals() {
  local goals_file="$1"
  awk -F ',' '
    NR == 1 {
      if ($1 != "index" || $3 != "status") {
        print "Unexpected goals CSV header in " FILENAME > "/dev/stderr"
        exit 1
      }
      next
    }
    {
      count += 1
      status = tolower($3)
      if (status != "valid" && status != "proved") {
        print "Non-valid goal in " FILENAME ": " $2 " (" $3 ")" > "/dev/stderr"
        failed = 1
      }
    }
    END {
      if (count == 0) {
        print "No proof goal reported in " FILENAME > "/dev/stderr"
        exit 1
      }
      if (failed) {
        exit 1
      }
    }
  ' "$goals_file"
}

write_goal_manifest() {
  local goals_file="$1"
  local manifest_file="$2"
  awk -F ',' 'NR > 1 { print $2 "," tolower($3) }' "$goals_file" \
    | LC_ALL=C sort >"$manifest_file"
}

write_structure_snapshot() {
  local timings_file="$1"
  local snapshot_file="$2"
  awk '
    index($0, ",") {
      key = substr($0, 1, index($0, ",") - 1)
      value = substr($0, index($0, ",") + 1)
      if (key ~ /_s$/ || key ~ /^why3_worker_/ ||
          key == "why3_cross_worker_duplicate_goal_count") {
        next
      }
      if (key ~ /^vc_taxonomy_(family|transition|source)_[0-9][0-9][0-9]_/) {
        tail = substr(key, length("vc_taxonomy_") + 1)
        kind = tail
        sub(/_.*/, "", kind)
        tail = substr(tail, length(kind) + 2)
        index_id = tail
        sub(/_.*/, "", index_id)
        field = substr(tail, length(index_id) + 2)
        if (field == "sample_goal") {
          next
        }
        group = kind SUBSEP index_id
        group_kind[group] = kind
        group_record[group] = group_record[group] field "=" value ";"
        next
      }
      print key "," value
    }
    END {
      for (group in group_record) {
        print "vc_taxonomy_" group_kind[group] "_record," group_record[group]
      }
    }
  ' "$timings_file" | LC_ALL=C sort >"$snapshot_file"
}

compare_exact() {
  local reference_file="$1"
  local actual_file="$2"
  local label="$3"
  if cmp -s "$reference_file" "$actual_file"; then
    return 0
  fi
  echo "Structural instability in $label:" >&2
  diff -u "$reference_file" "$actual_file" | sed -n '1,120p' >&2 || true
  return 1
}

run_once() {
  local case_name="$1"
  local source_file="$2"
  local run_label="$3"
  local case_dir="$4"
  shift 4
  local goals_file="$case_dir/$run_label.goals.csv"
  local timings_file="$case_dir/$run_label.timings.csv"
  local stdout_file="$case_dir/$run_label.stdout"
  local stderr_file="$case_dir/$run_label.stderr"

  if ! env \
    TMPDIR="$campaign_dir/tmp" \
    XDG_CACHE_HOME="$campaign_dir/xdg-cache" \
    opam exec -- "$cli" \
      --prove \
      --proof-jobs="$proof_jobs" \
      --timeout-s="$timeout_s" \
      --dump-goals="$goals_file" \
      --dump-timings="$timings_file" \
      "$@" \
      "$source_file" >"$stdout_file" 2>"$stderr_file"
  then
    echo "Proof command failed for $case_name ($run_label)." >&2
    sed -n '1,120p' "$stderr_file" >&2
    return 1
  fi

  if [[ ! -s "$goals_file" || ! -s "$timings_file" ]]; then
    echo "Missing CLI report for $case_name ($run_label)." >&2
    return 1
  fi

  validate_goals "$goals_file"
  write_goal_manifest "$goals_file" "$case_dir/$run_label.goals.manifest"
  write_structure_snapshot "$timings_file" "$case_dir/$run_label.structure"
}

median_metric() {
  local case_dir="$1"
  local key="$2"
  local values_file="$case_dir/median-$key.values"
  local timings_file value

  : >"$values_file"
  for timings_file in "$case_dir"/run-*.timings.csv; do
    if value="$(read_metric "$timings_file" "$key")"; then
      printf '%s\n' "$value" >>"$values_file"
    else
      printf '%s\n' "n/a"
      return 0
    fi
  done

  LC_ALL=C sort -n "$values_file" | awk '
    { values[NR] = $1 }
    END {
      if (NR == 0) {
        print "n/a"
      } else if (NR % 2 == 1) {
        printf "%.6f\n", values[(NR + 1) / 2]
      } else {
        printf "%.6f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
      }
    }
  '
}

run_strategy_matrix() {
  local matrix_csv="$campaign_dir/strategy-matrix.csv"
  local case_name record source_rel description source_file case_dir
  local strategy timings_file goal_count total_wall

  printf '%s\n' 'case,strategy,goal_count,total_wall_s' >"$matrix_csv"
  for case_name in $selected_cases; do
    record="$(case_record "$case_name")"
    source_rel="${record%%|*}"
    description="${record#*|}"
    source_file="$repo_root/$source_rel"
    case_dir="$campaign_dir/strategy-$case_name"

    if [[ ! -f "$source_file" ]]; then
      echo "Missing source for $case_name: $source_file" >&2
      return 1
    fi
    mkdir -p "$case_dir"
    echo "[strategy] $case_name: $description"

    for strategy in default monolithic separate multi-weak-until reference; do
      echo "[strategy] $case_name: $strategy"
      case "$strategy" in
        default)
          run_once "$case_name" "$source_file" "$strategy" "$case_dir"
          ;;
        monolithic|separate|multi-weak-until)
          run_once "$case_name" "$source_file" "$strategy" "$case_dir" \
            "--proof-case-strategy=$strategy"
          ;;
        reference)
          run_once "$case_name" "$source_file" "$strategy" "$case_dir" \
            --no-proof-optimizations
          ;;
      esac

      timings_file="$case_dir/$strategy.timings.csv"
      goal_count="$(read_metric "$timings_file" "why3_goal_count")"
      total_wall="$(read_metric "$timings_file" "total_wall_s")"
      printf '%s,%s,%s,%s\n' \
        "$case_name" "$strategy" "$goal_count" "$total_wall" >>"$matrix_csv"
    done
  done

  echo
  echo "Strategy matrix (all reported goals are valid)"
  awk -F ',' '
    NR == 1 {
      printf "%-24s %-18s %8s %10s\n", "case", "strategy", "goals", "total"
      next
    }
    {
      printf "%-24s %-18s %8s %10.6f\n", $1, $2, $3, $4
    }
  ' "$matrix_csv"
  echo
  echo "[strategy] raw reports: $campaign_dir"
}

if [[ "$strategy_matrix" == true ]]; then
  run_strategy_matrix
  exit $?
fi

structure_csv="$campaign_dir/structural-metrics.csv"
wall_csv="$campaign_dir/wall-medians.csv"
printf '%s\n' \
  'case,measured_runs,goal_count,spot_calls,product_states,product_edges,canonical_summaries,canonical_product_cases' \
  >"$structure_csv"
printf '%s\n' \
  'case,measured_runs,total_wall_s,frontend_parse_s,automata_generation_s,product_s,canonical_s,temporal_lower_s,why_gen_s,vc_smt_s' \
  >"$wall_csv"

for case_name in $selected_cases; do
  record="$(case_record "$case_name")"
  source_rel="${record%%|*}"
  description="${record#*|}"
  source_file="$repo_root/$source_rel"
  case_dir="$campaign_dir/$case_name"

  if [[ ! -f "$source_file" ]]; then
    echo "Missing source for $case_name: $source_file" >&2
    exit 1
  fi
  mkdir -p "$case_dir"

  echo "[performance] $case_name: $description"
  echo "[performance] $case_name: warm-up"
  run_once "$case_name" "$source_file" "warmup" "$case_dir"

  run_index=1
  while (( run_index <= runs )); do
    echo "[performance] $case_name: measured run $run_index/$runs"
    run_once "$case_name" "$source_file" "run-$run_index" "$case_dir"
    compare_exact \
      "$case_dir/warmup.structure" \
      "$case_dir/run-$run_index.structure" \
      "$case_name structure (run $run_index)"
    compare_exact \
      "$case_dir/warmup.goals.manifest" \
      "$case_dir/run-$run_index.goals.manifest" \
      "$case_name goal manifest (run $run_index)"
    run_index=$((run_index + 1))
  done

  reference_timings="$case_dir/run-1.timings.csv"
  goal_count="$(metric_or_na "$reference_timings" "why3_goal_count")"
  spot_calls="$(metric_or_na "$reference_timings" "spot_calls")"
  product_states="$(metric_or_na "$reference_timings" "product_states")"
  product_edges="$(metric_or_na "$reference_timings" "product_edges")"
  canonical_summaries="$(metric_or_na "$reference_timings" "canonical_summaries")"
  canonical_product_cases="$(metric_or_na "$reference_timings" "canonical_product_cases")"
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$case_name" "$runs" "$goal_count" "$spot_calls" \
    "$product_states" "$product_edges" \
    "$canonical_summaries" "$canonical_product_cases" >>"$structure_csv"

  total_wall="$(median_metric "$case_dir" "total_wall_s")"
  frontend_parse="$(median_metric "$case_dir" "frontend_parse_s")"
  automata_generation="$(median_metric "$case_dir" "automata_generation_s")"
  product="$(median_metric "$case_dir" "product_s")"
  canonical="$(median_metric "$case_dir" "canonical_s")"
  temporal_lower="$(median_metric "$case_dir" "temporal_lower_s")"
  why_gen="$(median_metric "$case_dir" "why_gen_s")"
  vc_smt="$(median_metric "$case_dir" "vc_smt_s")"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$case_name" "$runs" "$total_wall" "$frontend_parse" \
    "$automata_generation" "$product" "$canonical" "$temporal_lower" \
    "$why_gen" "$vc_smt" >>"$wall_csv"
done

echo
echo "Structural metrics (exactly stable across warm-up and measured runs)"
awk -F ',' '
  NR == 1 {
    printf "%-24s %6s %7s %7s %8s %8s %10s %10s\n",
      "case", "runs", "goals", "spot", "pstates", "pedges", "summaries", "pcases"
    next
  }
  {
    printf "%-24s %6s %7s %7s %8s %8s %10s %10s\n",
      $1, $2, $3, $4, $5, $6, $7, $8
  }
' "$structure_csv"

echo
echo "Wall-clock phase medians in seconds (observational; no thresholds)"
awk -F ',' '
  NR == 1 {
    printf "%-24s %6s %8s %8s %8s %8s %8s %8s %8s %8s\n",
      "case", "runs", "total", "parse", "automata", "product",
      "canon.", "lower", "why-gen", "prove"
    next
  }
  {
    printf "%-24s %6s %8s %8s %8s %8s %8s %8s %8s %8s\n",
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
  }
' "$wall_csv"

echo
echo "[performance] raw reports: $campaign_dir"
