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

open Ir_shared_types

type formula_meta = {
  oid : formula_id;
  loc : loc option;
}

type summary_formula = {
  logic : Core_syntax.hexpr;
  meta : formula_meta;
}

type temporal_layout = (hexpr * Temporal_support.pre_k_info) list

type product_state = {
  prog_state : ident;
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

type transition = {
  src_state : ident;
  dst_state : ident;
  guard_expr : expr option;
  body_stmts : stmt list;
}

type safe_product_case = {
  product_dst : product_state;
  admissible_guard : summary_formula;
}

type unsafe_product_case = {
  product_dst : product_state;
  excluded_guard : summary_formula;
}

type product_step_summary_trace = { step_uid : transition_index }

type product_step_summary_identity = {
  program_step : transition;
  product_src : product_state;
  assume_guard : Core_syntax.hexpr;
}

type product_step_summary = {
  trace : product_step_summary_trace;
  identity : product_step_summary_identity;
  propagation_requires : summary_formula list;
  requires : summary_formula list;
  ensures : summary_formula list;
  safe_cases : safe_product_case list;
  unsafe_cases : unsafe_product_case list;
}

type node_signature = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
}

type state_invariant = {
  state : ident;
  formula : Core_syntax.hexpr;
}

type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  state_invariants : state_invariant list;
}

type node_ir = {
  semantics : node_signature;
  source_info : source_info;
  temporal_layout : temporal_layout;
  summaries : product_step_summary list;
  init_invariant_goals : summary_formula list;
}

type program_ir = { nodes : node_ir list }
