  $ for f in ./inputs/*.obc; do
  >   [ -e "$f" ] || continue;
  >   echo "[ko] $f";
  >   ! kairos --log-level quiet --dump-why - "$f" > /dev/null 2>&1;
  > done
  [ko] ./inputs/bad_syntax.obc
  [ko] ./inputs/counter4.obc
  [ko] ./inputs/handoff.obc
  [ko] ./inputs/light_latch_corebug.obc
  [ko] ./inputs/light_latch_min.obc
  [ko] ./inputs/pre_k_invalid_ensure.obc
  [ko] ./inputs/pre_k_invalid_require.obc
