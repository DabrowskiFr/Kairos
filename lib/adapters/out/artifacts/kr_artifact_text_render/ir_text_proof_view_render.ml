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
 * Kairos — Text renderer for canonical IR.
 *---------------------------------------------------------------------------*)
open Kr_domain_core_syntax
open Kr_domain_render.Kr_domain_render_syntax
let separator = "# " ^ String.make 48 '='

let line ?(indent = 0) (buf : Buffer.t) (s : string) =
  Buffer.add_string buf (String.make (indent * 2) ' ');
  Buffer.add_string buf s;
  Buffer.add_char buf '\n'

let render_ty (t : ty) : string =
  match t with
  | TInt -> "int"
  | TBool -> "bool"
  | TReal -> "real"
  | TCustom s -> s

let render_vdecl (d : vdecl) : string =
  d.vname ^ " : " ^ render_ty d.vty

let render_vdecl_list (ds : vdecl list) : string =
  match ds with
  | [] -> "(none)"
  | _ -> String.concat ", " (List.map render_vdecl ds)

let render_ident_list (ids : ident list) : string =
  match ids with
  | [] -> "(none)"
  | _ -> String.concat " | " ids

let render_stmt (s : Kr_domain_core_syntax.stmt) : string =
  match s.stmt with
  | SAssign (v, e) -> v ^ " := " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_expr e
  | SAssert formula -> "assert " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_fo formula
  | SIf (c, _t, []) -> "if " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_expr c ^ " then { ... }"
  | SIf (c, _t, _e) -> "if " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_expr c ^ " then { ... } else { ... }"
  | SWhile (c, _invariants, _variant, _body) ->
      "while " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_expr c ^ " { ... }"
  | SMethodCall (name, _) -> name ^ "(...)"
  | SSkip -> "skip"
  | SMatch (e, _branches, _default) ->
      "match " ^ Kr_domain_render.Kr_domain_render_syntax.string_of_expr e ^ " { ... }"

let render_ltl_list (fs : ltl list) : string =
  match fs with
  | [] -> "(none)"
  | _ -> String.concat "\n    " (List.map Kr_domain_render.Kr_domain_render_syntax.string_of_ltl fs)

let render_loc_opt = function
  | None -> "None"
  | Some (l : Kr_domain_core_locations.loc) -> Printf.sprintf "Some(%d:%d-%d:%d)" l.line l.col l.line_end l.col_end

let render_ty_short = render_ty

let render_vdecl_short (d : vdecl) : string =
  Printf.sprintf "%s:%s" d.vname (render_ty_short d.vty)

let render_vdecls_short (ds : vdecl list) : string =
  "[" ^ String.concat ", " (List.map render_vdecl_short ds) ^ "]"

let render_idents_short (xs : ident list) : string =
  "[" ^ String.concat ", " xs ^ "]"

let render_expr_opt = function
  | None -> "true"
  | Some e -> Kr_domain_render.Kr_domain_render_syntax.string_of_expr e

let render_product_state (s : Kr_verification_ir.product_state) : string =
  Printf.sprintf "(%s,R%d,E%d)" s.prog_state s.assume_state_index s.guarantee_state_index

let render_product_state_list (xs : Kr_verification_ir.product_state list) : string =
  "[" ^ String.concat ", " (List.map render_product_state xs) ^ "]"

let render_state_invariant (inv : Kr_verification_ir.state_invariant) : string =
  Printf.sprintf "{state=%s; formula=%s}" inv.state (Kr_domain_render.Kr_domain_render_syntax.string_of_fo inv.formula)

let render_formula_ref (f : 'phase Kr_verification_ir.summary_formula) : string =
  Printf.sprintf "f#%d" f.meta.oid

let render_formula_refs (fs : 'phase Kr_verification_ir.summary_formula list) : string =
  "[" ^ String.concat ", " (List.map render_formula_ref fs) ^ "]"

let program_transitions_from_summaries (n : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir) : Kr_verification_ir.transition list =
  n.summaries
  |> List.map (fun (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) -> summary.identity.program_step)
  |> List.sort_uniq Stdlib.compare

let program_transitions_for_node ~(source_program : Kr_domain_core_model.program_model option)
    (n : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir) :
    Kr_verification_ir.transition list =
  match source_program with
  | Some source_program -> (
      match
        List.find_opt
          (fun (source_node : Kr_domain_core_model.node_model) ->
            String.equal source_node.node_name n.semantics.sem_nname)
          source_program
      with
      | Some source_node -> Kr_verification_transition.prioritized_program_transitions_of_node source_node
      | None -> program_transitions_from_summaries n)
  | None -> program_transitions_from_summaries n

let collect_formula_pool (program : Kr_verification_ir.program_ir) : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list =
  let by_oid : (int, Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) Hashtbl.t = Hashtbl.create 257 in
  let add_formula (f : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) =
    match Hashtbl.find_opt by_oid f.meta.oid with
    | None -> Hashtbl.add by_oid f.meta.oid f
    | Some _ -> ()
  in
  let add_formulas = List.iter add_formula in
  let add_product_summary (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) =
    add_formulas summary.propagation_requires;
    add_formulas summary.requires;
    add_formulas summary.ensures;
    add_formulas summary.elaboration_checks;
    List.iter
      (fun (c : Kr_domain_core_syntax.history_free Kr_verification_ir.product_case) ->
        add_formula c.guarantee_guard)
      summary.product_cases
  in
  List.iter
    (fun (n : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir) ->
      List.iter add_product_summary n.summaries)
    program.nodes;
  Hashtbl.fold (fun _ f acc -> f :: acc) by_oid []
  |> List.sort (fun (a : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) (b : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) ->
         Int.compare a.meta.oid b.meta.oid)

let render_formula_pool (buf : Buffer.t) (program : Kr_verification_ir.program_ir) =
  let formulas = collect_formula_pool program in
  line buf "formula_pool";
  if formulas = [] then line ~indent:1 buf "[]"
  else
    List.iter
      (fun (f : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) ->
        line ~indent:1 buf
          (Printf.sprintf "%s = {logic=%s; meta={oid=%d; loc=%s}}"
             (render_formula_ref f) (Kr_domain_render.Kr_domain_render_syntax.string_of_fo f.logic)
             f.meta.oid
             (render_loc_opt f.meta.loc)))
      formulas

let render_transition_full (buf : Buffer.t) (idx : int) (t : Kr_verification_ir.transition) =
  line ~indent:1 buf
    (Printf.sprintf "t%d: %s -> %s when %s" idx t.src_state t.dst_state
       (render_expr_opt t.guard_expr));
  let body = "[" ^ String.concat "; " (List.map render_stmt t.body_stmts) ^ "]" in
  line ~indent:2 buf ("body=" ^ body)

let render_product_summary ~name ~summary_index ~(indent : int) (buf : Buffer.t)
    (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) =
  let product_src = Kr_verification_ir.product_source summary in
  let product_dsts =
    summary.product_cases
    |> List.map (fun (c : Kr_domain_core_syntax.history_free Kr_verification_ir.product_case) ->
           Kr_verification_ir.product_destination summary c)
    |> List.sort_uniq Stdlib.compare
  in
  let guarantee_guards =
    summary.product_cases
    |> List.map (fun (c : Kr_domain_core_syntax.history_free Kr_verification_ir.product_case) ->
           c.guarantee_guard)
  in
  let source_id = Printf.sprintf "S%d" summary_index in
  let destination_id =
    if product_dsts = [] then None
    else Some (Printf.sprintf "D%d" summary_index)
  in
  line ~indent buf
    (Printf.sprintf "%s @ %s via t%d" name (render_product_state product_src)
       summary.trace.step_uid);
  line ~indent:(indent + 1) buf "identity:";
  line ~indent:(indent + 2) buf ("source_id=" ^ source_id);
  line ~indent:(indent + 2) buf ("source=" ^ render_product_state product_src);
  line ~indent:(indent + 2) buf
    (Printf.sprintf "assume_destination=A%d"
       summary.identity
         .assume_destination_state_index);
  line ~indent:(indent + 2) buf
    ("assume_guard=" ^ Kr_domain_render.Kr_domain_render_syntax.string_of_fo summary.identity.assume_guard);
  line ~indent:(indent + 1) buf "summary:";
  line ~indent:(indent + 2) buf ("propagation_requires=" ^ render_formula_refs summary.propagation_requires);
  line ~indent:(indent + 2) buf ("requires=" ^ render_formula_refs summary.requires);
  line ~indent:(indent + 2) buf ("ensures =" ^ render_formula_refs summary.ensures);
  line ~indent:(indent + 2) buf
    ("elaboration_checks=" ^ render_formula_refs summary.elaboration_checks);
  line ~indent:(indent + 1) buf "product_post:";
  line ~indent:(indent + 2) buf
    ("destination_id="
    ^
    match destination_id with
    | None -> "None"
    | Some id -> id);
  line ~indent:(indent + 2) buf
    ("destinations=" ^ render_product_state_list product_dsts);
  line ~indent:(indent + 2) buf
    ("guarantee_guards=" ^ render_formula_refs guarantee_guards);
  line ~indent:(indent + 1) buf "product_cases:";
  if summary.product_cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Kr_domain_core_syntax.history_free Kr_verification_ir.product_case) ->
        let product_dst_id = Printf.sprintf "K%d_%d" summary_index (idx + 1) in
        let product_dst = Kr_verification_ir.product_destination summary c in
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state product_dst);
        line ~indent:(indent + 3) buf
          ("guarantee_guard="
          ^ Kr_domain_render.Kr_domain_render_syntax.string_of_fo c.guarantee_guard.logic))
      summary.product_cases

let render_node_pretty ~(source_program : Kr_domain_core_model.program_model option)
    (buf : Buffer.t)
    (n : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir) =
  let program_transitions = program_transitions_for_node ~source_program n in
  line buf ("node " ^ n.semantics.sem_nname);
  line buf "";
  line buf "signature";
  line ~indent:1 buf ("inputs=" ^ render_vdecls_short n.semantics.sem_inputs);
  line ~indent:1 buf ("outputs=" ^ render_vdecls_short n.semantics.sem_outputs);
  line ~indent:1 buf ("locals=" ^ render_vdecls_short n.semantics.sem_locals);
  line ~indent:1 buf ("states=" ^ render_idents_short n.semantics.sem_states);
  line ~indent:1 buf ("init=" ^ n.semantics.sem_init_state);
  line buf "";
  line buf "source_info";
  line ~indent:1 buf
    ("assumes=["
    ^ String.concat "; " (List.map Kr_domain_render.Kr_domain_render_syntax.string_of_ltl n.source_info.assumes)
    ^ "]");
  line ~indent:1 buf
    ("guarantees=["
    ^ String.concat "; " (List.map Kr_domain_render.Kr_domain_render_syntax.string_of_ltl n.source_info.guarantees)
    ^ "]");
  line ~indent:1 buf
    ("state_invariants=["
    ^ String.concat "; " (List.map render_state_invariant n.source_info.state_invariants)
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
      (fun i summary ->
        render_product_summary ~name:(Printf.sprintf "C%d" (i + 1)) ~summary_index:(i + 1)
          ~indent:1 buf summary)
      n.summaries;
  line buf "";
  line buf separator;
  line buf ""

let render_pretty_program ?(source_program : Kr_domain_core_model.program_model option = None)
    (program : Kr_verification_ir.program_ir) :
    string =
  let buf = Buffer.create 32768 in
  line buf "program";
  render_formula_pool buf program;
  line buf "";
  List.iter (render_node_pretty ~source_program buf) program.nodes;
  Buffer.contents buf
