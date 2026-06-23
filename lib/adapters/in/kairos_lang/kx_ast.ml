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
open Kx_core_syntax

type invariant_state_rel = { state : ident; formula : hexpr } [@@deriving yojson]

type stmt = { stmt : stmt_desc; loc : Kx_loc.loc option }

and stmt_desc =
  | SAssign of ident * expr
  | SAssert of hexpr
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * hexpr list * expr option * stmt list
  | SMatch of expr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * expr list * ident list
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
  ensures : hexpr list;
}
[@@deriving yojson]

type node_semantics = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_instances : (ident * ident) list;
  sem_locals : vdecl list;
  sem_ghosts : vdecl list;
  sem_public_ghosts : ident list;
  sem_states : ident list;
  sem_init_state : ident;
  sem_trans : transition list;
}
[@@deriving yojson]

type node_specification = {
  spec_assumes : ltl list;
  spec_guarantees : ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}
[@@deriving yojson]

type node = {
  semantics : node_semantics;
  specification : node_specification;
}
[@@deriving yojson]

type program = node list [@@deriving yojson]

let semantics_of_node (n : node) : node_semantics =
  n.semantics

let specification_of_node (n : node) : node_specification =
  n.specification
