  $ obc2why3 --log-level quiet --dump-obc - ./inputs/delay_int.obc
  node delay_int (x: int) returns (y: int)
    guarantee X(G({y} = {__pre_k1_x}));
    locals
      prev: int; (* user local *)
      __mon_state: mon_state; (* monitor state *)
      __pre_k1_x: int; (* k-step history *)
    states Init, Run;
    init Init
    trans
      Init -> Run {
        (* -- requires -- *)
        (* source: monitor/program compatibility *)
        requires {__mon_state} = {Mon0};                                    (* H1 *)
        (* source: no bad state *)
        requires {__mon_state} <> {Mon2};                                   (* H2 *)
        (* -- ensures -- *)
        (* source: user *)
        ensures {prev} = {x};                                               (* G1 *)
        (* source: user contracts coherency *)
        ensures {prev} = {x} -> {prev} = {x};                               (* G2 *)
        (* source: no bad state *)
        ensures {__mon_state} <> {Mon2};                                    (* G3 *)
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
        (* -- requires -- *)
        (* source: user *)
        requires {prev} = {__pre_k1_x};                                     (* H4 *)
        (* source: monitor/program compatibility *)
        requires {__mon_state} = {Mon1} or {__mon_state} = {Mon2};          (* H3 *)
        requires {__mon_state} = {Mon1} -> true or {y} = {__pre_k1_x};      (* H6 *)
        requires {__mon_state} = {Mon2} -> true or not {y} = {__pre_k1_x};  (* H7 *)
        (* source: no bad state *)
        requires {__mon_state} <> {Mon2};                                   (* H5 *)
        (* -- ensures -- *)
        (* source: user *)
        ensures {prev} = {x};                                               (* G4 *)
        (* source: user contracts coherency *)
        ensures {prev} = {x} -> {prev} = {x};                               (* G5 *)
        (* source: no bad state *)
        ensures {__mon_state} <> {Mon2};                                    (* G6 *)
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
