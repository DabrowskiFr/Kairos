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

let map_node_contracts (f:Ast.node_contracts -> Ast.node_contracts) (n:Ast.node)
  : Ast.node =
  let contracts = f (Ast.node_contracts n) in
  if contracts == Ast.node_contracts n then n
  else Ast.with_node_contracts contracts n

let map_node_body (f:Ast.node_body -> Ast.node_body) (n:Ast.node) : Ast.node =
  let body = f (Ast.node_body n) in
  if body == Ast.node_body n then n
  else Ast.with_node_body body n

let map_transition_contracts
    (f:Ast.transition_contracts -> Ast.transition_contracts)
    (t:Ast.transition)
  : Ast.transition =
  let contracts = f (Ast.transition_contracts t) in
  if contracts == Ast.transition_contracts t then t
  else Ast.with_transition_contracts contracts t

let map_transition_body
    (f:Ast.transition_body -> Ast.transition_body)
    (t:Ast.transition)
  : Ast.transition =
  let body = f (Ast.transition_body_data t) in
  if body == Ast.transition_body_data t then t
  else Ast.with_transition_body_data body t

let map_program (f:Ast.node -> Ast.node) (p:Ast.program) : Ast.program =
  List.map f p
