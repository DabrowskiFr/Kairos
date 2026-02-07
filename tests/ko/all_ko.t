  $ for f in ./inputs/*.obc; do
  >   [ -e "$f" ] || continue;
  >   echo "[ko] $f";
  >   ! kairos --log-level quiet --dump-why - "$f" > /dev/null 2>&1;
  > done
  [ko] ./inputs/bad_syntax.obc
