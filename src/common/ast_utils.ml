open Ast

let origin_to_string = function
  | UserContract -> "user"
  | Monitor -> "monitor"
  | Coherency -> "coherency"
  | Compatibility -> "compatibility"
  | Internal -> "internal"

let origin_of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "monitor" | "Monitor" -> Some Monitor
  | "coherency" | "Coherency" -> Some Coherency
  | "compatibility" | "Compatibility" -> Some Compatibility
  | "internal" | "Internal" -> Some Internal
  | _ -> None

let loc_to_string (l:loc) : string =
  Printf.sprintf "%d:%d-%d:%d" l.line l.col l.line_end l.col_end

let compare_loc (a:loc) (b:loc) : int =
  match Stdlib.compare a.line b.line with
  | 0 ->
      begin match Stdlib.compare a.col b.col with
      | 0 ->
          begin match Stdlib.compare a.line_end b.line_end with
          | 0 -> Stdlib.compare a.col_end b.col_end
          | c -> c
          end
      | c -> c
      end
  | c -> c

let show_program = show_program
