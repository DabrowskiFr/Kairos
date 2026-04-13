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

(** Abstract syntax tree for Kairos programs *)

open Core_syntax

(** {1 Core Types} *)


type invariant_state_rel = {
  state : ident;
  formula : hexpr;
}[@@deriving yojson]

(** {1 Statements & Invariants} *)

(** Executable statements. *)
type stmt = { stmt : stmt_desc; loc : Loc.loc option }
[@@deriving yojson]

and stmt_desc =
  | SAssign of ident * expr
  | SIf of expr * stmt list * stmt list
  | SMatch of expr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * expr list * ident list
[@@deriving yojson]

(** {1 Per-pass Metadata}

    Per-pass metadata is kept outside the AST in pipeline/runtime layers. *)

(** {1 Program Structure} *)

(** Source transition. *)
type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
}

(** Program-facing part of a node: state machine and transition semantics. *)
type node_semantics = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_instances : (ident * ident) list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
  sem_trans : transition list;
}

(** Specification-facing part of a node.

    Formulas may refer to current values through [HVar] and to bounded history
    through [HPreK]. *)
type node_specification = {
  spec_assumes : ltl list;
  spec_guarantees : ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}

(** Source node. *)
type node = {
  semantics : node_semantics;
  specification : node_specification;
}

(** A program is a list of nodes. *)
type program = node list

(** {2 Utilities}

    Structural queries live in {!module-Ast_queries}. *)

val semantics_of_node : node -> node_semantics
(** [specification_of_node] service entrypoint. *)

val specification_of_node : node -> node_specification
