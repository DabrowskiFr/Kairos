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
  assume_state_index : int;
  guarantee_state_index : int;
}

type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Verification_model.program_step;
  prog_guard : Core_syntax.historical Core_syntax.hexpr;
  assume_guard : Core_syntax.historical Core_syntax.hexpr;
  guarantee_guard : Core_syntax.historical Core_syntax.hexpr;
}

type product_prefix = {
  src : product_state;
  assume_destination_state_index : int;
  prog_transition : Verification_model.program_step;
  prog_guard : Core_syntax.historical Core_syntax.hexpr;
  assume_guard : Core_syntax.historical Core_syntax.hexpr;
}

type exploration = {
  initial_state : product_state;
  states : product_state list;
  steps : product_step list;
  prefixes : product_prefix list;
}

let compare_state a b =
  match String.compare a.prog_state b.prog_state with
  | 0 -> begin
      match
        Int.compare a.assume_state_index b.assume_state_index
      with
      | 0 ->
          Int.compare a.guarantee_state_index
            b.guarantee_state_index
      | c -> c
    end
  | c -> c
