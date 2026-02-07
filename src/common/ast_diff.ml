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

let diff_program (a:Ast.program) (b:Ast.program) : string list =
  let acc = ref [] in
  let names p = List.map (fun n -> (Ast.node_sig n).nname) p in
  let a_names = names a in
  let b_names = names b in
  if List.length a_names <> List.length b_names then
    acc := Printf.sprintf "node count differs: %d vs %d"
      (List.length a_names) (List.length b_names) :: !acc;
  List.iter
    (fun name ->
       if not (List.mem name b_names) then
         acc := Printf.sprintf "node missing in right: %s" name :: !acc)
    a_names;
  List.iter
    (fun name ->
       if not (List.mem name a_names) then
         acc := Printf.sprintf "node missing in left: %s" name :: !acc)
    b_names;
  List.iter
    (fun n ->
       match List.find_opt (fun m -> (Ast.node_sig m).nname = (Ast.node_sig n).nname) b with
       | None -> ()
       | Some m ->
           let t1 = List.length (Ast.node_trans n) in
           let t2 = List.length (Ast.node_trans m) in
           if t1 <> t2 then
             acc := Printf.sprintf "node %s transition count differs: %d vs %d"
               (Ast.node_sig n).nname t1 t2 :: !acc)
    a;
  List.rev !acc

let merge_program_attrs ~prefer_right ~(left:Ast.program) ~(right:Ast.program)
  : Ast.program =
  let choose a b = if prefer_right then b else a in
  let merge_node_attrs (a:Ast.node) (b:Ast.node) : Ast.node =
    let attrs = choose (Ast.node_attrs a) (Ast.node_attrs b) in
    Ast.with_node_attrs attrs a
  in
  let merge_transition_attrs (a:Ast.transition) (b:Ast.transition) : Ast.transition =
    let attrs = choose (Ast.transition_attrs a) (Ast.transition_attrs b) in
    Ast.with_transition_attrs attrs a
  in
  List.map
    (fun n ->
       match List.find_opt (fun m -> (Ast.node_sig m).nname = (Ast.node_sig n).nname) right with
       | None -> n
       | Some m ->
           let n = merge_node_attrs n m in
           let body = Ast.node_body n in
           let trans =
             List.mapi
               (fun i t ->
                  match List.nth_opt (Ast.node_trans m) i with
                  | None -> t
                  | Some t2 -> merge_transition_attrs t t2)
               body.trans
           in
           if trans == body.trans then n
           else Ast.with_node_body { body with trans } n)
    left
