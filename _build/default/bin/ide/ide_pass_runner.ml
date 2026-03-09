type state = {
  mutable generation : int;
  mutable active : bool;
}

let create () = { generation = 0; active = false }

let time_pass ~record ~name ~cached f =
  if cached then (
    record ~name ~elapsed:0.0 ~cached:true;
    f ())
  else
    let t0 = Unix.gettimeofday () in
    let res = f () in
    let elapsed = Unix.gettimeofday () -. t0 in
    record ~name ~elapsed ~cached:false;
    res

let run_async (st : state) ~set_active ~set_busy_message ~compute ~on_ok ~on_error =
  if st.active then set_busy_message ()
  else (
    st.generation <- st.generation + 1;
    let token = st.generation in
    st.active <- true;
    set_active true;
    ignore
      (Thread.create
         (fun () ->
           let res = compute () in
           ignore
             (Glib.Idle.add (fun () ->
                  if token = st.generation then (
                    st.active <- false;
                    set_active false;
                    match res with Ok v -> on_ok v | Error e -> on_error e);
                  false)))
         ()))

let cancel (st : state) ~set_active ~on_cancel =
  if st.active then (
    st.generation <- st.generation + 1;
    st.active <- false;
    set_active false;
    on_cancel ())
