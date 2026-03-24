type t =
  | UserContract
  | Instrumentation
  | Coherency
  | Compatibility
  | AssumeAutomaton
  | Internal
[@@deriving show, yojson]

let to_string = function
  | UserContract -> "user"
  | Instrumentation -> "instrumentation"
  | Coherency -> "coherency"
  | Compatibility -> "compatibility"
  | AssumeAutomaton -> "assume-automaton"
  | Internal -> "internal"

let of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "instrumentation" | "monitor" | "Instrumentation" -> Some Instrumentation
  | "coherency" | "Coherency" -> Some Coherency
  | "compatibility" | "Compatibility" -> Some Compatibility
  | "assume-automaton" | "AssumeAutomaton" -> Some AssumeAutomaton
  | "internal" | "Internal" -> Some Internal
  | _ -> None
