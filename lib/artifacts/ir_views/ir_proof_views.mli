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

open Ast

type transition_clauses = {
  requires : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
}

type raw_transition = {
  core : Ir.transition;
  guard : Fo_formula.t;
}

type node_core = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
}

type raw_node = {
  core : node_core;
  temporal_layout : Ir.temporal_layout;
  transitions : raw_transition list;
  assumes : ltl list;
  guarantees : ltl list;
}

type annotated_transition = {
  raw : raw_transition;
  clauses : transition_clauses;
}

type annotated_node = {
  raw : raw_node;
  transitions : annotated_transition list;
  init_invariant_goals : Ir.summary_formula list;
}

type verified_transition = {
  core : Ir.transition;
  guard : Fo_formula.t;
  clauses : transition_clauses;
}

type verified_node = {
  core : node_core;
  transitions : verified_transition list;
  product_transitions : Ir.product_step_summary list;
  assumes : ltl list;
  guarantees : ltl list;
  init_invariant_goals : Ir.summary_formula list;
}
