  $ kairos --log-level quiet --dump-why - ./inputs/delay_int.obc | grep -nE "^module Delay_int$|^  type mon_state|^  let rec step"
  1:module Delay_int
  5:  type mon_state = 
  22:  let rec step (vars : vars) (x : int)
