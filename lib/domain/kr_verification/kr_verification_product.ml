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
open Kr_domain_core_syntax_builders
type product_state = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

type monitor_successor = {
  destination_state_index : int;
  guard : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr;
}

type product_prefix = {
  prog_transition : Kr_domain_core_model.program_step;
  assume_source_state_index : int;
  assume_successor : monitor_successor;
  guarantee_source_state_index : int;
  guarantee_successors : monitor_successor list;
}

type exploration = {
  initial_state : product_state;
  prefixes : product_prefix list;
}

let prefix_source prefix =
  {
    prog_state = prefix.prog_transition.src_state;
    assume_state_index = prefix.assume_source_state_index;
    guarantee_state_index =
      prefix.guarantee_source_state_index;
  }

let successor_destination prefix guarantee_successor =
  {
    prog_state = prefix.prog_transition.dst_state;
    assume_state_index =
      prefix.assume_successor.destination_state_index;
    guarantee_state_index =
      guarantee_successor.destination_state_index;
  }

let program_guard prefix =
  match prefix.prog_transition.guard_expr with
  | None -> mk_hbool true
  | Some guard ->
      hexpr_of_expr guard
      |> Kr_domain_core_syntax.historical_of_history_free
      |> Kr_domain_core_formula_simplifier.simplify

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

let states exploration =
  exploration.prefixes
  |> List.fold_left
       (fun accumulated prefix ->
         let accumulated =
           prefix_source prefix :: accumulated
         in
         List.fold_left
           (fun accumulated guarantee_successor ->
             successor_destination prefix
               guarantee_successor
             :: accumulated)
           accumulated prefix.guarantee_successors)
       [ exploration.initial_state ]
  |> List.sort_uniq compare_state

let step_count exploration =
  List.fold_left
    (fun count prefix ->
      count + List.length prefix.guarantee_successors)
    0 exploration.prefixes
