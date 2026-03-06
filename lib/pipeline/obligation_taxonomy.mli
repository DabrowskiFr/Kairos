open Ast

(** Obligation families mirrored from the Rocq refactoring taxonomy. *)
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

type summary = { total : int; counts : (family * int) list }

val family_name : family -> string
val summarize_program : program -> summary
val render_summary : summary -> string
val to_stage_meta : summary -> (string * string) list
