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

(** Intermediate artifact bundle derived from a pipeline snapshot.

    This payload is consumed by output mappers and diagnostic reports.
*)

type t = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
}

(** Build automata and product graph artifacts for [asts]. *)

val build :
  asts:Runtime_snapshot.ast_flow -> t
