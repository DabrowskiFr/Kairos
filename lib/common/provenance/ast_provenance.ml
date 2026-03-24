open Ast

let fresh_oid () = Provenance.fresh_id ()

let with_origin ?loc origin value =
  let oid = fresh_oid () in
  let _ = origin in
  { value; oid; loc }

let map_with_origin f x = { x with value = f x.value; loc = x.loc }
let values xs = List.map (fun x -> x.value) xs
let origins xs = List.map (fun (_ : Ast.ltl_o) -> None) xs
