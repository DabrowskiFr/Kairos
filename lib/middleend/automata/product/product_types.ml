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
open Core_syntax
type product_state = {
  prog_state : ident;
  assume_state : int;
  guarantee_state : int;
}

type step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type automaton_edge = Automaton_types.transition

type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Ir.transition;
  prog_guard : Fo_formula.t;
  assume_edge : automaton_edge;
  assume_guard : Fo_formula.t;
  guarantee_edge : automaton_edge;
  guarantee_guard : Fo_formula.t;
  step_class : step_class;
}

type exploration = {
  initial_state : product_state;
  states : product_state list;
  steps : product_step list;
}

let compare_state a b =
  match String.compare a.prog_state b.prog_state with
  | 0 -> begin
      match Int.compare a.assume_state b.assume_state with
      | 0 -> Int.compare a.guarantee_state b.guarantee_state
      | c -> c
    end
  | c -> c
