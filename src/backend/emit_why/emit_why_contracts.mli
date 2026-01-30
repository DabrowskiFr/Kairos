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
type contract_info = Emit_why_types.contract_info

(** {2 Invariants}

    - [build_contracts] expects [env_info] produced by [prepare_node].
    - [env_info.node] already carries pre_k normalization for invariants. *)

(** Build full contract terms (pre/post) and their labels. *)
val build_contracts :
  nodes:Ast.node list ->
  Emit_why_env.env_info ->
  contract_info
