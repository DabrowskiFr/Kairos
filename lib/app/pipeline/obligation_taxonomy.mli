(** Taxonomy used to classify generated proof obligations and helper goals. *)

open Ast

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
  | FamCoherencyRequires
  | FamCoherencyEnsuresShifted
  | FamInitialCoherencyGoal
  | FamNoBadRequires
  | FamNoBadEnsures
  | FamMonitorCompatibilityRequires
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
val summarize_program : program -> summary
val render_summary : summary -> string
val to_stage_meta : summary -> (string * string) list
