(** Origin tags attached to contract formulas.

    These tags classify formulas for:
    {ul
    {- diagnostics;}
    {- rendering;}
    {- obligation labeling.}} *)
type t =
  | UserContract
  | Instrumentation
  | Invariant
  | GuaranteeAutomaton
  | GuaranteeViolation
  | GuaranteePropagation
  | AssumeAutomaton
  | ProgramGuard
  | Internal
[@@deriving show, yojson]

(** Stable textual encoding used in artifacts and diagnostics. *)
val to_string : t -> string

(** Partial inverse of {!to_string}. *)
val of_string : string -> t option
