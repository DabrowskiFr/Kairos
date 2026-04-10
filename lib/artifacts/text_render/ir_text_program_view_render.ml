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

open Ast

let indent_str (n : int) : string = String.make (2 * max 0 n) ' '

let rec render_stmt (s : stmt) (indent_level : int) : string list =
  match s.stmt with
  | SAssign (id, e) -> [ indent_str indent_level ^ id ^ " := " ^ Logic_pretty.string_of_iexpr e ^ ";" ]
  | SSkip -> [ indent_str indent_level ^ "skip;" ]
  | SCall _ -> failwith "calls are not supported outside parser/AST"
  | SIf (c, t, e) ->
      [ indent_str indent_level ^ "if " ^ Logic_pretty.string_of_iexpr c ^ " then" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) t
      @ [ indent_str indent_level ^ "else" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) e
      @ [ indent_str indent_level ^ "end;" ]
  | SMatch (e, branches, dflt) ->
      [ indent_str indent_level ^ "match " ^ Logic_pretty.string_of_iexpr e ^ " with" ]
      @ List.concat_map
          (fun (ctor, body) ->
            [ indent_str (indent_level + 1) ^ "| " ^ ctor ^ " ->" ]
            @ List.concat_map (fun st -> render_stmt st (indent_level + 2)) body)
          branches
      @
      if dflt = [] then [ indent_str indent_level ^ "end;" ]
      else
        [ indent_str (indent_level + 1) ^ "| _ ->" ]
        @ List.concat_map (fun st -> render_stmt st (indent_level + 2)) dflt
        @ [ indent_str indent_level ^ "end;" ]

let render_transition ?(indent : int = 0) (t : Ir.transition) : string =
  let guard_s =
    match t.guard_iexpr with None -> "" | Some g -> " when " ^ Logic_pretty.string_of_iexpr g
  in
  let header = indent_str indent ^ "transition " ^ t.src_state ^ " -> " ^ t.dst_state ^ guard_s ^ " {" in
  let body = List.concat_map (fun s -> render_stmt s (indent + 1)) t.body_stmts in
  let sections = if body = [] then [] else (indent_str (indent + 1) ^ "do") :: body in
  String.concat "\n" (header :: sections @ [ indent_str indent ^ "}" ])

let render_vdecl (v : vdecl) : string =
  let ty_s =
    match v.vty with
    | TInt -> "int"
    | TBool -> "bool"
    | TReal -> "real"
    | TCustom s -> s
  in
  v.vname ^ ": " ^ ty_s

let program_transitions_of_node ~(source_program : Ast.program option) (n : Ir.node_ir) :
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
      | None ->
          n.summaries
          |> List.map (fun (summary : Ir.product_step_summary) -> summary.identity.program_step)
          |> List.sort_uniq Stdlib.compare)
  | None ->
      n.summaries
      |> List.map (fun (summary : Ir.product_step_summary) -> summary.identity.program_step)
      |> List.sort_uniq Stdlib.compare

let render_node_with_source ~(source_program : Ast.program option) (n : Ir.node_ir) : string =
  let sem = n.semantics in
  let line_params name vs =
    if vs = [] then None
    else Some (name ^ " " ^ String.concat ", " (List.map render_vdecl vs) ^ ";")
  in
  let line_states =
    if sem.sem_states = [] then None else Some ("states " ^ String.concat ", " sem.sem_states ^ ";")
  in
  let fields =
    [
      line_params "inputs" sem.sem_inputs;
      line_params "outputs" sem.sem_outputs;
      line_params "locals" sem.sem_locals;
      line_states;
      Some ("init " ^ sem.sem_init_state ^ ";");
    ]
    |> List.filter_map Fun.id
  in
  let assumes =
    List.map (fun a -> "assume " ^ Logic_pretty.string_of_ltl a ^ ";") n.source_info.assumes
  in
  let guarantees =
    List.map (fun g -> "guarantee " ^ Logic_pretty.string_of_ltl g ^ ";") n.source_info.guarantees
  in
  let trans =
    List.map (render_transition ~indent:1) (program_transitions_of_node ~source_program n)
  in
  let body = List.map (fun l -> indent_str 1 ^ l) (fields @ assumes @ guarantees) @ trans in
  String.concat "\n" ([ "node " ^ sem.sem_nname ^ " {" ] @ body @ [ "}" ])

let render_node ?(source_program : Ast.program option = None) (n : Ir.node_ir) : string =
  render_node_with_source ~source_program n

let render_program ?(source_program : Ast.program option = None) (p : Ir.node_ir list) : string =
  String.concat "\n\n" (List.map (render_node_with_source ~source_program) p)
