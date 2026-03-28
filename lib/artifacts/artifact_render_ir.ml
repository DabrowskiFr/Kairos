(*---------------------------------------------------------------------------
 * Kairos — Text renderer for the three IR layers.
 *
 * Produces a human-readable `.kir` representation of:
 *   raw_node       (Pass 3 output)
 *   annotated_node (Pass 4 output)
 *   verified_node  (Pass 5 output)
 *---------------------------------------------------------------------------*)

let separator = "# " ^ String.make 48 '='

(* ------------------------------------------------------------------ *)
(* Helpers                                                              *)
(* ------------------------------------------------------------------ *)

let render_ty (t : Ast.ty) : string =
  match t with
  | TInt -> "int"
  | TBool -> "bool"
  | TReal -> "real"
  | TCustom s -> s

let render_vdecl (d : Ast.vdecl) : string =
  d.vname ^ " : " ^ render_ty d.vty

let render_vdecl_list (ds : Ast.vdecl list) : string =
  match ds with
  | [] -> "(none)"
  | _ -> String.concat ", " (List.map render_vdecl ds)

let render_ident_list (ids : Ast.ident list) : string =
  match ids with
  | [] -> "(none)"
  | _ -> String.concat " | " ids

let render_instances (insts : (Ast.ident * Ast.ident) list) : string =
  match insts with
  | [] -> "(none)"
  | _ -> String.concat ", " (List.map (fun (i, n) -> i ^ " : " ^ n) insts)

let render_pre_k_map (m : (Ast.hexpr * Temporal_support.pre_k_info) list) : string =
  match m with
  | [] -> "(none)"
  | _ ->
      String.concat "\n    "
        (List.map
           (fun (h, (info : Temporal_support.pre_k_info)) ->
             let names_str = String.concat ", " info.names in
             let ty_str = render_ty info.vty in
             Ast_pretty.string_of_hexpr h ^ " -> slot " ^ names_str ^ " : " ^ ty_str)
           m)

let render_stmt (s : Ast.stmt) : string =
  match s.stmt with
  | SAssign (v, e) -> v ^ " := " ^ Ast_pretty.string_of_iexpr e
  | SIf (c, _t, []) -> "if " ^ Ast_pretty.string_of_iexpr c ^ " then { ... }"
  | SIf (c, _t, _e) -> "if " ^ Ast_pretty.string_of_iexpr c ^ " then { ... } else { ... }"
  | SCall (inst, args, rets) ->
      "(" ^ String.concat ", " rets ^ ") := " ^ inst
      ^ "(" ^ String.concat ", " (List.map Ast_pretty.string_of_iexpr args) ^ ")"
  | SSkip -> "skip"
  | SMatch (e, _branches, _default) ->
      "match " ^ Ast_pretty.string_of_iexpr e ^ " { ... }"

let render_stmt_list (stmts : Ast.stmt list) : string =
  match stmts with
  | [] -> "(none)"
  | _ -> String.concat "\n    " (List.map render_stmt stmts)

let render_ltl_list (fs : Ast.ltl list) : string =
  match fs with
  | [] -> "(none)"
  | _ -> String.concat "\n    " (List.map Ast_pretty.string_of_ltl fs)

let render_fo_o_list (fs : Ir.contract_formula list) : string =
  match fs with
  | [] -> "(none)"
  | _ ->
      String.concat "\n    "
        (List.map (fun (f : Ir.contract_formula) -> Ast_pretty.string_of_ltl f.value) fs)

(* ------------------------------------------------------------------ *)
(* raw_node                                                             *)
(* ------------------------------------------------------------------ *)

let render_raw_node_header (n : Ir.raw_node) : string =
  Printf.sprintf
    "# [raw] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
    n.node_name separator n.node_name
    (render_vdecl_list n.inputs)
    (render_vdecl_list n.outputs)
    (render_vdecl_list n.locals)
    (render_ident_list n.control_states)
    n.init_state
    (render_instances n.instances)
    (render_pre_k_map n.pre_k_map)
    (render_ltl_list n.assumes)
    (render_ltl_list n.guarantees)

let render_raw_transition (t : Ir.raw_transition) : string =
  let guard_str = Ast_pretty.string_of_fo t.guard in
  let guard_iexpr_str =
    match t.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  Printf.sprintf
    "\n[transition %s -> %s]\n  guard       : %s%s\n  body        :\n    %s"
    t.src_state t.dst_state
    guard_str
    guard_iexpr_str
    (render_stmt_list t.body_stmts)

let render_raw_node (n : Ir.raw_node) : string =
  let header = render_raw_node_header n in
  let transitions = List.map render_raw_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"

(* ------------------------------------------------------------------ *)
(* annotated_node                                                       *)
(* ------------------------------------------------------------------ *)

let render_annotated_transition (t : Ir.annotated_transition) : string =
  let raw = t.raw in
  let guard_str = Ast_pretty.string_of_fo raw.guard in
  let guard_iexpr_str =
    match raw.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  Printf.sprintf
    "\n[transition %s -> %s]\n  guard       : %s%s\n  body        :\n    %s\n  requires    :\n    %s\n  ensures     :\n    %s"
    raw.src_state raw.dst_state
    guard_str
    guard_iexpr_str
    (render_stmt_list raw.body_stmts)
    (render_fo_o_list t.requires)
    (render_fo_o_list t.ensures)

let render_annotated_node (n : Ir.annotated_node) : string =
  let raw = n.raw in
  let header =
    Printf.sprintf
      "# [annotated] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
      raw.node_name separator raw.node_name
      (render_vdecl_list raw.inputs)
      (render_vdecl_list raw.outputs)
      (render_vdecl_list raw.locals)
      (render_ident_list raw.control_states)
      raw.init_state
      (render_instances raw.instances)
      (render_pre_k_map raw.pre_k_map)
      (render_ltl_list raw.assumes)
      (render_ltl_list raw.guarantees)
  in
  let transitions = List.map render_annotated_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"

(* ------------------------------------------------------------------ *)
(* verified_node                                                        *)
(* ------------------------------------------------------------------ *)

let render_verified_transition (t : Ir.verified_transition) : string =
  let guard_str = Ast_pretty.string_of_fo t.guard in
  let guard_iexpr_str =
    match t.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  Printf.sprintf
    "\n[transition %s -> %s]\n  guard       : %s%s\n  body        :\n    %s\n  pre_k_upd   :\n    %s\n  requires    :\n    %s\n  ensures     :\n    %s"
    t.src_state t.dst_state
    guard_str
    guard_iexpr_str
    (render_stmt_list t.body_stmts)
    (render_stmt_list t.pre_k_updates)
    (render_fo_o_list t.requires)
    (render_fo_o_list t.ensures)

let render_verified_node (n : Ir.verified_node) : string =
  let header =
    Printf.sprintf
      "# [verified] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n\n  assumes     : %s\n  guarantees  : %s"
      n.node_name separator n.node_name
      (render_vdecl_list n.inputs)
      (render_vdecl_list n.outputs)
      (render_vdecl_list n.locals)
      (render_ident_list n.control_states)
      n.init_state
      (render_instances n.instances)
      (render_ltl_list n.assumes)
      (render_ltl_list n.guarantees)
  in
  let transitions = List.map render_verified_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"
