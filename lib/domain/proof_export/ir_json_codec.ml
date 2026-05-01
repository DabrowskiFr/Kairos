(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let ( let* ) = Result.bind

let formula_meta_to_yojson (m : Ir.formula_meta) : Yojson.Safe.t =
  let option_to_yojson f = function None -> `Null | Some x -> f x in
  `Assoc
    [
      ("oid", `Int m.oid);
      ("loc", option_to_yojson Loc.loc_to_yojson m.loc);
    ]

let formula_meta_of_yojson (json : Yojson.Safe.t) : (Ir.formula_meta, string) result =
  let option_of_yojson f = function `Null -> Ok None | x -> Result.map Option.some (f x) in
  match json with
  | `Assoc fields ->
      let find name = List.assoc_opt name fields in
      let* oid_json = Option.to_result ~none:"formula_meta: missing field 'oid'" (find "oid") in
      let* loc_json = Option.to_result ~none:"formula_meta: missing field 'loc'" (find "loc") in
      let* loc = option_of_yojson Loc.loc_of_yojson loc_json in
      let oid =
        match oid_json with
        | `Int n -> Ok n
        | _ -> Error "formula_meta.oid: expected int"
      in
      let* oid = oid in
      Ok { Ir.oid; loc }
  | _ -> Error "formula_meta: expected object"

let summary_formula_to_yojson (f : Ir.summary_formula) : Yojson.Safe.t =
  `Assoc
    [
      ("logic", Core_syntax.hexpr_to_yojson f.logic);
      ("meta", formula_meta_to_yojson f.meta);
    ]

let summary_formula_of_yojson (json : Yojson.Safe.t) : (Ir.summary_formula, string) result =
  match json with
  | `Assoc fields ->
      let find name =
        match List.assoc_opt name fields with
        | Some v -> Ok v
        | None -> Error (Printf.sprintf "summary_formula: missing field '%s'" name)
      in
      let* logic_json = find "logic" in
      let* meta_json = find "meta" in
      let* logic = Core_syntax.hexpr_of_yojson logic_json in
      let* meta = formula_meta_of_yojson meta_json in
      Ok { Ir.logic; meta }
  | _ -> Error "summary_formula: expected object"

let summary_formula_list_to_yojson (xs : Ir.summary_formula list) : Yojson.Safe.t =
  `List (List.map summary_formula_to_yojson xs)

let summary_formula_list_of_yojson (json : Yojson.Safe.t) :
    (Ir.summary_formula list, string) result =
  match json with
  | `List items ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | x :: xs ->
            let* decoded = summary_formula_of_yojson x in
            go (decoded :: acc) xs
      in
      go [] items
  | _ -> Error "summary_formula list: expected list"
