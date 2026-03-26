open Ast

let fresh_oid () = Provenance.fresh_id ()

let with_origin ?loc origin value =
  let oid = fresh_oid () in
  let _ = origin in
  { value; oid; loc }
