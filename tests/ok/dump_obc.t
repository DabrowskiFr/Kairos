  $ kairos --log-level quiet --dump-obc - ./inputs/delay_int.obc
  node delay_int (x: int) returns (y: int)
    ensures X(G({y} = {__pre_k1_x}));
    locals
      prev: int; (* user local *)
      __mon_state: mon_state; (* monitor state *)
      __pre_k1_x: int; (* k-step history *)
    states Init, Run;
    init Init
    trans
      Init -> Run {
        (* -- assumes -- *)
        (* source: monitor/program compatibility *)
        assumes {__mon_state} = {Mon0};                                    (* H1 *)
        (* source: monitor pre-condition *)
        assumes {__mon_state} <> {Mon2};                                   (* H2 *)
        (* -- guarantees -- *)
        (* source: monitor post-condition *)
        guarantees {__mon_state} <> {Mon2};                                (* G1 *)
        (* -- user code -- *)
        y := 0;
        prev := x;
        (* -- monitor code -- *)
        match __mon_state with
        | Mon0 ->
          __mon_state := Mon1;
        | Mon1 ->
          if y = __pre_k1_x then
            __mon_state := Mon1;
          else
            if not (y = __pre_k1_x) then
              __mon_state := Mon2;
            else
              skip;
            end;
          end;
        | Mon2 ->
          __mon_state := Mon2;
        end;
      }
      Run -> Run {
        (* -- assumes -- *)
        (* source: monitor/program compatibility *)
        assumes {__mon_state} = {Mon1} or {__mon_state} = {Mon2};          (* H3 *)
        assumes {__mon_state} = {Mon1} -> true or {y} = {__pre_k1_x};      (* H5 *)
        assumes {__mon_state} = {Mon2} -> true or not {y} = {__pre_k1_x};  (* H6 *)
        (* source: monitor pre-condition *)
        assumes {__mon_state} <> {Mon2};                                   (* H4 *)
        (* -- guarantees -- *)
        (* source: monitor post-condition *)
        guarantees {__mon_state} <> {Mon2};                                (* G2 *)
        (* -- user code -- *)
        y := prev;
        prev := x;
        (* -- monitor code -- *)
        match __mon_state with
        | Mon0 ->
          __mon_state := Mon1;
        | Mon1 ->
          if y = __pre_k1_x then
            __mon_state := Mon1;
          else
            if not (y = __pre_k1_x) then
              __mon_state := Mon2;
            else
              skip;
            end;
          end;
        | Mon2 ->
          __mon_state := Mon2;
        end;
      }
  end
