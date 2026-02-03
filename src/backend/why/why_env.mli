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

(** {1 Monitor Constructor Discovery} *)

(** Detect if an identifier is a monitor state constructor. *)
val is_mon_state_ctor : string -> bool
(** Collect monitor state constructors referenced by a node. *)
val collect_mon_state_ctors : Ast.node -> Ast.ident list

(** {1 Why3 Environment Preparation} *)

(** Precomputed data for emitting a node. *)
type env_info = Why_types.env_info

(** {2 Invariants}

    - [node] is the node used for emission.
    - [inputs] includes the implicit [vars] record binder (and inputs if any).
    - [env] records links/ghosts/pre_k derived from [node] and collection passes. *)

(** Build environment data needed by the Why3 emission stages. *)
val prepare_node : prefix_fields:bool -> nodes:Ast.node list -> Ast.node -> env_info
