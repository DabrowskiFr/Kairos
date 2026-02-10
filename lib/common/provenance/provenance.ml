type id = int

let counter = ref 0
let parents_tbl : (id, id list) Hashtbl.t = Hashtbl.create 1024

let reset () =
  counter := 0;
  Hashtbl.reset parents_tbl

let fresh_id () =
  incr counter;
  let id = !counter in
  Hashtbl.replace parents_tbl id [];
  id

let register id =
  if not (Hashtbl.mem parents_tbl id) then
    Hashtbl.add parents_tbl id []

let add_parents ~child ~parents =
  let existing = Hashtbl.find_opt parents_tbl child |> Option.value ~default:[] in
  let merged =
    List.fold_left
      (fun acc p -> if List.mem p acc then acc else acc @ [p])
      existing
      parents
  in
  Hashtbl.replace parents_tbl child merged;
  List.iter register parents

let parents id =
  Hashtbl.find_opt parents_tbl id |> Option.value ~default:[]

let ancestors id =
  let visited = Hashtbl.create 128 in
  let rec dfs acc = function
    | [] -> acc
    | x :: xs ->
        if Hashtbl.mem visited x then dfs acc xs
        else (
          Hashtbl.add visited x ();
          let ps = parents x in
          dfs (x :: acc) (ps @ xs)
        )
  in
  List.rev (dfs [] (parents id))
