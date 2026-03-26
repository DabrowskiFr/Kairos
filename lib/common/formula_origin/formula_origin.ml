type t =
  | UserContract
  | Instrumentation
  | Invariant
  | GuaranteeAutomaton
  | GuaranteePropagation
  | AssumeAutomaton
  | Internal
[@@deriving show, yojson]

let to_string = function
  | UserContract -> "user"
  | Instrumentation -> "instrumentation"
  | Invariant -> "invariant"
  | GuaranteeAutomaton -> "guarantee-automaton"
  | GuaranteePropagation -> "guarantee-propagation"
  | AssumeAutomaton -> "assume-automaton"
  | Internal -> "internal"

let of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "instrumentation" | "monitor" | "Instrumentation" -> Some Instrumentation
  | "invariant" | "Invariant" | "coherency" | "Coherency" -> Some Invariant
  | "guarantee-automaton" | "GuaranteeAutomaton" -> Some GuaranteeAutomaton
  | "guarantee-propagation" | "GuaranteePropagation" -> Some GuaranteePropagation
  | "assume-automaton" | "AssumeAutomaton" -> Some AssumeAutomaton
  | "internal" | "Internal" -> Some Internal
  | _ -> None
