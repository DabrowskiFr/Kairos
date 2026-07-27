(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Backend-independent canonical keys and physical interning for formulas. *)

type key =
  | KInt of int
  | KBool of bool
  | KEnum of string
  | KVar of string
  | KPreK of string * int
  | KPred of string * key list
  | KFunCall of string * key list
  | KBin of Core_syntax.binop * key * key
  | KCmp of Core_syntax.relop * key * key
  | KUn of Core_syntax.unop * key

let rec exact_key :
    type phase. phase Core_syntax.hexpr -> key =
 fun formula ->
  match formula.hexpr with
  | HLitInt value -> KInt value
  | HLitBool value -> KBool value
  | HLitEnum name -> KEnum name
  | HVar name -> KVar name
  | HPreK (name, depth) -> KPreK (name, depth)
  | HPred (name, args) -> KPred (name, List.map exact_key args)
  | HFunCall (name, args) -> KFunCall (name, List.map exact_key args)
  | HBin (op, lhs, rhs) -> KBin (op, exact_key lhs, exact_key rhs)
  | HCmp (op, lhs, rhs) -> KCmp (op, exact_key lhs, exact_key rhs)
  | HUn (op, inner) -> KUn (op, exact_key inner)

let key ?(normalize = Fun.id) formula = exact_key (normalize formula)

type 'phase pool = (key, 'phase Core_syntax.hexpr) Hashtbl.t

let create_pool ?(size = 512) () = Hashtbl.create size

let intern ?(normalize = Fun.id) pool formula =
  let formula = normalize formula in
  let formula_key = exact_key formula in
  match Hashtbl.find_opt pool formula_key with
  | Some representative -> representative
  | None ->
      Hashtbl.add pool formula_key formula;
      formula
