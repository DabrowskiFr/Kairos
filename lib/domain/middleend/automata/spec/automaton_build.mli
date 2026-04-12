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

(** Low-level bridge from a normalized Kairos LTL formula to the internal
    automaton representation.

    This module is responsible for invoking the external safety-automaton
    backend and normalizing its result into {!Automaton_types.automaton}. *)
open Core_syntax
val build :
  atom_map:((hexpr * relop * hexpr) * ident) list ->
  atom_names:ident list ->
  atom_named_exprs:(ident * expr) list ->
  ltl ->
  Automaton_types.automaton
(** [build ~atom_map ~atom_names ~atom_named_exprs spec] constructs the safety
    automaton for [spec], then normalizes states and guards into the automaton
    format consumed by the rest of the middleend. *)
