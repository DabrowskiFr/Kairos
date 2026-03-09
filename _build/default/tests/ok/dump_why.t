  $ kairos --log-level quiet --dump-why - ./inputs/delay_int.kairos | grep -nE "^module Delay_int$|^  type mon_state|^  let rec step"
  1:module Delay_int
  16:  let rec step (vars : vars) (x : int)
