open Ast

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

let is_input_of_node (n : node) (v : ident) : bool =
  List.exists (fun vd -> vd.vname = v) n.semantics.sem_inputs

let input_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.semantics.sem_inputs
let output_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.semantics.sem_outputs

let transitions_from_state_fn (n : node) : ident -> transition list =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let ts = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t :: ts))
    n.semantics.sem_trans;
  fun src -> Hashtbl.find_opt by_src src |> Option.value ~default:[]
