  $ for f in ./inputs/*.kairos; do
  >   [ -e "$f" ] || continue;
  >   echo "[ok] $f";
  >   kairos --log-level quiet --dump-obc - "$f" > /dev/null;
  >   kairos --log-level quiet --dump-why - "$f" > /dev/null;
  >   kairos --log-level quiet --prove "$f" > /dev/null;
  > done
