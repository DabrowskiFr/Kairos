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
  | SAssign (id, e) -> [ indent_str indent_level ^ id ^ " := " ^ Ast_pretty.string_of_iexpr e ^ ";" ]
  | SSkip -> [ indent_str indent_level ^ "skip;" ]
  | SCall (inst, args, outs) ->
      let args_s = String.concat ", " (List.map Ast_pretty.string_of_iexpr args) in
      let outs_s = String.concat ", " outs in
      [ indent_str indent_level ^ "call " ^ inst ^ "(" ^ args_s ^ ") returns (" ^ outs_s ^ ");" ]
  | SIf (c, t, e) ->
      [ indent_str indent_level ^ "if " ^ Ast_pretty.string_of_iexpr c ^ " then" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) t
      @ [ indent_str indent_level ^ "else" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) e
      @ [ indent_str indent_level ^ "end;" ]
  | SMatch (e, branches, dflt) ->
      [ indent_str indent_level ^ "match " ^ Ast_pretty.string_of_iexpr e ^ " with" ]
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
    match t.guard with None -> "" | Some g -> " when " ^ Ast_pretty.string_of_iexpr g
  in
  let header = indent_str indent ^ "transition " ^ t.src ^ " -> " ^ t.dst ^ guard_s ^ " {" in
  let body = List.concat_map (fun s -> render_stmt s (indent + 1)) t.body in
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

let render_node (n : Ir.node) : string =
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
    List.map (fun a -> "assume " ^ Ast_pretty.string_of_ltl a ^ ";") n.source_info.assumes
  in
  let guarantees =
    List.map (fun g -> "guarantee " ^ Ast_pretty.string_of_ltl g ^ ";") n.source_info.guarantees
  in
  let trans = List.map (render_transition ~indent:1) n.trans in
  let body = List.map (fun l -> indent_str 1 ^ l) (fields @ assumes @ guarantees) @ trans in
  String.concat "\n" ([ "node " ^ sem.sem_nname ^ " {" ] @ body @ [ "}" ])

let render_program (p : Ir.node list) : string =
  String.concat "\n\n" (List.map render_node p)
