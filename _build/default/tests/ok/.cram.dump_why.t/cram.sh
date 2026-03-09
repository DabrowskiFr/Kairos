  $ kairos --log-level quiet --dump-why - ./inputs/delay_int.kairos | grep -nE "^module Delay_int$|^  type mon_state|^  let rec step"
