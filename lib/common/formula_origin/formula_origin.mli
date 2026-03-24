type t =
  | UserContract
  | Instrumentation
  | Coherency
  | Compatibility
  | AssumeAutomaton
  | Internal
[@@deriving show, yojson]

val to_string : t -> string
val of_string : string -> t option
