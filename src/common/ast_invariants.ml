(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

type issue = string

let issue fmt = Printf.sprintf fmt

let check_transition_basic (n:Ast.node) (t:Ast.transition) : issue list =
  let states = Ast.node_states n in
  let src = Ast.transition_src t in
  let dst = Ast.transition_dst t in
  let acc = ref [] in
  if not (List.mem src states) then
    acc := issue "transition src state '%s' not in node states" src :: !acc;
  if not (List.mem dst states) then
    acc := issue "transition dst state '%s' not in node states" dst :: !acc;
  !acc

let check_node_basic (n:Ast.node) : issue list =
  let acc = ref [] in
  let states = Ast.node_states n in
  let init_state = Ast.node_init_state n in
  let uniq l = List.sort_uniq String.compare l in
  if List.length (uniq states) <> List.length states then
    acc := issue "node '%s' has duplicate states" (Ast.node_sig n).nname :: !acc;
  if not (List.mem init_state states) then
    acc := issue "node '%s' init_state '%s' not in states"
      (Ast.node_sig n).nname init_state :: !acc;
  let trans_issues =
    List.concat_map (check_transition_basic n) (Ast.node_trans n)
  in
  acc := List.rev_append trans_issues !acc;
  List.rev !acc

let check_program_basic (p:Ast.program) : issue list =
  let acc = ref [] in
  let names = List.map (fun n -> (Ast.node_sig n).nname) p in
  let uniq = List.sort_uniq String.compare names in
  if List.length uniq <> List.length names then
    acc := "duplicate node names detected" :: !acc;
  List.iter
    (fun n ->
       List.iter (fun i -> acc := i :: !acc) (check_node_basic n))
    p;
  List.rev !acc

let check_program_contracts (p:Ast.program) : issue list =
  let acc = ref [] in
  List.iter
    (fun n ->
       let assumes = Ast.node_assumes n in
       let guarantees = Ast.node_guarantees n in
       if assumes = [] && guarantees = [] then
         acc := issue "node '%s' has no contracts" (Ast.node_sig n).nname :: !acc)
    p;
  List.rev !acc

let check_program_monitor (p:Ast.program) : issue list =
  let acc = ref [] in
  List.iter
    (fun n ->
       match Ast.node_monitor_info n with
       | None -> acc := issue "node '%s' missing monitor info" (Ast.node_sig n).nname :: !acc
       | Some _ -> ())
    p;
  List.rev !acc

let check_program_obc (p:Ast.program) : issue list =
  let acc = ref [] in
  List.iter
    (fun n ->
       match Ast.node_obc_info n with
       | None -> acc := issue "node '%s' missing obc info" (Ast.node_sig n).nname :: !acc
       | Some _ -> ())
    p;
  List.rev !acc
