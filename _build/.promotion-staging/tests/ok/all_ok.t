  $ for f in ./inputs/*.kairos; do
  >   [ -e "$f" ] || continue;
  >   echo "[ok] $f";
  >   kairos --log-level quiet --dump-obc - "$f" > /dev/null;
  >   kairos --log-level quiet --dump-why - "$f" > /dev/null;
  >   kairos --log-level quiet --prove "$f" > /dev/null;
  > done
  [ok] ./inputs/ack_cycle.kairos
  [ok] ./inputs/delay_int.kairos
  [ok] ./inputs/delay_int2.kairos
  [ok] ./inputs/edge_rise.kairos
  [ok] ./inputs/handoff.kairos
  [ok] ./inputs/r_mode_gate.kairos
  [ok] ./inputs/require_always_one.kairos
  [ok] ./inputs/require_delay_bool.kairos
  [ok] ./inputs/toggle.kairos
  [ok] ./inputs/traffic3.kairos
  [ok] ./inputs/w_ack_window.kairos
  [ok] ./inputs/w_hold_until_off.kairos
  [ok] ./inputs/wr_input_output.kairos
