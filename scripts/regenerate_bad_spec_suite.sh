#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-/Users/fredericdabrowski/Repos/kairos/kairos-dev}"
ok_dir="$repo_root/tests/ok"
ko_dir="$repo_root/tests/ko"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for ok_file in "$ok_dir"/*.kairos; do
  base_name="$(basename "$ok_file" .kairos)"
  ko_file="$ko_dir/${base_name}__bad_spec.kairos"
  if [[ ! -f "$ko_file" ]]; then
    continue
  fi

  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s);
      sub(/[[:space:]]+$/, "", s);
      return s;
    }
    /^node / {
      line = $0;
      if (match(line, /returns[[:space:]]*\(([^)]*)\)/)) {
        returns = substr(line, RSTART, RLENGTH);
        sub(/^returns[[:space:]]*\(/, "", returns);
        sub(/\)$/, "", returns);
        split(returns, ports, ",");
        first_port = trim(ports[1]);
        split(first_port, pair, ":");
        current_output = trim(pair[1]);
      }
      print;
      next;
    }
    /^contracts[[:space:]]*$/ {
      in_contracts = 1;
      printed_bad_ensure = 0;
      print;
      next;
    }
    in_contracts && /^[[:space:]]*ensures[[:space:]]*:/ {
      if (!printed_bad_ensure) {
        print "  ensures: G (undefined_spec_symbol = 0);";
        printed_bad_ensure = 1;
      }
      next;
    }
    in_contracts && /^(states|locals|invariants|transitions|end)[[:space:]]*[:]?/ {
      in_contracts = 0;
      print;
      next;
    }
    in_contracts && /^[[:space:]]*$/ {
      next;
    }
    { print; }
  ' "$ok_file" > "$tmp_dir/${base_name}.kairos"

  mv "$tmp_dir/${base_name}.kairos" "$ko_file"
done

echo "Regenerated bad_spec variants in $ko_dir"
