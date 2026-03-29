type t =
  | UserContract
  | Instrumentation
  | Invariant
  | GuaranteeAutomaton
  | GuaranteeViolation
  | GuaranteePropagation
  | AssumeAutomaton
  | ProgramGuard
  | StateStability
  | Internal
[@@deriving show, yojson]

let to_string = function
  | UserContract -> "user"
  | Instrumentation -> "instrumentation"
  | Invariant -> "invariant"
  | GuaranteeAutomaton -> "guarantee-automaton"
  | GuaranteeViolation -> "guarantee-violation"
  | GuaranteePropagation -> "guarantee-propagation"
  | AssumeAutomaton -> "assume-automaton"
  | ProgramGuard -> "program-guard"
  | StateStability -> "state-stability"
  | Internal -> "internal"

let of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "instrumentation" | "monitor" | "Instrumentation" -> Some Instrumentation
  | "invariant" | "Invariant" | "coherency" | "Coherency" -> Some Invariant
  | "guarantee-automaton" | "GuaranteeAutomaton" -> Some GuaranteeAutomaton
  | "guarantee-violation" | "GuaranteeViolation" -> Some GuaranteeViolation
  | "guarantee-propagation" | "GuaranteePropagation" -> Some GuaranteePropagation
  | "assume-automaton" | "AssumeAutomaton" -> Some AssumeAutomaton
  | "program-guard" | "ProgramGuard" -> Some ProgramGuard
  | "state-stability" | "StateStability" -> Some StateStability
  | "internal" | "Internal" -> Some Internal
  | _ -> None
