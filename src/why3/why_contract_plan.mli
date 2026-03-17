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

type transition_contracts = {
  transition_requires_pre_terms : (Why3.Ptree.term * string) list;
  transition_requires_pre : Why3.Ptree.term list;
  post_contract_terms : Why3.Ptree.term list;
  pure_post : Why3.Ptree.term list;
  post_terms : (Why3.Ptree.term * string) list;
  post_terms_vcid : (Why3.Ptree.term * string) list;
}

type link_contracts = {
  link_terms_pre : Why3.Ptree.term list;
  link_terms_post : Why3.Ptree.term list;
  instance_invariants : Why3.Ptree.term list;
  instance_delay_links_inv : Why3.Ptree.term list;
  link_invariants : Why3.Ptree.term list;
}

val compute_transition_contracts :
  env:Support.env ->
  runtime_transitions:Why_runtime_view.runtime_transition_view list ->
  labeled_trans:
    (Why_runtime_view.runtime_transition_view * (Ast.fo_o * string) list * (Ast.fo_ltl * string * string) list) list ->
  has_monitor_instrumentation:bool ->
  post_contract_user:Why3.Ptree.term list ->
  use_kernel_product_contracts:bool ->
  init_for_var:(Ast.ident -> Ast.iexpr) ->
  apply_k_guard:(in_post:bool -> int option -> Why3.Ptree.term list -> Why3.Ptree.term list) ->
  transition_contracts

val compute_link_contracts :
  env:Support.env ->
  runtime:Why_runtime_view.t ->
  kernel_contract:Kernel_guided_contract.node_contract option ->
  current_temporal_contract:Kernel_guided_contract.exported_summary_contract ->
  use_kernel_product_contracts:bool ->
  has_instance_calls:bool ->
  hexpr_needs_old:(Ast.hexpr -> bool) ->
  instance_relation_term:
    (?in_post:bool -> Product_kernel_ir.instance_relation_ir -> Why3.Ptree.term option) ->
  link_contracts
