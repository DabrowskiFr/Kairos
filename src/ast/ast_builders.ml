open Ast

let mk_iexpr ?loc iexpr = { iexpr; loc }
let iexpr_desc e = e.iexpr
let with_iexpr_desc e iexpr = { e with iexpr }
let mk_var v = mk_iexpr (IVar v)
let mk_int n = mk_iexpr (ILitInt n)
let mk_bool b = mk_iexpr (ILitBool b)
let as_var e = match e.iexpr with IVar v -> Some v | _ -> None
let mk_stmt ?loc stmt = { stmt; loc }
let stmt_desc s = s.stmt
let with_stmt_desc s stmt = { s with stmt }
let fresh_oid () = Provenance.fresh_id ()

let empty_node_attrs : node_attrs =
  { uid = None; invariants_user = []; invariants_state_rel = []; coherency_goals = [] }

let empty_transition_attrs : transition_attrs =
  { uid = None; ghost = []; instrumentation = []; warnings = [] }

let ensure_node_uid (n : node) : node =
  match n.attrs.uid with
  | Some _ -> n
  | None -> { n with attrs = { n.attrs with uid = Some (fresh_oid ()) } }

let ensure_transition_uid (t : transition) : transition =
  match t.attrs.uid with
  | Some _ -> t
  | None -> { t with attrs = { t.attrs with uid = Some (fresh_oid ()) } }

let ensure_program_uids (p : program) : program =
  List.map
    (fun n ->
      let n = ensure_node_uid n in
      let trans = List.map ensure_transition_uid n.trans in
      if trans == n.trans then n else { n with trans })
    p

let mk_transition ~src ~dst ~guard ~requires ~ensures ~body : transition =
  { src; dst; guard; requires; ensures; body; attrs = empty_transition_attrs }

let mk_node ~nname ~inputs ~outputs ~assumes ~guarantees ~instances ~locals ~states ~init_state
    ~trans : node =
  {
    nname;
    inputs;
    outputs;
    assumes;
    guarantees;
    instances;
    locals;
    states;
    init_state;
    trans;
    attrs = empty_node_attrs;
  }
