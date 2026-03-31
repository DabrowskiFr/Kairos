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
        (List.map (fun (f : Ir.contract_formula) -> Ast_pretty.string_of_ltl f.logic) fs)

(* ------------------------------------------------------------------ *)
(* raw_node                                                             *)
(* ------------------------------------------------------------------ *)

let render_raw_node_header (n : Ir.raw_node) : string =
  let c = n.core in
  Printf.sprintf
    "# [raw] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
    c.node_name separator c.node_name
    (render_vdecl_list c.inputs)
    (render_vdecl_list c.outputs)
    (render_vdecl_list c.locals)
    (render_ident_list c.control_states)
    c.init_state
    (render_instances c.instances)
    (render_pre_k_map n.pre_k_map)
    (render_ltl_list n.assumes)
    (render_ltl_list n.guarantees)

let render_raw_transition (t : Ir.raw_transition) : string =
  let guard_str = Ast_pretty.string_of_fo t.guard in
  let guard_iexpr_str =
    match t.core.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  Printf.sprintf
    "\n[transition %s -> %s]\n  guard       : %s%s\n  body        :\n    %s"
    t.core.src_state t.core.dst_state
    guard_str
    guard_iexpr_str
    (render_stmt_list t.core.body_stmts)

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
    match raw.core.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  let contract_lines =
    let lines = ref [] in
    if t.contracts.requires <> [] then
      lines := !lines @ [ "  requires    :"; "    " ^ render_fo_o_list t.contracts.requires ];
    if t.contracts.ensures <> [] then
      lines := !lines @ [ "  ensures     :"; "    " ^ render_fo_o_list t.contracts.ensures ];
    !lines
  in
  String.concat "\n"
    ([
       "";
       Printf.sprintf "[transition %s -> %s]" raw.core.src_state raw.core.dst_state;
       Printf.sprintf "  guard       : %s%s" guard_str guard_iexpr_str;
       "  body        :";
       "    " ^ render_stmt_list raw.core.body_stmts;
     ]
    @ contract_lines)

let render_annotated_node (n : Ir.annotated_node) : string =
  let raw = n.raw in
  let c = raw.core in
  let header =
    Printf.sprintf
      "# [annotated] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
      c.node_name separator c.node_name
      (render_vdecl_list c.inputs)
      (render_vdecl_list c.outputs)
      (render_vdecl_list c.locals)
      (render_ident_list c.control_states)
      c.init_state
      (render_instances c.instances)
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
    match t.core.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  let contract_lines =
    let lines = ref [] in
    if t.contracts.requires <> [] then
      lines := !lines @ [ "  requires    :"; "    " ^ render_fo_o_list t.contracts.requires ];
    if t.contracts.ensures <> [] then
      lines := !lines @ [ "  ensures     :"; "    " ^ render_fo_o_list t.contracts.ensures ];
    !lines
  in
  String.concat "\n"
    ([
       "";
       Printf.sprintf "[transition %s -> %s]" t.core.src_state t.core.dst_state;
       Printf.sprintf "  guard       : %s%s" guard_str guard_iexpr_str;
       "  body        :";
       "    " ^ render_stmt_list t.core.body_stmts;
       "  pre_k_upd   :";
       "    " ^ render_stmt_list t.pre_k_updates;
     ]
    @ contract_lines)

let render_verified_node (n : Ir.verified_node) : string =
  let c = n.core in
  let header =
    Printf.sprintf
      "# [verified] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  instances   : %s\n\n  assumes     : %s\n  guarantees  : %s"
      c.node_name separator c.node_name
      (render_vdecl_list c.inputs)
      (render_vdecl_list c.outputs)
      (render_vdecl_list c.locals)
      (render_ident_list c.control_states)
      c.init_state
      (render_instances c.instances)
      (render_ltl_list n.assumes)
      (render_ltl_list n.guarantees)
  in
  let transitions = List.map render_verified_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"

(* ------------------------------------------------------------------ *)
(* full IR pretty dump                                                  *)
(* ------------------------------------------------------------------ *)

let line ?(indent = 0) (buf : Buffer.t) (s : string) =
  Buffer.add_string buf (String.make (indent * 2) ' ');
  Buffer.add_string buf s;
  Buffer.add_char buf '\n'

let render_loc_opt = function
  | None -> "None"
  | Some (l : Ast.loc) -> Printf.sprintf "Some(%d:%d-%d:%d)" l.line l.col l.line_end l.col_end

let render_origin_opt = function
  | None -> "None"
  | Some o -> "Some(" ^ Formula_origin.to_string o ^ ")"

let render_ty_short = render_ty

let render_vdecl_short (d : Ast.vdecl) : string = Printf.sprintf "%s:%s" d.vname (render_ty_short d.vty)

let render_vdecls_short (ds : Ast.vdecl list) : string =
  "[" ^ String.concat ", " (List.map render_vdecl_short ds) ^ "]"

let render_idents_short (xs : Ast.ident list) : string = "[" ^ String.concat ", " xs ^ "]"

let render_instances_short (xs : (Ast.ident * Ast.ident) list) : string =
  let one (inst, node) = Printf.sprintf "%s:%s" inst node in
  "[" ^ String.concat ", " (List.map one xs) ^ "]"

let render_iexpr_opt = function
  | None -> "true"
  | Some e -> Ast_pretty.string_of_iexpr e

let render_product_state (s : Ir.product_state) : string =
  Printf.sprintf "(%s,A%d,G%d)" s.prog_state s.assume_state_index s.guarantee_state_index

let render_product_state_list (xs : Ir.product_state list) : string =
  "[" ^ String.concat ", " (List.map render_product_state xs) ^ "]"

let render_step_class = function
  | Ir.Safe -> "Safe"
  | Ir.Bad_assumption -> "Bad_assumption"
  | Ir.Bad_guarantee -> "Bad_guarantee"

let render_user_invariant (inv : Ast.invariant_user) : string =
  Printf.sprintf "{id=%s; expr=%s}" inv.inv_id (Ast_pretty.string_of_hexpr inv.inv_expr)

let render_state_invariant (inv : Ast.invariant_state_rel) : string =
  Printf.sprintf "{state=%s; formula=%s}" inv.state (Ast_pretty.string_of_ltl inv.formula)

let render_formula_ref (f : Ir.contract_formula) : string = Printf.sprintf "f#%d" f.meta.oid

let render_formula_refs (fs : Ir.contract_formula list) : string =
  "[" ^ String.concat ", " (List.map render_formula_ref fs) ^ "]"

let collect_formula_pool (program : Ir.program) : Ir.contract_formula list =
  let by_oid : (int, Ir.contract_formula) Hashtbl.t = Hashtbl.create 257 in
  let add_formula (f : Ir.contract_formula) =
    match Hashtbl.find_opt by_oid f.meta.oid with
    | None -> Hashtbl.add by_oid f.meta.oid f
    | Some _ -> ()
  in
  let add_formulas = List.iter add_formula in
  let add_product_case (c : Ir.product_case) =
    add_formulas c.propagates;
    add_formulas c.ensures;
    add_formulas c.forbidden
  in
  let add_product_contract (pc : Ir.product_contract) =
    add_formulas pc.common.requires;
    add_formulas pc.common.ensures;
    add_formulas pc.safe_summary.safe_propagates;
    add_formulas pc.safe_summary.safe_ensures;
    List.iter add_product_case pc.cases
  in
  let add_raw (_r : Ir.raw_node) = () in
  let add_annotated (a : Ir.annotated_node) =
    List.iter
      (fun (t : Ir.annotated_transition) ->
        add_formulas t.contracts.requires;
        add_formulas t.contracts.ensures)
      a.transitions;
    add_formulas a.coherency_goals
  in
  let add_verified (v : Ir.verified_node) =
    List.iter
      (fun (t : Ir.verified_transition) ->
        add_formulas t.contracts.requires;
        add_formulas t.contracts.ensures)
      v.transitions;
    List.iter add_product_contract v.product_transitions;
    add_formulas v.coherency_goals
  in
  let add_node (n : Ir.node) =
    List.iter add_product_contract n.product_transitions;
    add_formulas n.coherency_goals;
    Option.iter add_raw n.proof_views.raw;
    Option.iter add_annotated n.proof_views.annotated;
    Option.iter add_verified n.proof_views.verified
  in
  List.iter add_node program.nodes;
  program.contracts_info.contract_origin_map
  |> List.iter (fun (oid, origin_opt) ->
         if not (Hashtbl.mem by_oid oid) then
           let synthetic : Ir.contract_formula =
             {
               logic = Ast.LTrue;
               meta = { origin = origin_opt; oid; loc = None };
             }
           in
           Hashtbl.add by_oid oid synthetic);
  Hashtbl.fold (fun _ f acc -> f :: acc) by_oid []
  |> List.sort (fun (a : Ir.contract_formula) (b : Ir.contract_formula) -> Int.compare a.meta.oid b.meta.oid)

let render_formula_pool (buf : Buffer.t) (program : Ir.program) =
  let formulas = collect_formula_pool program in
  line buf "formula_pool";
  if formulas = [] then line ~indent:1 buf "[]"
  else
    List.iter
      (fun (f : Ir.contract_formula) ->
        line ~indent:1 buf
          (Printf.sprintf "%s = {logic=%s; meta={origin=%s; oid=%d; loc=%s}}"
             (render_formula_ref f) (Ast_pretty.string_of_ltl f.logic)
             (render_origin_opt f.meta.origin)
             f.meta.oid
             (render_loc_opt f.meta.loc)))
      formulas

let render_transition_full (buf : Buffer.t) (idx : int) (t : Ir.transition) =
  line ~indent:1 buf
    (Printf.sprintf "t%d: %s -> %s when %s" idx t.src t.dst (render_iexpr_opt t.guard));
  let body = "[" ^ String.concat "; " (List.map render_stmt t.body) ^ "]" in
  line ~indent:2 buf ("body=" ^ body)

let render_product_contract ~name ~(indent : int) (buf : Buffer.t) (pc : Ir.product_contract) =
  line ~indent buf
    (Printf.sprintf "%s @ %s via t%d" name (render_product_state pc.identity.product_src)
       pc.identity.program_transition_index);
  line ~indent:(indent + 1) buf "identity:";
  line ~indent:(indent + 2) buf ("source_id=" ^ pc.identity.product_src_id);
  line ~indent:(indent + 2) buf ("source=" ^ render_product_state pc.identity.product_src);
  line ~indent:(indent + 2) buf
    ("assume_guard=" ^ Ast_pretty.string_of_fo pc.identity.assume_guard);
  line ~indent:(indent + 1) buf "common:";
  line ~indent:(indent + 2) buf ("requires=" ^ render_formula_refs pc.common.requires);
  line ~indent:(indent + 2) buf ("ensures =" ^ render_formula_refs pc.common.ensures);
  line ~indent:(indent + 1) buf "safe_summary:";
  line ~indent:(indent + 2) buf
    ("destination_id="
    ^
    match pc.safe_summary.safe_destination_id with
    | None -> "None"
    | Some id -> id);
  line ~indent:(indent + 2) buf
    ("destinations=" ^ render_product_state_list pc.safe_summary.safe_product_dsts);
  line ~indent:(indent + 2) buf
    ("safe_propagates=" ^ render_formula_refs pc.safe_summary.safe_propagates);
  line ~indent:(indent + 2) buf
    ("safe_ensures=" ^ render_formula_refs pc.safe_summary.safe_ensures);
  line ~indent:(indent + 1) buf "cases:";
  if pc.cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Ir.product_case) ->
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf ("step_class=" ^ render_step_class c.step_class);
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ c.product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state c.product_dst);
        line ~indent:(indent + 3) buf ("guarantee_guard=" ^ Ast_pretty.string_of_fo c.guarantee_guard);
        line ~indent:(indent + 3) buf ("propagates=" ^ render_formula_refs c.propagates);
        line ~indent:(indent + 3) buf ("ensures=" ^ render_formula_refs c.ensures);
        line ~indent:(indent + 3) buf ("forbidden=" ^ render_formula_refs c.forbidden))
      pc.cases

let render_node_core ~indent (buf : Buffer.t) (c : Ir.node_core) =
  line ~indent buf ("node_name=" ^ c.node_name);
  line ~indent buf ("inputs=" ^ render_vdecls_short c.inputs);
  line ~indent buf ("outputs=" ^ render_vdecls_short c.outputs);
  line ~indent buf ("locals=" ^ render_vdecls_short c.locals);
  line ~indent buf ("control_states=" ^ render_idents_short c.control_states);
  line ~indent buf ("init_state=" ^ c.init_state);
  line ~indent buf ("instances=" ^ render_instances_short c.instances)

let render_pre_k_map_entry (h, (info : Temporal_support.pre_k_info)) : string =
  Printf.sprintf "{key=%s; h=%s; expr=%s; names=[%s]; vty=%s}"
    (Ast_pretty.string_of_hexpr h)
    (Ast_pretty.string_of_hexpr info.h)
    (Ast_pretty.string_of_iexpr info.expr)
    (String.concat ", " info.names)
    (render_ty_short info.vty)

let render_raw_transition ~indent (buf : Buffer.t) idx (t : Ir.raw_transition) =
  line ~indent buf
    (Printf.sprintf "r%d: %s -> %s when %s" idx t.core.src_state t.core.dst_state
       (render_iexpr_opt t.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.core.body_stmts) ^ "]")

let render_annotated_transition ~indent (buf : Buffer.t) idx (t : Ir.annotated_transition) =
  line ~indent buf
    (Printf.sprintf "a%d: %s -> %s when %s" idx t.raw.core.src_state t.raw.core.dst_state
       (render_iexpr_opt t.raw.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.raw.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.raw.core.body_stmts) ^ "]");
  if t.contracts.requires <> [] then
    line ~indent:(indent + 1) buf ("requires=" ^ render_formula_refs t.contracts.requires);
  if t.contracts.ensures <> [] then
    line ~indent:(indent + 1) buf ("ensures =" ^ render_formula_refs t.contracts.ensures)

let render_verified_transition_full ~indent (buf : Buffer.t) idx (t : Ir.verified_transition) =
  line ~indent buf
    (Printf.sprintf "v%d: %s -> %s when %s" idx t.core.src_state t.core.dst_state
       (render_iexpr_opt t.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.core.body_stmts) ^ "]");
  line ~indent:(indent + 1) buf
    ("pre_k_updates=[" ^ String.concat "; " (List.map render_stmt t.pre_k_updates) ^ "]");
  if t.contracts.requires <> [] then
    line ~indent:(indent + 1) buf ("requires=" ^ render_formula_refs t.contracts.requires);
  if t.contracts.ensures <> [] then
    line ~indent:(indent + 1) buf ("ensures =" ^ render_formula_refs t.contracts.ensures)

let render_raw_view ~indent (buf : Buffer.t) = function
  | None -> line ~indent buf "raw=None"
  | Some (raw : Ir.raw_node) ->
      line ~indent buf "raw=Some {";
      line ~indent:(indent + 1) buf "core:";
      render_node_core ~indent:(indent + 2) buf raw.core;
      line ~indent:(indent + 1) buf "pre_k_map:";
      if raw.pre_k_map = [] then line ~indent:(indent + 2) buf "[]"
      else
        List.iter
          (fun e -> line ~indent:(indent + 2) buf (render_pre_k_map_entry e))
          raw.pre_k_map;
      line ~indent:(indent + 1) buf "transitions:";
      if raw.transitions = [] then line ~indent:(indent + 2) buf "[]"
      else List.iteri (render_raw_transition ~indent:(indent + 2) buf) raw.transitions;
      line ~indent:(indent + 1) buf
        ("assumes=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl raw.assumes) ^ "]");
      line ~indent:(indent + 1) buf
        ("guarantees=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl raw.guarantees) ^ "]");
      line ~indent buf "}"

let render_annotated_view ~indent (buf : Buffer.t) = function
  | None -> line ~indent buf "annotated=None"
  | Some (ann : Ir.annotated_node) ->
      line ~indent buf "annotated=Some {";
      line ~indent:(indent + 1) buf "raw_ref=raw";
      line ~indent:(indent + 1) buf "transitions:";
      if ann.transitions = [] then line ~indent:(indent + 2) buf "[]"
      else List.iteri (render_annotated_transition ~indent:(indent + 2) buf) ann.transitions;
      line ~indent:(indent + 1) buf ("coherency_goals=" ^ render_formula_refs ann.coherency_goals);
      line ~indent:(indent + 1) buf
        ("user_invariants=[" ^ String.concat "; " (List.map render_user_invariant ann.user_invariants) ^ "]");
      line ~indent buf "}"

let render_verified_view ~indent (buf : Buffer.t) = function
  | None -> line ~indent buf "verified=None"
  | Some (ver : Ir.verified_node) ->
      line ~indent buf "verified=Some {";
      line ~indent:(indent + 1) buf "core:";
      render_node_core ~indent:(indent + 2) buf ver.core;
      line ~indent:(indent + 1) buf "transitions:";
      if ver.transitions = [] then line ~indent:(indent + 2) buf "[]"
      else List.iteri (render_verified_transition_full ~indent:(indent + 2) buf) ver.transitions;
      line ~indent:(indent + 1) buf "product_transitions:";
      if ver.product_transitions = [] then line ~indent:(indent + 2) buf "[]"
      else
        List.iteri
          (fun i pc ->
            render_product_contract ~name:(Printf.sprintf "V%d" (i + 1)) ~indent:(indent + 2) buf pc)
          ver.product_transitions;
      line ~indent:(indent + 1) buf
        ("assumes=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl ver.assumes) ^ "]");
      line ~indent:(indent + 1) buf
        ("guarantees=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl ver.guarantees) ^ "]");
      line ~indent:(indent + 1) buf ("coherency_goals=" ^ render_formula_refs ver.coherency_goals);
      line ~indent:(indent + 1) buf
        ("user_invariants=[" ^ String.concat "; " (List.map render_user_invariant ver.user_invariants) ^ "]");
      line ~indent buf "}"

let render_node_pretty (buf : Buffer.t) (n : Ir.node) =
  line buf ("node " ^ n.semantics.sem_nname);
  line buf "";
  line buf "signature";
  line ~indent:1 buf ("inputs=" ^ render_vdecls_short n.semantics.sem_inputs);
  line ~indent:1 buf ("outputs=" ^ render_vdecls_short n.semantics.sem_outputs);
  line ~indent:1 buf ("locals=" ^ render_vdecls_short n.semantics.sem_locals);
  line ~indent:1 buf ("states=" ^ render_idents_short n.semantics.sem_states);
  line ~indent:1 buf ("init=" ^ n.semantics.sem_init_state);
  line ~indent:1 buf ("instances=" ^ render_instances_short n.semantics.sem_instances);
  line buf "";
  line buf "source_info";
  line ~indent:1 buf
    ("assumes=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl n.source_info.assumes) ^ "]");
  line ~indent:1 buf
    ("guarantees=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl n.source_info.guarantees) ^ "]");
  line ~indent:1 buf
    ("user_invariants=["
    ^ String.concat "; " (List.map render_user_invariant n.source_info.user_invariants)
    ^ "]");
  line ~indent:1 buf
    ("state_invariants=["
    ^ String.concat "; " (List.map render_state_invariant n.source_info.state_invariants)
    ^ "]");
  line buf "";
  line buf "transitions";
  if n.trans = [] then line ~indent:1 buf "[]"
  else List.iteri (render_transition_full buf) n.trans;
  line buf "";
  line buf "canonical (product_transitions)";
  if n.product_transitions = [] then line ~indent:1 buf "[]"
  else
    List.iteri
      (fun i pc -> render_product_contract ~name:(Printf.sprintf "C%d" (i + 1)) ~indent:1 buf pc)
      n.product_transitions;
  line buf "";
  line buf ("coherency_goals=" ^ render_formula_refs n.coherency_goals);
  line buf "";
  line buf "proof_views";
  render_raw_view ~indent:1 buf n.proof_views.raw;
  render_annotated_view ~indent:1 buf n.proof_views.annotated;
  render_verified_view ~indent:1 buf n.proof_views.verified;
  line buf ""

let render_pretty_program (program : Ir.program) : string =
  let buf = Buffer.create 32768 in
  line buf "program";
  line buf "contracts_info";
  line ~indent:1 buf
    ("contract_origin_map=["
    ^
    String.concat "; "
      (List.map
         (fun (oid, origin) ->
           Printf.sprintf "(%d,%s)" oid (render_origin_opt origin))
         program.contracts_info.contract_origin_map)
    ^ "]");
  if program.contracts_info.warnings <> [] then
    line ~indent:1 buf ("warnings=[" ^ String.concat "; " program.contracts_info.warnings ^ "]");
  line buf "";
  render_formula_pool buf program;
  line buf "";
  List.iter (render_node_pretty buf) program.nodes;
  Buffer.contents buf
