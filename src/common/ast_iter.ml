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

let iter_program (f:Ast.node -> unit) (p:Ast.program) : unit =
  List.iter f p

let iter_nodes (f:Ast.node -> unit) (p:Ast.program) : unit =
  iter_program f p

let iter_node_transitions (f:Ast.node -> Ast.transition -> unit) (p:Ast.program) : unit =
  List.iter
    (fun n -> List.iter (fun t -> f n t) (Ast.node_trans n))
    p

let iter_transitions (f:Ast.transition -> unit) (p:Ast.program) : unit =
  iter_node_transitions (fun _ t -> f t) p

let fold_nodes (f:'a -> Ast.node -> 'a) (init:'a) (p:Ast.program) : 'a =
  List.fold_left f init p

let fold_transitions (f:'a -> Ast.transition -> 'a) (init:'a) (p:Ast.program) : 'a =
  fold_nodes
    (fun acc n -> List.fold_left f acc (Ast.node_trans n))
    init
    p

let map_program (f:Ast.node -> Ast.node) (p:Ast.program) : Ast.program =
  List.map f p

let map_node_transitions (f:Ast.transition -> Ast.transition) (n:Ast.node) : Ast.node =
  let body = Ast.node_body n in
  let trans = List.map f body.trans in
  if trans == body.trans then n
  else Ast.with_node_body { body with trans } n

let map_transitions (f:Ast.transition -> Ast.transition) (p:Ast.program) : Ast.program =
  List.map (map_node_transitions f) p
