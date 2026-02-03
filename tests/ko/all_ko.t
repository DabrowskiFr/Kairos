  $ for f in ./inputs/*.obc; do
  >   [ -e "$f" ] || continue;
  >   echo "[ko] $f";
  >   ! obc2why3 --log-level quiet --dump-why - "$f" > /dev/null 2>&1;
  > done
  [ko] ./inputs/bad_syntax.obc
