#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: check_c_codegen.sh <kairos-exe>" >&2
  exit 2
fi

if ! command -v cc >/dev/null 2>&1; then
  echo "C compiler 'cc' is required for C codegen tests" >&2
  exit 1
fi

cli="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$script_dir"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

compile_generated() {
  local source_file="$1"
  local label="$2"
  local out_dir="$tmpdir/$label"

  "$cli" --emit-c="$out_dir" "$source_file"
  cc -std=c99 -Wall -Wextra -pedantic -Werror \
    -c "$out_dir/kairos_generated.c" \
    -o "$out_dir/kairos_generated.o"
}

compile_generated "$test_root/ok/resettable_delay.kairos" resettable_delay
compile_generated "$test_root/ok/pure_function_bool_enum.kairos" pure_function_bool_enum
compile_generated "$test_root/ok/action_contract_inline.kairos" action_contract_inline
compile_generated "$test_root/ok/while_counter.kairos" while_counter
compile_generated "$test_root/ok/w_bundle_prev_window.kairos" keyword_sanitization

toggle_dir="$tmpdir/toggle"
"$cli" --emit-c="$toggle_dir" "$test_root/ok/toggle.kairos"
cat > "$toggle_dir/harness.c" <<'EOF'
#include "kairos_generated.h"
#include <stdio.h>

int main(void) {
  toggle_state_t state;
  int y = -1;

  toggle_init(&state);
  toggle_step(&state, &y);
  printf("%d\n", y);
  toggle_step(&state, &y);
  printf("%d\n", y);
  toggle_step(&state, &y);
  printf("%d\n", y);

  return 0;
}
EOF

cc -std=c99 -Wall -Wextra -pedantic -Werror \
  "$toggle_dir/kairos_generated.c" "$toggle_dir/harness.c" \
  -o "$toggle_dir/harness"

"$toggle_dir/harness" > "$toggle_dir/out.txt"
expected="$tmpdir/toggle.expected"
printf "0\n1\n0\n" > "$expected"

if ! diff -u "$expected" "$toggle_dir/out.txt"; then
  echo "Generated C toggle runtime did not preserve output state" >&2
  exit 1
fi

alarm_dir="$tmpdir/reactive_alarm"
"$cli" --emit-c="$alarm_dir" "$test_root/ok/reactive_alarm_cover.kairos"
cat > "$alarm_dir/harness.c" <<'EOF'
#include "kairos_generated.h"
#include <stdio.h>

static void print_step(
    const reactive_alarm_cover_state_t *state,
    reactive_alarm_cover_control_state_t expected_state,
    bool motor_on,
    bool alarm_latched) {
  printf("%d %d %d\n",
         state->control_state == expected_state,
         motor_on,
         alarm_latched);
}

int main(void) {
  reactive_alarm_cover_state_t state;
  bool motor_on = false;
  bool alarm_latched = false;

  reactive_alarm_cover_init(&state);

  /* Hazard and start arrive together: the safety transition has priority. */
  reactive_alarm_cover_step(
      &state, true, false, true, false, &motor_on, &alarm_latched);
  print_step(
      &state,
      KAIROS_REACTIVE_ALARM_COVER_STATE_ALARMPENDING,
      motor_on,
      alarm_latched);

  reactive_alarm_cover_step(
      &state, false, false, false, false, &motor_on, &alarm_latched);
  print_step(
      &state,
      KAIROS_REACTIVE_ALARM_COVER_STATE_ALARM,
      motor_on,
      alarm_latched);

  reactive_alarm_cover_step(
      &state, false, false, false, true, &motor_on, &alarm_latched);
  print_step(
      &state,
      KAIROS_REACTIVE_ALARM_COVER_STATE_IDLE,
      motor_on,
      alarm_latched);

  reactive_alarm_cover_step(
      &state, false, false, true, false, &motor_on, &alarm_latched);
  print_step(
      &state,
      KAIROS_REACTIVE_ALARM_COVER_STATE_RUN,
      motor_on,
      alarm_latched);

  return 0;
}
EOF

cc -std=c99 -Wall -Wextra -pedantic -Werror \
  "$alarm_dir/kairos_generated.c" "$alarm_dir/harness.c" \
  -o "$alarm_dir/harness"

"$alarm_dir/harness" > "$alarm_dir/out.txt"
alarm_expected="$tmpdir/reactive_alarm.expected"
printf "1 0 1\n1 0 1\n1 0 0\n1 1 0\n" > "$alarm_expected"

if ! diff -u "$alarm_expected" "$alarm_dir/out.txt"; then
  echo "Generated C alarm runtime did not preserve transition priority" >&2
  exit 1
fi

echo "[c-codegen] OK: generated C preserves state and safety priority"
