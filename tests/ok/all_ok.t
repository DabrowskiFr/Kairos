  $ for f in ./inputs/*.obc; do
  >   [ -e "$f" ] || continue;
  >   echo "[ok] $f";
  >   obc2why3 --log-level quiet --dump-obc - "$f" > /dev/null;
  >   obc2why3 --log-level quiet --dump-why - "$f" > /dev/null;
  >   obc2why3 --log-level quiet --prove "$f" > /dev/null;
  > done
  [ok] ./inputs/delay_int.obc
  [ok] ./inputs/delay_int2.obc
  [ok] ./inputs/edge_rise.obc
  [ok] ./inputs/toggle.obc
  [ok] ./inputs/toggle_if.obc
  [ok] ./inputs/traffic3.obc
