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

(** Semantic collection helpers over AST programs: temporal history, call
    sites, and lightweight spec heuristics. *)

val collect_hexpr : Ast.hexpr -> Ast.hexpr list -> Ast.hexpr list
val collect_ltl : Ast.ltl -> Ast.hexpr list -> Ast.hexpr list
val collect_fo : Ast.fo_atom -> Ast.hexpr list -> Ast.hexpr list

val collect_pre_k_from_specs :
  fo_atom:Ast.ltl list ->
  fo_formula:Fo_formula.t list ->
  ltl:Ast.ltl list ->
  invariants_user:Ast.invariant_user list ->
  invariants_state_rel:Ast.invariant_state_rel list ->
  Ast.hexpr list

val build_pre_k_infos_from_parts :
  inputs:Ast.vdecl list ->
  locals:Ast.vdecl list ->
  outputs:Ast.vdecl list ->
  fo_formulas:Fo_formula.t list ->
  ltl:Ast.ltl list ->
  invariants_user:Ast.invariant_user list ->
  invariants_state_rel:Ast.invariant_state_rel list ->
  (Ast.hexpr * Temporal_support.pre_k_info) list

val build_pre_k_infos : Ast.node -> (Ast.hexpr * Temporal_support.pre_k_info) list

val collect_calls_stmt :
  (Ast.ident * Ast.iexpr list) list -> Ast.stmt -> (Ast.ident * Ast.iexpr list) list

val collect_calls_trans : Ast.transition list -> (Ast.ident * Ast.iexpr list) list

val collect_calls_stmt_full :
  (Ast.ident * Ast.iexpr list * Ast.ident list) list ->
  Ast.stmt ->
  (Ast.ident * Ast.iexpr list * Ast.ident list) list

val collect_calls_trans_full :
  Ast.transition list -> (Ast.ident * Ast.iexpr list * Ast.ident list) list

val extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option
