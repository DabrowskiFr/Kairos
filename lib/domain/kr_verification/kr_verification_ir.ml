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

open Kr_domain_core_syntax
open Kr_verification_ir_shared

type formula_meta = {
  oid : formula_id;
  loc : Kr_domain_core_locations.loc option;
  family : string option;
}

type 'phase summary_formula = {
  logic : 'phase Kr_domain_core_syntax.hexpr;
  meta : formula_meta;
}

type temporal_layout = Kr_domain_core.Kr_domain_core_history.pre_k_info list

type product_state = Kr_verification_product.product_state = {
  prog_state : ident;
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

type monitor_state_pair = {
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

type transition = {
  src_state : ident;
  dst_state : ident;
  guard_expr : expr option;
  body_stmts : stmt list;
}

type 'phase product_case = {
  guarantee_destination_state_index : automaton_state_index;
  guarantee_guard : 'phase summary_formula;
}

type product_step_summary_trace = { step_uid : transition_index }

type 'phase product_step_summary_identity = {
  program_step : transition;
  monitor_source : monitor_state_pair;
  assume_destination_state_index : automaton_state_index;
  assume_guard : 'phase Kr_domain_core_syntax.hexpr;
}

type 'phase product_step_summary = {
  trace : product_step_summary_trace;
  identity : 'phase product_step_summary_identity;
  propagation_requires : 'phase summary_formula list;
  requires : 'phase summary_formula list;
  ensures : 'phase summary_formula list;
  elaboration_checks : 'phase summary_formula list;
  product_cases : 'phase product_case list;
}

let product_source (summary : 'phase product_step_summary) : product_state =
  {
    prog_state = summary.identity.program_step.src_state;
    assume_state_index = summary.identity.monitor_source.assume_state_index;
    guarantee_state_index =
      summary.identity.monitor_source.guarantee_state_index;
  }

let product_destination (summary : 'phase product_step_summary)
    (case : 'phase product_case) : product_state =
  {
    prog_state = summary.identity.program_step.dst_state;
    assume_state_index =
      summary.identity.assume_destination_state_index;
    guarantee_state_index =
      case.guarantee_destination_state_index;
  }

type node_signature = {
  sem_nname : ident;
  sem_type_decls : enum_decl list;
  sem_function_decls : pure_function_decl list;
  sem_methods : method_decl list;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
}

type state_invariant = Kr_domain_core_model.state_invariant = {
  state : ident;
  formula : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr;
}

type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  state_invariants : state_invariant list;
}

type 'phase node_ir = {
  semantics : node_signature;
  source_info : source_info;
  temporal_layout : temporal_layout;
  summaries : 'phase product_step_summary list;
}

type program_ir = { nodes : Kr_domain_core_syntax.history_free node_ir list }
