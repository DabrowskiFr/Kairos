open Ast

module FoSet = Set.Make (struct
  type t = fo

  let compare = compare
end)

let origin_to_string = function
  | UserContract -> "user"
  | Monitor -> "monitor"
  | Coherency -> "coherency"
  | Compatibility -> "compatibility"
  | AssumeAutomaton -> "assume-automaton"
  | Internal -> "internal"

let origin_of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "monitor" | "Monitor" -> Some Monitor
  | "coherency" | "Coherency" -> Some Coherency
  | "compatibility" | "Compatibility" -> Some Compatibility
  | "assume-automaton" | "AssumeAutomaton" -> Some AssumeAutomaton
  | "internal" | "Internal" -> Some Internal
  | _ -> None

let loc_to_string (l : loc) : string =
  Printf.sprintf "%d:%d-%d:%d" l.line l.col l.line_end l.col_end

let compare_loc (a : loc) (b : loc) : int =
  match Stdlib.compare a.line b.line with
  | 0 -> begin
      match Stdlib.compare a.col b.col with
      | 0 -> begin
          match Stdlib.compare a.line_end b.line_end with
          | 0 -> Stdlib.compare a.col_end b.col_end
          | c -> c
        end
      | c -> c
    end
  | c -> c

let is_input_of_node (n : node) (v : ident) : bool = List.exists (fun vd -> vd.vname = v) n.inputs
let input_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.inputs
let output_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.outputs

let transitions_from_state_fn (n : node) : ident -> transition list =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let ts = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t :: ts))
    n.trans;
  fun src -> Hashtbl.find_opt by_src src |> Option.value ~default:[]

let requires_from_state_fn (n : node) : ident -> fo list =
  let transitions_from_state = transitions_from_state_fn n in
  let transition_requires (t : transition) = Ast_provenance.values t.requires in
  fun src -> transitions_from_state src |> List.rev |> List.concat_map transition_requires

let add_new_coherency_goals (n : node) (new_goals : fo list) : node =
  let existing_values = List.map (fun (f : fo_o) -> f.value) n.attrs.coherency_goals in
  let existing_set = FoSet.of_list existing_values in
  let new_set = FoSet.of_list new_goals in
  let only_new =
    FoSet.diff new_set existing_set |> FoSet.elements
    |> List.map (Ast_provenance.with_origin Coherency)
  in
  if only_new = [] then n
  else { n with attrs = { n.attrs with coherency_goals = n.attrs.coherency_goals @ only_new } }

let show_program = show_program
