open Ast

let fresh_oid () = Provenance.fresh_id ()

let with_origin ?loc origin value =
  let oid = fresh_oid () in
  { value; origin = Some origin; oid; loc }

let map_with_origin f x = { x with value = f x.value; loc = x.loc }
let values xs = List.map (fun x -> x.value) xs
let origins xs = List.map (fun x -> x.origin) xs
