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

let separator = "# " ^ String.make 48 '='

let line ?(indent = 0) (buf : Buffer.t) (s : string) =
  Buffer.add_string buf (String.make (indent * 2) ' ');
  Buffer.add_string buf s;
  Buffer.add_char buf '\n'

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

let render_stmt (s : Ast.stmt) : string =
  match s.stmt with
  | SAssign (v, e) -> v ^ " := " ^ Logic_pretty.string_of_iexpr e
  | SIf (c, _t, []) -> "if " ^ Logic_pretty.string_of_iexpr c ^ " then { ... }"
  | SIf (c, _t, _e) -> "if " ^ Logic_pretty.string_of_iexpr c ^ " then { ... } else { ... }"
  | SCall _ -> failwith "calls are not supported outside parser/AST"
  | SSkip -> "skip"
  | SMatch (e, _branches, _default) ->
      "match " ^ Logic_pretty.string_of_iexpr e ^ " { ... }"

let render_ltl_list (fs : Ast.ltl list) : string =
  match fs with
  | [] -> "(none)"
  | _ -> String.concat "\n    " (List.map Logic_pretty.string_of_ltl fs)

let render_loc_opt = function
  | None -> "None"
  | Some (l : Ast.loc) -> Printf.sprintf "Some(%d:%d-%d:%d)" l.line l.col l.line_end l.col_end

let render_origin_opt = function
  | None -> "None"
  | Some o -> "Some(" ^ Formula_origin.to_string o ^ ")"

let render_ty_short = render_ty

let render_vdecl_short (d : Ast.vdecl) : string =
  Printf.sprintf "%s:%s" d.vname (render_ty_short d.vty)

let render_vdecls_short (ds : Ast.vdecl list) : string =
  "[" ^ String.concat ", " (List.map render_vdecl_short ds) ^ "]"

let render_idents_short (xs : Ast.ident list) : string =
  "[" ^ String.concat ", " xs ^ "]"

let render_iexpr_opt = function
  | None -> "true"
  | Some e -> Logic_pretty.string_of_iexpr e

let render_product_state (s : Ir.product_state) : string =
  Printf.sprintf "(%s,R%d,E%d)" s.prog_state s.assume_state_index s.guarantee_state_index

let render_product_state_list (xs : Ir.product_state list) : string =
  "[" ^ String.concat ", " (List.map render_product_state xs) ^ "]"

let render_state_invariant (inv : Ir.state_invariant) : string =
  Printf.sprintf "{state=%s; formula=%s}" inv.state (Logic_pretty.string_of_fo inv.formula)

let render_formula_ref (f : Ir.summary_formula) : string =
  Printf.sprintf "f#%d" f.meta.oid

let render_formula_refs (fs : Ir.summary_formula list) : string =
  "[" ^ String.concat ", " (List.map render_formula_ref fs) ^ "]"

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
            String.equal source_node.semantics.sem_nname n.semantics.sem_nname)
          source_program
      with
      | Some source_node -> Ir_transition.prioritized_program_transitions_of_node source_node
      | None -> program_transitions_from_summaries n)
  | None -> program_transitions_from_summaries n

let collect_formula_pool (program : Ir.program_ir) : Ir.summary_formula list =
  let by_oid : (int, Ir.summary_formula) Hashtbl.t = Hashtbl.create 257 in
  let add_formula (f : Ir.summary_formula) =
    match Hashtbl.find_opt by_oid f.meta.oid with
    | None -> Hashtbl.add by_oid f.meta.oid f
    | Some _ -> ()
  in
  let add_formulas = List.iter add_formula in
  let add_product_summary (summary : Ir.product_step_summary) =
    add_formulas summary.requires;
    add_formulas summary.ensures;
    List.iter
      (fun (c : Ir.safe_product_case) ->
        add_formula c.admissible_guard)
      summary.safe_cases;
    List.iter
      (fun (c : Ir.unsafe_product_case) ->
        add_formula c.excluded_guard)
      summary.unsafe_cases
  in
  List.iter
    (fun (n : Ir.node_ir) ->
      List.iter add_product_summary n.summaries;
      add_formulas n.init_invariant_goals)
    program.nodes;
  List.iter
    (fun (oid, origin_opt) ->
      if not (Hashtbl.mem by_oid oid) then
        let synthetic : Ir.summary_formula =
          { logic = Fo_formula.FTrue; meta = { origin = origin_opt; oid; loc = None } }
        in
        Hashtbl.add by_oid oid synthetic)
    program.formula_origin_map;
  Hashtbl.fold (fun _ f acc -> f :: acc) by_oid []
  |> List.sort (fun (a : Ir.summary_formula) (b : Ir.summary_formula) ->
         Int.compare a.meta.oid b.meta.oid)

let render_formula_pool (buf : Buffer.t) (program : Ir.program_ir) =
  let formulas = collect_formula_pool program in
  line buf "formula_pool";
  if formulas = [] then line ~indent:1 buf "[]"
  else
    List.iter
      (fun (f : Ir.summary_formula) ->
        line ~indent:1 buf
          (Printf.sprintf "%s = {logic=%s; meta={origin=%s; oid=%d; loc=%s}}"
             (render_formula_ref f) (Logic_pretty.string_of_fo f.logic)
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

let render_product_summary ~name ~summary_index ~(indent : int) (buf : Buffer.t)
    (summary : Ir.product_step_summary) =
  let safe_product_dsts =
    summary.safe_cases
    |> List.map (fun (c : Ir.safe_product_case) -> c.product_dst)
    |> List.sort_uniq Stdlib.compare
  in
  let admissible_guards =
    summary.safe_cases
    |> List.map (fun (c : Ir.safe_product_case) -> c.admissible_guard)
  in
  let source_id = Printf.sprintf "S%d" summary_index in
  let safe_destination_id =
    if safe_product_dsts = [] then None
    else Some (Printf.sprintf "D%d" summary_index)
  in
  line ~indent buf
    (Printf.sprintf "%s @ %s via t%d" name (render_product_state summary.identity.product_src)
       summary.trace.step_uid);
  line ~indent:(indent + 1) buf "identity:";
  line ~indent:(indent + 2) buf ("source_id=" ^ source_id);
  line ~indent:(indent + 2) buf ("source=" ^ render_product_state summary.identity.product_src);
  line ~indent:(indent + 2) buf
    ("assume_guard=" ^ Logic_pretty.string_of_fo summary.identity.assume_guard);
  line ~indent:(indent + 1) buf "summary:";
  line ~indent:(indent + 2) buf ("requires=" ^ render_formula_refs summary.requires);
  line ~indent:(indent + 2) buf ("ensures =" ^ render_formula_refs summary.ensures);
  line ~indent:(indent + 1) buf "safe_aggregate:";
  line ~indent:(indent + 2) buf
    ("destination_id="
    ^
    match safe_destination_id with
    | None -> "None"
    | Some id -> id);
  line ~indent:(indent + 2) buf ("destinations=" ^ render_product_state_list safe_product_dsts);
  line ~indent:(indent + 2) buf ("admissible_guards=" ^ render_formula_refs admissible_guards);
  line ~indent:(indent + 1) buf "safe_cases:";
  if summary.safe_cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Ir.safe_product_case) ->
        let product_dst_id = Printf.sprintf "K%d_%d" summary_index (idx + 1) in
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf "step_class=Safe";
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state c.product_dst);
        line ~indent:(indent + 3) buf
          ("admissible_guard=" ^ Logic_pretty.string_of_fo c.admissible_guard.logic);
        line ~indent:(indent + 3) buf "excluded_guard=[]")
      summary.safe_cases;
  line ~indent:(indent + 1) buf "unsafe_cases:";
  if summary.unsafe_cases = [] then line ~indent:(indent + 2) buf "[]"
  else
    List.iteri
      (fun idx (c : Ir.unsafe_product_case) ->
        let product_dst_id =
          Printf.sprintf "K%d_%d" summary_index (List.length summary.safe_cases + idx + 1)
        in
        line ~indent:(indent + 2) buf (Printf.sprintf "case[%d]:" idx);
        line ~indent:(indent + 3) buf "step_class=Bad_guarantee";
        line ~indent:(indent + 3) buf ("product_dst_id=" ^ product_dst_id);
        line ~indent:(indent + 3) buf ("product_dst=" ^ render_product_state c.product_dst);
        line ~indent:(indent + 3) buf
          ("excluded_guard=" ^ Logic_pretty.string_of_fo c.excluded_guard.logic);
        line ~indent:(indent + 3) buf "admissible_guard=[]";
        line ~indent:(indent + 3) buf "ensures=[]";
        line ~indent:(indent + 3) buf ("excluded=" ^ render_formula_refs [ c.excluded_guard ]))
      summary.unsafe_cases

let render_node_pretty ~(source_program : Ast.program option) (buf : Buffer.t)
    (n : Ir.node_ir) =
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
    ^ String.concat "; " (List.map Logic_pretty.string_of_ltl n.source_info.assumes)
    ^ "]");
  line ~indent:1 buf
    ("guarantees=["
    ^ String.concat "; " (List.map Logic_pretty.string_of_ltl n.source_info.guarantees)
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
  line ~indent:1 buf ("init_invariant_goals=" ^ render_formula_refs n.init_invariant_goals);
  line buf "";
  line buf separator;
  line buf ""

let render_pretty_program ?(source_program : Ast.program option = None) (program : Ir.program_ir) :
    string =
  let buf = Buffer.create 32768 in
  line buf "program";
  line buf "formula_origin_map";
  line ~indent:1 buf
    ("["
    ^
    String.concat "; "
      (List.map
         (fun (oid, origin) -> Printf.sprintf "(%d,%s)" oid (render_origin_opt origin))
         program.formula_origin_map)
    ^ "]");
  line buf "";
  render_formula_pool buf program;
  line buf "";
  List.iter (render_node_pretty ~source_program buf) program.nodes;
  Buffer.contents buf
