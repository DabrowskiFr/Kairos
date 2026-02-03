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

(** {1 Fold Contracts} *)

(** Compute fold post terms. *)
val fold_post_terms : Support.env -> Support.fold_info -> Why3.Ptree.term list

(** {1 Contract Assembly} *)

(** Pre/post conditions with label groups for UI diagnostics. *)
type contract_info = Why_types.contract_info

(** Enable/disable pure translation mode (no extra contract generation). *)
val set_pure_translation : bool -> unit

(** {2 Invariants}

    - [build_contracts] expects [env_info] produced by [prepare_node]. *)

(** Build full contract terms (pre/post) and their labels. *)
val build_contracts :
  nodes:Ast.node list ->
  Why_env.env_info ->
  contract_info
