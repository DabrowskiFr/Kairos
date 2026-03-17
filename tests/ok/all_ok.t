  $ for f in ./inputs/*.kairos; do
  >   [ -e "$f" ] || continue;
  >   if rg -q '^import ' "$f"; then continue; fi
  >   kairos --log-level quiet --emit-kobj "${f%.kairos}.kobj" "$f" > /dev/null;
  > done
  $ for f in ./inputs/*.kairos; do
  >   [ -e "$f" ] || continue;
  >   if ! rg -q '^import ' "$f"; then continue; fi
  >   kairos --log-level quiet --emit-kobj "${f%.kairos}.kobj" "$f" > /dev/null;
  > done
  $ for f in ./inputs/*.kairos; do
  >   [ -e "$f" ] || continue;
  >   echo "[ok] $f";
  >   kairos --log-level quiet --dump-obc - "$f" > /dev/null;
  >   kairos --log-level quiet --dump-why - "$f" > /dev/null;
  >   kairos --log-level quiet --prove "$f" > /dev/null;
  > done
  [ok] ./inputs/ack_cycle.kairos
  [ok] ./inputs/counter4.kairos
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
  shell-init: error retrieving current directory: getcwd: cannot access parent directories: No such file or directory
