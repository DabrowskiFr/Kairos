  $ kairos --log-level quiet --dump-obc - ./inputs/delay_int.kairos
  node delay_int (x: int) returns (y: int)
    ensures X(G({y} = {__pre_k1_x}));
    (* invariant state = Run -> {z} = {__pre_k1_x} *)
    locals
      z: int; (* user local *)
      __aut_state: aut_state; (* automata state *)
      __pre_k1_x: int; (* k-step history *)
    states Init(init), Run;
    transitions
      Init -> Run {
        (* -- assumes -- *)
        (* source: automata/program compatibility *)
        assumes {__aut_state} = {Aut0};                                    (* H1 *)
        (* source: automata pre-condition *)
        assumes {__aut_state} <> {Aut2};                                   (* H2 *)
        (* -- guarantees -- *)
        (* source: user contracts coherency *)
        guarantees {z} = {x};                                              (* G2 *)
        (* source: automata post-condition *)
        guarantees {__aut_state} <> {Aut2};                                (* G1 *)
        (* -- user code -- *)
        z := x;
        (* -- automata update code -- *)
        match __aut_state with
        | Aut0 ->
          __aut_state := Aut1;
        | Aut1 ->
          if y = __pre_k1_x then
            __aut_state := Aut1;
          else
            if not (y = __pre_k1_x) then
              __aut_state := Aut2;
            else
              skip;
            end;
          end;
        | Aut2 ->
          __aut_state := Aut2;
        end;
      }
      Run -> Run {
        (* -- assumes -- *)
        (* source: user contracts coherency *)
        assumes {z} = {__pre_k1_x};                                        (* H7 *)
        (* source: automata/program compatibility *)
        assumes {__aut_state} = {Aut1} or {__aut_state} = {Aut2};          (* H3 *)
        assumes {__aut_state} = {Aut1} -> true or {y} = {__pre_k1_x};      (* H5 *)
        assumes {__aut_state} = {Aut2} -> true or not {y} = {__pre_k1_x};  (* H6 *)
        (* source: automata pre-condition *)
        assumes {__aut_state} <> {Aut2};                                   (* H4 *)
        (* -- guarantees -- *)
        (* source: user contracts coherency *)
        guarantees {z} = {x};                                              (* G4 *)
        (* source: automata post-condition *)
        guarantees {__aut_state} <> {Aut2};                                (* G3 *)
        (* -- user code -- *)
        y := z;
        z := x;
        (* -- automata update code -- *)
        match __aut_state with
        | Aut0 ->
          __aut_state := Aut1;
        | Aut1 ->
          if y = __pre_k1_x then
            __aut_state := Aut1;
          else
            if not (y = __pre_k1_x) then
              __aut_state := Aut2;
            else
              skip;
            end;
          end;
        | Aut2 ->
          __aut_state := Aut2;
        end;
      }
  end
