#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: collect_eval_metrics.sh [options]

Collect structural/proof metrics for a list of .kairos examples and emit:
  - a CSV file
  - a LaTeX table snippet

Options:
  --repo DIR           Kairos repo root (default: script parent/..)
  --cli PATH           CLI executable (default: REPO/_build/default/bin/cli/main.exe)
  --out-dir DIR        Working/output directory (default: REPO/tmp/eval_metrics)
  --csv PATH           CSV output path (default: OUT_DIR/metrics.csv)
  --tex PATH           LaTeX table output path (default: OUT_DIR/metrics_table.tex)
  --timeout-s N        Timeout passed to --prove (default: 6)
  --examples LIST      Comma-separated names or paths. Names are resolved as tests/ok/<name>.kairos
  --no-build           Do not run dune build

Example:
  collect_eval_metrics.sh \
    --out-dir /tmp/eval \
    --csv /tmp/eval/metrics.csv \
    --tex /tmp/eval/metrics_table.tex \
    --examples resettable_delay,armed_delay_flag,delay_core
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO="$REPO_DEFAULT"
CLI=""
OUT_DIR=""
CSV_OUT=""
TEX_OUT=""
TIMEOUT_S="6"
DO_BUILD="1"
EXAMPLES_CSV="resettable_delay,armed_delay_flag,delay_core,edge_rise,handoff,toggle,traffic3,w_guarded_prev_hold"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --cli)
      CLI="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --csv)
      CSV_OUT="$2"
      shift 2
      ;;
    --tex)
      TEX_OUT="$2"
      shift 2
      ;;
    --timeout-s)
      TIMEOUT_S="$2"
      shift 2
      ;;
    --examples)
      EXAMPLES_CSV="$2"
      shift 2
      ;;
    --no-build)
      DO_BUILD="0"
      shift
      ;;
    -h|--help)
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

if [[ -z "$CLI" ]]; then
  CLI="$REPO/_build/default/bin/cli/main.exe"
fi
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$REPO/tmp/eval_metrics"
fi
if [[ -z "$CSV_OUT" ]]; then
  CSV_OUT="$OUT_DIR/metrics.csv"
fi
if [[ -z "$TEX_OUT" ]]; then
  TEX_OUT="$OUT_DIR/metrics_table.tex"
fi

mkdir -p "$OUT_DIR"

if [[ "$DO_BUILD" == "1" ]]; then
  (cd "$REPO" && dune build bin/cli/main.exe)
fi

IFS=',' read -r -a EXAMPLES <<< "$EXAMPLES_CSV"

echo "example,product_steps,canonical_contracts,safe_cases,bad_guarantee_cases,obligations,prove_status,prove_time_s,total_wall_s,build_ast_s,build_outputs_s,spot_s,spot_calls,z3_s,z3_calls,product_s,canonical_s,why_gen_s,vc_smt_s,solver_sum_s,solver_goal_count,require_automata_states,require_automata_edges,ensures_automata_states,ensures_automata_edges,product_edges_full,product_edges_live,product_states_full,product_states_live,canonical_cases_bad_assumption,canonical_contracts_stage,canonical_cases_safe_stage,canonical_cases_bad_guarantee_stage" > "$CSV_OUT"

for entry in "${EXAMPLES[@]}"; do
  if [[ "$entry" == *.kairos ]] || [[ "$entry" == */* ]]; then
    FILE="$entry"
    if [[ ! -f "$FILE" ]]; then
      FILE="$REPO/$entry"
    fi
  else
    FILE="$REPO/tests/ok/${entry}.kairos"
  fi

  if [[ ! -f "$FILE" ]]; then
    echo "Example not found: $entry" >&2
    exit 2
  fi

  STEM="$(basename "$FILE" .kairos)"
  EX_OUT="$OUT_DIR/$STEM"
  mkdir -p "$EX_OUT"

  PRODUCT_TXT="$EX_OUT/$STEM.product.txt"
  OBLIGATIONS_TXT="$EX_OUT/$STEM.obligations.txt"
  VC_TXT="$EX_OUT/$STEM.vc.txt"
  TIMINGS_CSV="$EX_OUT/$STEM.timings.csv"
  PROVE_OUT="$EX_OUT/$STEM.prove.out"
  PROVE_ERR="$EX_OUT/$STEM.prove.err"

  "$CLI" --dump-product "$PRODUCT_TXT" "$FILE"
  "$CLI" --dump-obligations-map "$OBLIGATIONS_TXT" "$FILE"
  "$CLI" --dump-why3-vc "$VC_TXT" "$FILE"

  set +e
  /usr/bin/time -p "$CLI" --prove --timeout-s "$TIMEOUT_S" --dump-timings "$TIMINGS_CSV" "$FILE" > "$PROVE_OUT" 2> "$PROVE_ERR"
  PROVE_CODE=$?
  set -e

  OBLIGATIONS="$(grep -Ec '^[[:space:]]*goal[[:space:]]+' "$VC_TXT" || true)"

  PROVE_TIME_S="$(awk '/^real /{print $2}' "$PROVE_ERR" | tail -n 1)"
  if [[ -z "$PROVE_TIME_S" ]]; then
    PROVE_TIME_S="NA"
  fi

  if [[ "$PROVE_CODE" -eq 0 ]]; then
    PROVE_STATUS="OK"
  else
    PROVE_STATUS="KO($PROVE_CODE)"
  fi

  timing_value() {
    local key="$1"
    if [[ -f "$TIMINGS_CSV" ]]; then
      awk -F',' -v k="$key" '$1 == k { print $2 }' "$TIMINGS_CSV" | tail -n 1
    fi
  }

  TOTAL_WALL_S="$(timing_value total_wall_s)"; [[ -n "$TOTAL_WALL_S" ]] || TOTAL_WALL_S="NA"
  BUILD_AST_S="$(timing_value build_ast_s)"; [[ -n "$BUILD_AST_S" ]] || BUILD_AST_S="NA"
  BUILD_OUTPUTS_S="$(timing_value build_outputs_s)"; [[ -n "$BUILD_OUTPUTS_S" ]] || BUILD_OUTPUTS_S="NA"
  SPOT_S="$(timing_value spot_s)"; [[ -n "$SPOT_S" ]] || SPOT_S="NA"
  SPOT_CALLS="$(timing_value spot_calls)"; [[ -n "$SPOT_CALLS" ]] || SPOT_CALLS="NA"
  Z3_S="$(timing_value z3_s)"; [[ -n "$Z3_S" ]] || Z3_S="NA"
  Z3_CALLS="$(timing_value z3_calls)"; [[ -n "$Z3_CALLS" ]] || Z3_CALLS="NA"
  PRODUCT_S="$(timing_value product_s)"; [[ -n "$PRODUCT_S" ]] || PRODUCT_S="NA"
  CANONICAL_S="$(timing_value canonical_s)"; [[ -n "$CANONICAL_S" ]] || CANONICAL_S="NA"
  WHY_GEN_S="$(timing_value why_gen_s)"; [[ -n "$WHY_GEN_S" ]] || WHY_GEN_S="NA"
  VC_SMT_S="$(timing_value vc_smt_s)"; [[ -n "$VC_SMT_S" ]] || VC_SMT_S="NA"
  SOLVER_SUM_S="$(timing_value solver_sum_s)"; [[ -n "$SOLVER_SUM_S" ]] || SOLVER_SUM_S="NA"
  SOLVER_GOAL_COUNT="$(timing_value solver_goal_count)"; [[ -n "$SOLVER_GOAL_COUNT" ]] || SOLVER_GOAL_COUNT="NA"
  REQUIRE_AUTOMATA_STATES="$(timing_value require_automata_states)"; [[ -n "$REQUIRE_AUTOMATA_STATES" ]] || REQUIRE_AUTOMATA_STATES="NA"
  REQUIRE_AUTOMATA_EDGES="$(timing_value require_automata_edges)"; [[ -n "$REQUIRE_AUTOMATA_EDGES" ]] || REQUIRE_AUTOMATA_EDGES="NA"
  ENSURES_AUTOMATA_STATES="$(timing_value ensures_automata_states)"; [[ -n "$ENSURES_AUTOMATA_STATES" ]] || ENSURES_AUTOMATA_STATES="NA"
  ENSURES_AUTOMATA_EDGES="$(timing_value ensures_automata_edges)"; [[ -n "$ENSURES_AUTOMATA_EDGES" ]] || ENSURES_AUTOMATA_EDGES="NA"
  PRODUCT_EDGES_FULL="$(timing_value product_edges_full)"; [[ -n "$PRODUCT_EDGES_FULL" ]] || PRODUCT_EDGES_FULL="NA"
  PRODUCT_EDGES_LIVE="$(timing_value product_edges_live)"; [[ -n "$PRODUCT_EDGES_LIVE" ]] || PRODUCT_EDGES_LIVE="NA"
  PRODUCT_STATES_FULL="$(timing_value product_states_full)"; [[ -n "$PRODUCT_STATES_FULL" ]] || PRODUCT_STATES_FULL="NA"
  PRODUCT_STATES_LIVE="$(timing_value product_states_live)"; [[ -n "$PRODUCT_STATES_LIVE" ]] || PRODUCT_STATES_LIVE="NA"
  CANONICAL_CONTRACTS_STAGE="$(timing_value canonical_contracts)"; [[ -n "$CANONICAL_CONTRACTS_STAGE" ]] || CANONICAL_CONTRACTS_STAGE="NA"
  CANONICAL_CASES_SAFE_STAGE="$(timing_value canonical_cases_safe)"; [[ -n "$CANONICAL_CASES_SAFE_STAGE" ]] || CANONICAL_CASES_SAFE_STAGE="NA"
  CANONICAL_CASES_BAD_A_STAGE="$(timing_value canonical_cases_bad_assumption)"; [[ -n "$CANONICAL_CASES_BAD_A_STAGE" ]] || CANONICAL_CASES_BAD_A_STAGE="NA"
  CANONICAL_CASES_BAD_G_STAGE="$(timing_value canonical_cases_bad_guarantee)"; [[ -n "$CANONICAL_CASES_BAD_G_STAGE" ]] || CANONICAL_CASES_BAD_G_STAGE="NA"

  CANONICAL_CONTRACTS="$CANONICAL_CONTRACTS_STAGE"
  SAFE_CASES="$CANONICAL_CASES_SAFE_STAGE"
  BAD_G_CASES="$CANONICAL_CASES_BAD_G_STAGE"
  if [[ "$CANONICAL_CONTRACTS" == "NA" || "$SAFE_CASES" == "NA" || "$BAD_G_CASES" == "NA" ]]; then
    CANONICAL_DOT="$EX_OUT/$STEM.canonical.dot"
    CANONICAL_TXT="$EX_OUT/$STEM.canonical.txt"
    "$CLI" --dump-canonical "$CANONICAL_DOT" "$FILE"
    if [[ "$CANONICAL_CONTRACTS" == "NA" ]]; then
      CANONICAL_CONTRACTS="$(grep -Ec '^C[0-9]+:' "$CANONICAL_TXT" || true)"
    fi
    if [[ "$SAFE_CASES" == "NA" ]]; then
      SAFE_CASES="$(grep -Ec '^  κ[0-9]+\.safe:' "$CANONICAL_TXT" || true)"
    fi
    if [[ "$BAD_G_CASES" == "NA" ]]; then
      BAD_G_CASES="$(grep -Ec '^  κ[0-9]+\.[0-9]+: BadGuarantee' "$CANONICAL_TXT" || true)"
    fi
  fi

  PRODUCT_STEPS="$PRODUCT_EDGES_FULL"
  if [[ "$PRODUCT_STEPS" == "NA" ]]; then
    PRODUCT_STEPS="$(grep -c ' -- ' "$PRODUCT_TXT" || true)"
  fi

  echo "$STEM,$PRODUCT_STEPS,$CANONICAL_CONTRACTS,$SAFE_CASES,$BAD_G_CASES,$OBLIGATIONS,$PROVE_STATUS,$PROVE_TIME_S,$TOTAL_WALL_S,$BUILD_AST_S,$BUILD_OUTPUTS_S,$SPOT_S,$SPOT_CALLS,$Z3_S,$Z3_CALLS,$PRODUCT_S,$CANONICAL_S,$WHY_GEN_S,$VC_SMT_S,$SOLVER_SUM_S,$SOLVER_GOAL_COUNT,$REQUIRE_AUTOMATA_STATES,$REQUIRE_AUTOMATA_EDGES,$ENSURES_AUTOMATA_STATES,$ENSURES_AUTOMATA_EDGES,$PRODUCT_EDGES_FULL,$PRODUCT_EDGES_LIVE,$PRODUCT_STATES_FULL,$PRODUCT_STATES_LIVE,$CANONICAL_CASES_BAD_A_STAGE,$CANONICAL_CONTRACTS_STAGE,$CANONICAL_CASES_SAFE_STAGE,$CANONICAL_CASES_BAD_G_STAGE" >> "$CSV_OUT"
done

awk -F',' '
BEGIN {
  print "% Auto-generated by scripts/collect_eval_metrics.sh"
  print "\\begin{tabular}{lcccccccc}"
  print "\\toprule"
  print "Exemple & \\multicolumn{2}{c}{Produit complet} & \\multicolumn{2}{c}{Produit utile} & Résumés locaux & \\multicolumn{2}{c}{Cas} & Obligations \\\\"
  print "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-6}\\cmidrule(lr){7-8}\\cmidrule(lr){9-9}"
  print " & $|S_p|$ & $|T_p|$ & $|S_u|$ & $|T_u|$ & $|S|$ & $|\\kappa_{safe}|$ & $|\\kappa_{badG}|$ & $|Obl|$ \\\\"
  print "\\midrule"
}
NR > 1 {
  example=$1
  gsub("_", "\\_", example)
  # CSV layout:
  # 28=product_states_full, 26=product_edges_full, 29=product_states_live, 27=product_edges_live
  # 3=canonical_contracts, 4=safe_cases, 5=bad_guarantee_cases, 6=obligations
  printf "\\lang{%s} & %s & %s & %s & %s & %s & %s & %s & %s \\\\\n", example, $28, $26, $29, $27, $3, $4, $5, $6
}
END {
  print "\\bottomrule"
  print "\\end{tabular}"
}
' "$CSV_OUT" > "$TEX_OUT"

echo "Wrote CSV: $CSV_OUT"
echo "Wrote TeX: $TEX_OUT"
