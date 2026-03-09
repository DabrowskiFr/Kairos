type t = Idle | Parsing | Building | Proving | Completed | Failed

let to_string = function
  | Idle -> "Idle"
  | Parsing -> "Parsing"
  | Building -> "Building"
  | Proving -> "Proving"
  | Completed -> "Completed"
  | Failed -> "Failed"

let is_active = function Parsing | Building | Proving -> true | _ -> false
