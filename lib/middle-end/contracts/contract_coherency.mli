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

(** {1 Contract Coherency} *)

(** Add post-conditions that imply successor requires (user contracts only). *)
val ensure_next_requires : Ast.node -> Ast.node

(** Reject contracts that reference [pre_k] before it can be defined from [init_state].
    If a monitor automaton is provided, reachability is computed on the product
    (program states, monitor states). *)
val validate_user_pre_k_definedness :
  ?monitor_automaton:Automaton_engine.automaton -> Ast.node -> unit

(** Add coherency constraints derived from user contracts. *)
val user_contracts_coherency : Ast.node -> Ast.node
