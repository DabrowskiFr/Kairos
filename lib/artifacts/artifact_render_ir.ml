(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

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

let render_fo_o_list (fs : Ir.summary_formula list) : string =
  match fs with
  | [] -> "(none)"
  | _ ->
      String.concat "\n    "
        (List.map (fun (f : Ir.summary_formula) -> Ast_pretty.string_of_fo f.logic) fs)

let ir_transition_of_ast_transition (t : Ast.transition) : Ir.transition =
  {
    src_state = t.src;
    dst_state = t.dst;
    guard_iexpr = t.guard;
    body_stmts = t.body;
  }

let program_transitions_from_summaries (n : Ir.node_ir) : Ir.transition list =
  n.summaries
  |> List.map (fun (summary : Ir.product_step_summary) -> summary.identity.program_step)
  |> List.sort_uniq Stdlib.compare

let program_transitions_for_node ~(source_program : Ast.program option) (n : Ir.node_ir) :
    Ir.transition list =
  match source_program with
  | Some source_program -> (
      match
        List.find_opt
          (fun (source_node : Ast.node) ->
            String.equal source_node.semantics.sem_nname n.context.semantics.sem_nname)
          source_program
      with
      | Some source_node -> List.map ir_transition_of_ast_transition source_node.semantics.sem_trans
      | None -> program_transitions_from_summaries n)
  | None -> program_transitions_from_summaries n

(* ------------------------------------------------------------------ *)
(* raw_node                                                             *)
(* ------------------------------------------------------------------ *)

let render_raw_node_header (n : Ir_proof_views.raw_node) : string =
  let c = n.core in
  Printf.sprintf
    "# [raw] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
    c.node_name separator c.node_name
    (render_vdecl_list c.inputs)
    (render_vdecl_list c.outputs)
    (render_vdecl_list c.locals)
    (render_ident_list c.control_states)
    c.init_state
    (render_pre_k_map n.pre_k_map)
    (render_ltl_list n.assumes)
    (render_ltl_list n.guarantees)

let render_raw_transition (t : Ir_proof_views.raw_transition) : string =
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

let render_raw_node (n : Ir_proof_views.raw_node) : string =
  let header = render_raw_node_header n in
  let transitions = List.map render_raw_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"

(* ------------------------------------------------------------------ *)
(* annotated_node                                                       *)
(* ------------------------------------------------------------------ *)

let render_annotated_transition (t : Ir_proof_views.annotated_transition) : string =
  let raw = t.raw in
  let guard_str = Ast_pretty.string_of_fo raw.guard in
  let guard_iexpr_str =
    match raw.core.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  let contract_lines =
    let lines = ref [] in
    if t.clauses.requires <> [] then
      lines := !lines @ [ "  requires    :"; "    " ^ render_fo_o_list t.clauses.requires ];
    if t.clauses.ensures <> [] then
      lines := !lines @ [ "  ensures     :"; "    " ^ render_fo_o_list t.clauses.ensures ];
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

let render_annotated_node (n : Ir_proof_views.annotated_node) : string =
  let raw = n.raw in
  let c = raw.core in
  let header =
    Printf.sprintf
      "# [annotated] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n  pre_k       : %s\n\n  assumes     : %s\n  guarantees  : %s"
      c.node_name separator c.node_name
      (render_vdecl_list c.inputs)
      (render_vdecl_list c.outputs)
      (render_vdecl_list c.locals)
      (render_ident_list c.control_states)
      c.init_state
      (render_pre_k_map raw.pre_k_map)
      (render_ltl_list raw.assumes)
      (render_ltl_list raw.guarantees)
  in
  let transitions = List.map render_annotated_transition n.transitions in
  header ^ "\n" ^ String.concat "\n" transitions ^ "\n"

(* ------------------------------------------------------------------ *)
(* verified_node                                                        *)
(* ------------------------------------------------------------------ *)

let render_verified_transition (t : Ir_proof_views.verified_transition) : string =
  let guard_str = Ast_pretty.string_of_fo t.guard in
  let guard_iexpr_str =
    match t.core.guard_iexpr with
    | None -> ""
    | Some e -> "\n  guard_iexpr : " ^ Ast_pretty.string_of_iexpr e
  in
  let contract_lines =
    let lines = ref [] in
    if t.clauses.requires <> [] then
      lines := !lines @ [ "  requires    :"; "    " ^ render_fo_o_list t.clauses.requires ];
    if t.clauses.ensures <> [] then
      lines := !lines @ [ "  ensures     :"; "    " ^ render_fo_o_list t.clauses.ensures ];
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

let render_verified_node (n : Ir_proof_views.verified_node) : string =
  let c = n.core in
  let header =
    Printf.sprintf
      "# [verified] %s\n%s\n\n[node %s]\n  inputs      : %s\n  outputs     : %s\n  locals      : %s\n  states      : %s\n  init        : %s\n\n  assumes     : %s\n  guarantees  : %s"
      c.node_name separator c.node_name
      (render_vdecl_list c.inputs)
      (render_vdecl_list c.outputs)
      (render_vdecl_list c.locals)
      (render_ident_list c.control_states)
      c.init_state
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

let render_iexpr_opt = function
  | None -> "true"
  | Some e -> Ast_pretty.string_of_iexpr e

let render_product_state (s : Ir.product_state) : string =
  Printf.sprintf "(%s,A%d,G%d)" s.prog_state s.assume_state_index s.guarantee_state_index

let render_product_state_list (xs : Ir.product_state list) : string =
  "[" ^ String.concat ", " (List.map render_product_state xs) ^ "]"

let render_user_invariant (inv : Ast.invariant_user) : string =
  Printf.sprintf "{id=%s; expr=%s}" inv.inv_id (Ast_pretty.string_of_hexpr inv.inv_expr)

let render_state_invariant (inv : Ast.invariant_state_rel) : string =
  Printf.sprintf "{state=%s; formula=%s}" inv.state (Ast_pretty.string_of_ltl inv.formula)

let render_formula_ref (f : Ir.summary_formula) : string = Printf.sprintf "f#%d" f.meta.oid

let render_formula_refs (fs : Ir.summary_formula list) : string =
  "[" ^ String.concat ", " (List.map render_formula_ref fs) ^ "]"

let collect_formula_pool ~(source_program : Ast.program option) (program : Ir.program_ir) :
    Ir.summary_formula list =
  let by_oid : (int, Ir.summary_formula) Hashtbl.t = Hashtbl.create 257 in
  let add_formula (f : Ir.summary_formula) =
    match Hashtbl.find_opt by_oid f.meta.oid with
    | None -> Hashtbl.add by_oid f.meta.oid f
    | Some _ -> ()
  in
  let add_formulas = List.iter add_formula in
  let add_product_contract (pc : Ir.product_step_summary) =
    add_formulas pc.requires;
    add_formulas pc.ensures;
    List.iter
      (fun (c : Ir.safe_product_case) ->
        add_formula c.admissible_guard)
      pc.safe_cases;
    List.iter
      (fun (c : Ir.unsafe_product_case) ->
        add_formula c.excluded_guard)
      pc.unsafe_cases
  in
  let add_raw (_r : Ir_proof_views.raw_node) = () in
  let add_annotated (a : Ir_proof_views.annotated_node) =
    List.iter
      (fun (t : Ir_proof_views.annotated_transition) ->
        add_formulas t.clauses.requires;
        add_formulas t.clauses.ensures)
      a.transitions;
    add_formulas a.coherency_goals
  in
  let add_verified (v : Ir_proof_views.verified_node) =
    List.iter
      (fun (t : Ir_proof_views.verified_transition) ->
        add_formulas t.clauses.requires;
        add_formulas t.clauses.ensures)
      v.transitions;
    List.iter add_product_contract v.product_transitions;
    add_formulas v.coherency_goals
  in
  let add_node (n : Ir.node_ir) =
    List.iter add_product_contract n.summaries;
    add_formulas n.goals;
    let raw =
      Proof_obligation_raw.build_raw_node
        ~program_transitions:(program_transitions_for_node ~source_program n)
        n
    in
    let annotated = Proof_obligation_annotate.annotate ~raw ~node:n in
    let verified =
      {
        (Proof_obligation_lowering.eliminate annotated) with
        product_transitions = n.summaries;
      }
    in
    add_raw raw;
    add_annotated annotated;
    add_verified verified
  in
  List.iter add_node program.nodes;
  program.formulas_info.formula_origin_map
  |> List.iter (fun (oid, origin_opt) ->
         if not (Hashtbl.mem by_oid oid) then
           let synthetic : Ir.summary_formula =
             {
               logic = Fo_formula.FTrue;
               meta = { origin = origin_opt; oid; loc = None };
             }
           in
           Hashtbl.add by_oid oid synthetic);
  Hashtbl.fold (fun _ f acc -> f :: acc) by_oid []
  |> List.sort (fun (a : Ir.summary_formula) (b : Ir.summary_formula) -> Int.compare a.meta.oid b.meta.oid)

let render_formula_pool ~(source_program : Ast.program option) (buf : Buffer.t)
    (program : Ir.program_ir) =
  let formulas = collect_formula_pool ~source_program program in
  line buf "formula_pool";
  if formulas = [] then line ~indent:1 buf "[]"
  else
    List.iter
      (fun (f : Ir.summary_formula) ->
        line ~indent:1 buf
          (Printf.sprintf "%s = {logic=%s; meta={origin=%s; oid=%d; loc=%s}}"
             (render_formula_ref f) (Ast_pretty.string_of_fo f.logic)
             (render_origin_opt f.meta.origin)
             f.meta.oid
             (render_loc_opt f.meta.loc)))
      formulas

let render_transition_full (buf : Buffer.t) (idx : int) (t : Ir.transition) =
  line ~indent:1 buf
    (Printf.sprintf "t%d: %s -> %s when %s" idx t.src_state t.dst_state
       (render_iexpr_opt t.guard_iexpr));
  let body = "[" ^ String.concat "; " (List.map render_stmt t.body_stmts) ^ "]" in
  line ~indent:2 buf ("body=" ^ body)

let render_product_contract ~name ~contract_index ~(indent : int) (buf : Buffer.t)
    (pc : Ir.product_step_summary) =
  let safe_product_dsts =
    pc.safe_cases
    |> List.map (fun (c : Ir.safe_product_case) -> c.product_dst)
    |> List.sort_uniq Stdlib.compare
  in
  let admissible_guards =
    pc.safe_cases
    |> List.map (fun (c : Ir.safe_product_case) -> c.admissible_guard)
  in
  let source_id = Printf.sprintf "S%d" contract_index in
  let safe_destination_id =
    if safe_product_dsts = [] then None
    else Some (Printf.sprintf "D%d" contract_index)
  in
  line ~indent buf
    (Printf.sprintf "%s @ %s via t%d" name (render_product_state pc.identity.product_src)
       pc.trace.step_uid);
  line ~indent:(indent + 1) buf "identity:";
  line ~indent:(indent + 2) buf ("source_id=" ^ source_id);
  line ~indent:(indent + 2) buf ("source=" ^ render_product_state pc.identity.product_src);
  line ~indent:(indent + 2) buf
    ("assume_guard=" ^ Ast_pretty.string_of_fo pc.identity.assume_guard);
  line ~indent:(indent + 1) buf "summary:";
  line ~indent:(indent + 2) buf ("requires=" ^ render_formula_refs pc.requires);
  line ~indent:(indent + 2) buf ("ensures =" ^ render_formula_refs pc.ensures);
  line ~indent:(indent + 1) buf "safe_aggregate:";
  line ~indent:(indent + 2) buf
    ("destination_id="
    ^
    match safe_destination_id with
    | None -> "None"
    | Some id -> id);
  line ~indent:(indent + 2) buf
    ("destinations=" ^ render_product_state_list safe_product_dsts);
  line ~indent:(indent + 2) buf
    ("admissible_guards=" ^ render_formula_refs admissible_guards);
  line ~indent:(indent + 1) buf "safe_cases:";
  if pc.safe_cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Ir.safe_product_case) ->
        let product_dst_id = Printf.sprintf "K%d_%d" contract_index (idx + 1) in
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf "step_class=Safe";
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state c.product_dst);
        line ~indent:(indent + 3) buf
          ("admissible_guard=" ^ Ast_pretty.string_of_fo c.admissible_guard.logic);
        line ~indent:(indent + 3) buf "excluded_guard=[]")
      pc.safe_cases;
  line ~indent:(indent + 1) buf "unsafe_cases:";
  if pc.unsafe_cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Ir.unsafe_product_case) ->
        let product_dst_id = Printf.sprintf "K%d_%d" contract_index (List.length pc.safe_cases + idx + 1) in
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf "step_class=Bad_guarantee";
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state c.product_dst);
        line ~indent:(indent + 3) buf
          ("excluded_guard=" ^ Ast_pretty.string_of_fo c.excluded_guard.logic);
        line ~indent:(indent + 3) buf "admissible_guard=[]";
        line ~indent:(indent + 3) buf "ensures=[]";
        line ~indent:(indent + 3) buf ("excluded=" ^ render_formula_refs [ c.excluded_guard ]))
      pc.unsafe_cases

let render_node_core ~indent (buf : Buffer.t) (c : Ir_proof_views.node_core) =
  line ~indent buf ("node_name=" ^ c.node_name);
  line ~indent buf ("inputs=" ^ render_vdecls_short c.inputs);
  line ~indent buf ("outputs=" ^ render_vdecls_short c.outputs);
  line ~indent buf ("locals=" ^ render_vdecls_short c.locals);
  line ~indent buf ("control_states=" ^ render_idents_short c.control_states);
  line ~indent buf ("init_state=" ^ c.init_state)

let render_pre_k_map_entry (h, (info : Temporal_support.pre_k_info)) : string =
  Printf.sprintf "{key=%s; h=%s; expr=%s; names=[%s]; vty=%s}"
    (Ast_pretty.string_of_hexpr h)
    (Ast_pretty.string_of_hexpr info.h)
    (Ast_pretty.string_of_iexpr info.expr)
    (String.concat ", " info.names)
    (render_ty_short info.vty)

let render_raw_transition ~indent (buf : Buffer.t) idx (t : Ir_proof_views.raw_transition) =
  line ~indent buf
    (Printf.sprintf "r%d: %s -> %s when %s" idx t.core.src_state t.core.dst_state
       (render_iexpr_opt t.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.core.body_stmts) ^ "]")

let render_annotated_transition ~indent (buf : Buffer.t) idx (t : Ir_proof_views.annotated_transition) =
  line ~indent buf
    (Printf.sprintf "a%d: %s -> %s when %s" idx t.raw.core.src_state t.raw.core.dst_state
       (render_iexpr_opt t.raw.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.raw.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.raw.core.body_stmts) ^ "]");
  if t.clauses.requires <> [] then
    line ~indent:(indent + 1) buf ("requires=" ^ render_formula_refs t.clauses.requires);
  if t.clauses.ensures <> [] then
    line ~indent:(indent + 1) buf ("ensures =" ^ render_formula_refs t.clauses.ensures)

let render_verified_transition_full ~indent (buf : Buffer.t) idx (t : Ir_proof_views.verified_transition) =
  line ~indent buf
    (Printf.sprintf "v%d: %s -> %s when %s" idx t.core.src_state t.core.dst_state
       (render_iexpr_opt t.core.guard_iexpr));
  line ~indent:(indent + 1) buf ("guard=" ^ Ast_pretty.string_of_fo t.guard);
  line ~indent:(indent + 1) buf
    ("body=[" ^ String.concat "; " (List.map render_stmt t.core.body_stmts) ^ "]");
  line ~indent:(indent + 1) buf
    ("pre_k_updates=[" ^ String.concat "; " (List.map render_stmt t.pre_k_updates) ^ "]");
  if t.clauses.requires <> [] then
    line ~indent:(indent + 1) buf ("requires=" ^ render_formula_refs t.clauses.requires);
  if t.clauses.ensures <> [] then
    line ~indent:(indent + 1) buf ("ensures =" ^ render_formula_refs t.clauses.ensures)

let render_raw_view ~indent (buf : Buffer.t) = function
  | None -> line ~indent buf "raw=None"
  | Some (raw : Ir_proof_views.raw_node) ->
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
  | Some (ann : Ir_proof_views.annotated_node) ->
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
  | Some (ver : Ir_proof_views.verified_node) ->
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
            render_product_contract ~name:(Printf.sprintf "V%d" (i + 1))
              ~contract_index:(i + 1) ~indent:(indent + 2) buf pc)
          ver.product_transitions;
      line ~indent:(indent + 1) buf
        ("assumes=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl ver.assumes) ^ "]");
      line ~indent:(indent + 1) buf
        ("guarantees=[" ^ String.concat "; " (List.map Ast_pretty.string_of_ltl ver.guarantees) ^ "]");
      line ~indent:(indent + 1) buf ("coherency_goals=" ^ render_formula_refs ver.coherency_goals);
      line ~indent:(indent + 1) buf
        ("user_invariants=[" ^ String.concat "; " (List.map render_user_invariant ver.user_invariants) ^ "]");
      line ~indent buf "}"

let render_node_pretty ~(source_program : Ast.program option) (buf : Buffer.t)
    (n : Ir.node_ir) =
  let program_transitions = program_transitions_for_node ~source_program n in
  line buf ("node " ^ n.context.semantics.sem_nname);
  line buf "";
  line buf "signature";
  line ~indent:1 buf ("inputs=" ^ render_vdecls_short n.context.semantics.sem_inputs);
  line ~indent:1 buf ("outputs=" ^ render_vdecls_short n.context.semantics.sem_outputs);
  line ~indent:1 buf ("locals=" ^ render_vdecls_short n.context.semantics.sem_locals);
  line ~indent:1 buf ("states=" ^ render_idents_short n.context.semantics.sem_states);
  line ~indent:1 buf ("init=" ^ n.context.semantics.sem_init_state);
  line buf "";
  line buf "source_info";
  line ~indent:1 buf
    ("assumes=["
    ^ String.concat "; " (List.map Ast_pretty.string_of_ltl n.context.source_info.assumes)
    ^ "]");
  line ~indent:1 buf
    ("guarantees=["
    ^ String.concat "; " (List.map Ast_pretty.string_of_ltl n.context.source_info.guarantees)
    ^ "]");
  line ~indent:1 buf
    ("user_invariants=["
    ^ String.concat "; " (List.map render_user_invariant n.context.source_info.user_invariants)
    ^ "]");
  line ~indent:1 buf
    ("state_invariants=["
    ^ String.concat "; " (List.map render_state_invariant n.context.source_info.state_invariants)
    ^ "]");
  line buf "";
  line buf "transitions";
  if program_transitions = [] then line ~indent:1 buf "[]"
  else List.iteri (render_transition_full buf) program_transitions;
  line buf "";
  line buf "canonical (summaries)";
  if n.summaries = [] then line ~indent:1 buf "[]"
  else
    List.iteri
      (fun i pc ->
        render_product_contract ~name:(Printf.sprintf "C%d" (i + 1)) ~contract_index:(i + 1)
          ~indent:1 buf pc)
      n.summaries;
  line buf "";
  line buf ("coherency_goals=" ^ render_formula_refs n.goals);
  line buf "";
  line buf "proof_views";
  let raw = Proof_obligation_raw.build_raw_node ~program_transitions n in
  let annotated = Proof_obligation_annotate.annotate ~raw ~node:n in
  let verified =
      {
        (Proof_obligation_lowering.eliminate annotated) with
        product_transitions = n.summaries;
      }
  in
  render_raw_view ~indent:1 buf (Some raw);
  render_annotated_view ~indent:1 buf (Some annotated);
  render_verified_view ~indent:1 buf (Some verified);
  line buf ""

let render_pretty_program ?(source_program : Ast.program option = None) (program : Ir.program_ir) :
    string =
  let buf = Buffer.create 32768 in
  line buf "program";
  line buf "formulas_info";
  line ~indent:1 buf
    ("formula_origin_map=["
    ^
    String.concat "; "
      (List.map
         (fun (oid, origin) ->
           Printf.sprintf "(%d,%s)" oid (render_origin_opt origin))
         program.formulas_info.formula_origin_map)
    ^ "]");
  if program.formulas_info.warnings <> [] then
    line ~indent:1 buf ("warnings=[" ^ String.concat "; " program.formulas_info.warnings ^ "]");
  line buf "";
  render_formula_pool ~source_program buf program;
  line buf "";
  List.iter (render_node_pretty ~source_program buf) program.nodes;
  Buffer.contents buf
