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

(** Taxonomy used to classify generated proof obligations and helper goals. *)

(** Fine-grained backend families emitted by the implementation.

    They are later projected onto:
    - semantic clause families (`no_bad`, `initial_goal`, `user_invariant`,
      `automaton_support`);
    - proof layers (`safety`, `helper`);
    - helper phases (`init_goal`, `propagation`).

    This mirrors the current Rocq/paper architecture where the four semantic
    labels classify generated clauses, while the actual proof split is
    `Safety` versus `Helper`. *)
type family =
  | FamTransitionRequires
  | FamTransitionEnsures
  | FamGuaranteeViolationForbidden
  | FamInvariantRequires
  | FamInvariantEnsuresShifted
  | FamInitialInvariantGoal
  | FamNoBadRequires
  | FamNoBadEnsures
  | FamGuaranteePropagationRequires
  | FamGuaranteeAutomatonEnsures
  | FamStateAwareAssumptionRequires

type category =
  | CatNoBad
  | CatInitialGoal
  | CatUserInvariant
  | CatAutomatonSupport

type major_class = Safety | Helper

type helper_phase =
  | InitGoal
  | Propagation

type helper_kind =
  | UserInvariant
  | AutomatonSupport

type summary = {
  total : int;
  counts : (family * int) list;
  generated_total : int;
  category_counts : (category * int) list;
  major_counts : (major_class * int) list;
  helper_phase_counts : (helper_phase * int) list;
  helper_kind_counts : (helper_kind * int) list;
}

val family_name : family -> string
val category_name : category -> string
val category_of_family : family -> category option
val major_class_name : major_class -> string
val major_class_of_category : category -> major_class
val helper_phase_name : helper_phase -> string
val helper_phase_of_category : category -> helper_phase option
val helper_kind_name : helper_kind -> string
val helper_kind_of_category : category -> helper_kind option
val summarize_program : Ir.node_ir list -> summary
val render_summary : summary -> string
val to_stage_meta : summary -> (string * string) list
