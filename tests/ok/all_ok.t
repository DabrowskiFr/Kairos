  $ for f in ./inputs/*.obc; do
  >   [ -e "$f" ] || continue;
  >   echo "[ok] $f";
  >   kairos --log-level quiet --dump-obc - "$f" > /dev/null;
  >   kairos --log-level quiet --dump-why - "$f" > /dev/null;
  >   kairos --log-level quiet --prove "$f" > /dev/null;
  > done
  [ok] ./inputs/ack_cycle.obc
  [ok] ./inputs/counter4.obc
  [ok] ./inputs/critical_safe.obc
  [ok] ./inputs/debounce3.obc
  [ok] ./inputs/delay_int.obc
  [ok] ./inputs/delay_int2.obc
  [ok] ./inputs/edge_rise.obc
  [ok] ./inputs/handoff.obc
  [ok] ./inputs/heartbeat.obc
  [ok] ./inputs/interlock_cycle.obc
  [ok] ./inputs/safe_mode.obc
  [ok] ./inputs/toggle.obc
  [ok] ./inputs/toggle_if.obc
  [ok] ./inputs/traffic3.obc
