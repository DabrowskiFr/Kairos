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

type issue = string

let issue fmt = Printf.sprintf fmt

let check_program_info ~(label:string) ~(get_info:Ast.node -> 'a option)
  (p:Ast.program) : issue list =
  let check n =
    if get_info n = None then
      Some (issue "node '%s' missing %s info" n.nname label)
    else None
  in
  List.filter_map check p

let check_transition_basic (n:Ast.node) (t:Ast.transition) : issue list =
  let states = n.states in
  let src = t.src in
  let dst = t.dst in
  let acc = ref [] in
  if not (List.mem src states) then
    acc := issue "transition src state '%s' not in node states" src :: !acc;
  if not (List.mem dst states) then
    acc := issue "transition dst state '%s' not in node states" dst :: !acc;
  !acc

let check_node_basic (n:Ast.node) : issue list =
  let acc = ref [] in
  let states = n.states in
  let init_state = n.init_state in
  let uniq l = List.sort_uniq String.compare l in
  if List.length (uniq states) <> List.length states then
    acc := issue "node '%s' has duplicate states" n.nname :: !acc;
  if not (List.mem init_state states) then
    acc := issue "node '%s' init_state '%s' not in states"
      n.nname init_state :: !acc;
  let trans_issues =
    List.concat_map (check_transition_basic n) (n.trans)
  in
  acc := List.rev_append trans_issues !acc;
  List.rev !acc

let check_program_basic (p:Ast.program) : issue list =
  let acc = ref [] in
  let names = List.map (fun n -> n.nname) p in
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
       let assumes = n.assumes in
       let guarantees = n.guarantees in
       if assumes = [] && guarantees = [] then
         acc := issue "node '%s' has no contracts" n.nname :: !acc)
    p;
  List.rev !acc

let check_program_monitor (p:Ast.program) : issue list =
  let _ = p in
  []

let check_program_obc (p:Ast.program) : issue list =
  let _ = p in
  []
