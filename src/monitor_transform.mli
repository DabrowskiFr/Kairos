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

(** {1 Monitor Naming} *)

(** Compute monitor state type. *)
val monitor_state_type : string
(** Compute monitor state name. *)
val monitor_state_name : string
(** Compute monitor state ctor. *)
val monitor_state_ctor : int -> string
(** Compute monitor state expr. *)
val monitor_state_expr : int -> Ast.iexpr

(** {1 Atom Naming} *)

(** Compute sanitize ident. *)
val sanitize_ident : string -> string
(** Make atom names. *)
val make_atom_names : (Ast.fo * Ast.iexpr) list -> string list

(** {1 Node Transforms} *)

(** Compute transform node. *)
val transform_node : Ast.node -> Ast.node
(** Compute monitor update stmts. *)
val monitor_update_stmts :
  Ast.ident list ->
  Automaton_core.residual_state list ->
  Automaton_core.guarded_transition list -> Ast.stmt list
(** Compute monitor assert. *)
val monitor_assert : int -> Ast.stmt list
(** Compute transform node monitor. *)
val transform_node_monitor : Ast.node -> Ast.node
