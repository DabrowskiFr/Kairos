  $ kairos --log-level quiet --dump-obc - ./inputs/delay_int.kairos
  node delay_int (x: int) returns (y: int)
    ensures X(G({y} = {__pre_k1_x}));
    (* invariant state = Run -> {z} = {__pre_k1_x} *)
    locals
      z: int; (* user local *)
      __pre_k1_x: int; (* k-step history *)
    states Init(init), Run;
    transitions
      Init -> Run {
        (* -- assumes -- *)
        (* source: monitor/program compatibility *)
        assumes true;                   (* H1 *)
        (* -- guarantees -- *)
        (* source: user contracts coherency *)
        guarantees {z} = {x};           (* G1 *)
        (* -- user code -- *)
        z := x;
      }
      Run -> Run {
        (* -- assumes -- *)
        (* source: user contracts coherency *)
        assumes {z} = {__pre_k1_x};     (* H3 *)
        (* source: monitor/program compatibility *)
        assumes {y} = {__pre_k1_x};     (* H2 *)
        (* -- guarantees -- *)
        (* source: user contracts coherency *)
        guarantees {z} = {x};           (* G3 *)
        (* source: monitor post-condition *)
        guarantees {y} = {__pre_k1_x};  (* G2 *)
        (* -- user code -- *)
        y := z;
        z := x;
      }
  end
