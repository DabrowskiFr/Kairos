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

(** Stable naming and lightweight string render helpers for kernel/product IR. *)
open Core_syntax

val phase_state_case_name : prog_state:ident -> guarantee_state:int -> string
val phase_step_pre_case_name : Proof_kernel_types.product_step_ir -> string
val phase_step_post_case_name : Proof_kernel_types.product_step_ir -> string

val string_of_role : Proof_kernel_types.automaton_role -> string
val string_of_step_kind : Proof_kernel_types.product_step_kind -> string
val string_of_step_origin : Proof_kernel_types.product_step_origin -> string
val string_of_product_coverage : Proof_kernel_types.product_coverage_ir -> string
val string_of_clause_origin : Proof_kernel_types.generated_clause_origin -> string
val string_of_clause_time : Proof_kernel_types.clause_time_ir -> string
val string_of_clause_fact_desc : Proof_kernel_types.clause_fact_desc_ir -> string
val string_of_relational_clause_fact_desc :
  Proof_kernel_types.relational_clause_fact_desc_ir -> string
val string_of_clause_fact : Proof_kernel_types.clause_fact_ir -> string
val string_of_relational_clause_fact : Proof_kernel_types.relational_clause_fact_ir -> string
val string_of_product_state : Proof_kernel_types.product_state_ir -> string
val string_of_edge : Proof_kernel_types.automaton_edge_ir -> string
