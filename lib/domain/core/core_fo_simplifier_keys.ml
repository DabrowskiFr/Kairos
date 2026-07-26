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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module StringSet = Set.Make (String)

type hexpr = Core_syntax.hexpr
type binop = Core_syntax.binop
type relop = Core_syntax.relop

let mk_h desc = Core_syntax_builders.mk_hexpr desc
let htrue = Core_syntax_builders.mk_hbool true
let hfalse = Core_syntax_builders.mk_hbool false

let is_htrue h =
  let open Core_syntax in
  match h with { hexpr = HLitBool true; _ } -> true | _ -> false

let is_hfalse h =
  let open Core_syntax in
  match h with { hexpr = HLitBool false; _ } -> true | _ -> false

let key_of_hexpr (h : hexpr) : string =
  let open Core_syntax in
  let buf = Buffer.create 64 in
  let rec add h =
    match h.hexpr with
    | HLitInt n ->
        Buffer.add_string buf "i:";
        Buffer.add_string buf (string_of_int n)
    | HLitBool b ->
        Buffer.add_string buf "b:";
        Buffer.add_string buf (string_of_bool b)
    | HLitEnum c ->
        Buffer.add_string buf "e:";
        Buffer.add_string buf c
    | HVar v ->
        Buffer.add_string buf "v:";
        Buffer.add_string buf v
    | HPreK (v, k) ->
        Buffer.add_string buf "p:";
        Buffer.add_string buf (string_of_int k);
        Buffer.add_char buf ':';
        Buffer.add_string buf v
    | HPred (id, hs) ->
        Buffer.add_string buf "pred:";
        Buffer.add_string buf id;
        Buffer.add_char buf '(';
        add_list hs;
        Buffer.add_char buf ')'
    | HFunCall (id, hs) ->
        Buffer.add_string buf "fun:";
        Buffer.add_string buf id;
        Buffer.add_char buf '(';
        add_list hs;
        Buffer.add_char buf ')'
    | HUn (op, inner) ->
        Buffer.add_string buf (match op with Neg -> "neg" | Not -> "not");
        Buffer.add_char buf '(';
        add inner;
        Buffer.add_char buf ')'
    | HBin (op, a, b) ->
        Buffer.add_string buf
          (match op with
          | Add -> "+"
          | Sub -> "-"
          | Mul -> "*"
          | Div -> "/"
          | And -> "and"
          | Or -> "or");
        Buffer.add_char buf '(';
        add a;
        Buffer.add_char buf ',';
        add b;
        Buffer.add_char buf ')'
    | HCmp (op, a, b) ->
        Buffer.add_string buf
          (match op with
          | REq -> "="
          | RNeq -> "<>"
          | RLt -> "<"
          | RLe -> "<="
          | RGt -> ">"
          | RGe -> ">=");
        Buffer.add_char buf '(';
        add a;
        Buffer.add_char buf ',';
        add b;
        Buffer.add_char buf ')'
  and add_list = function
    | [] -> ()
    | [ x ] -> add x
    | x :: xs ->
        add x;
        Buffer.add_char buf ',';
        add_list xs
  in
  add h;
  Buffer.contents buf

let const_key_of_hexpr h =
  let open Core_syntax in
  match h with
  | { hexpr = HLitInt n; _ } -> Some ("i:" ^ string_of_int n)
  | { hexpr = HLitBool b; _ } -> Some ("b:" ^ string_of_bool b)
  | { hexpr = HLitEnum c; _ } -> Some ("e:" ^ c)
  | _ -> None

let subject_key_of_hexpr h =
  let open Core_syntax in
  match h with
  | { hexpr = HVar v; _ } -> Some ("v:" ^ v)
  | { hexpr = HPreK (v, k); _ } -> Some ("p:" ^ string_of_int k ^ ":" ^ v)
  | _ -> None

type rel_lit = { subject : string; op : relop; value : string }

let rel_lit_of_hexpr (h : hexpr) : rel_lit option =
  let open Core_syntax in
  match h.hexpr with
  | HCmp (((REq | RNeq) as op), a, b) ->
      begin match (subject_key_of_hexpr a, const_key_of_hexpr b) with
      | Some subject, Some value -> Some { subject; op; value }
      | _ ->
          begin match (subject_key_of_hexpr b, const_key_of_hexpr a) with
          | Some subject, Some value -> Some { subject; op; value }
          | _ -> None
          end
      end
  | _ -> None

let ordered_pair_key prefix a b =
  let ka = key_of_hexpr a in
  let kb = key_of_hexpr b in
  if String.compare ka kb <= 0 then prefix ^ ka ^ ":" ^ kb else prefix ^ kb ^ ":" ^ ka

let comparison_literal_key op a b =
  let ka = key_of_hexpr a in
  let kb = key_of_hexpr b in
  match op with
  | Core_syntax.REq -> Some (ordered_pair_key "eq:" a b, true)
  | Core_syntax.RNeq -> Some (ordered_pair_key "eq:" a b, false)
  | Core_syntax.RLt -> Some ("lt:" ^ ka ^ ":" ^ kb, true)
  | Core_syntax.RGe -> Some ("lt:" ^ ka ^ ":" ^ kb, false)
  | Core_syntax.RGt -> Some ("lt:" ^ kb ^ ":" ^ ka, true)
  | Core_syntax.RLe -> Some ("lt:" ^ kb ^ ":" ^ ka, false)

let rec literal_key (h : hexpr) : (string * bool) option =
  let open Core_syntax in
  match h.hexpr with
  | HCmp (op, a, b) -> comparison_literal_key op a b
  | HUn (Not, inner) -> Option.map (fun (key, sign) -> (key, not sign)) (literal_key inner)
  | HVar _ | HPred _ | HFunCall _ -> Some ("bool:" ^ key_of_hexpr h, true)
  | _ -> None

let are_complements a b =
  match (literal_key a, literal_key b) with
  | Some (ka, sa), Some (kb, sb) -> String.equal ka kb && Bool.equal sa (not sb)
  | _ -> false

let negate_relop op =
  let open Core_syntax in
  match op with REq -> RNeq | RNeq -> REq | RLt -> RGe | RLe -> RGt | RGt -> RLe | RGe -> RLt

let eval_const_rel (op : relop) (a : hexpr) (b : hexpr) : bool option =
  let open Core_syntax in
  match (a.hexpr, b.hexpr) with
  | HLitInt x, HLitInt y ->
      Some
        (match op with
        | REq -> x = y
        | RNeq -> x <> y
        | RLt -> x < y
        | RLe -> x <= y
        | RGt -> x > y
        | RGe -> x >= y)
  | HLitBool x, HLitBool y ->
      Some (match op with REq -> x = y | RNeq -> x <> y | RLt | RLe | RGt | RGe -> false)
  | HLitEnum x, HLitEnum y ->
      Some
        (match op with
        | REq -> String.equal x y
        | RNeq -> not (String.equal x y)
        | RLt | RLe | RGt | RGe -> false)
  | _ -> None

let flatten_bool (op : binop) (h : hexpr) : hexpr list =
  let open Core_syntax in
  let rec loop acc h =
    match h.hexpr with HBin (op', a, b) when op = op' -> loop (loop acc b) a | _ -> h :: acc
  in
  List.rev (loop [] h)

let dedup_hexprs (xs : hexpr list) : hexpr list =
  let seen = Hashtbl.create ((List.length xs * 2) + 1) in
  let rec loop acc = function
    | [] -> List.rev acc
    | x :: rest ->
        let key = key_of_hexpr x in
        if Hashtbl.mem seen key then loop acc rest
        else (
          Hashtbl.add seen key ();
          loop (x :: acc) rest)
  in
  loop [] xs

let length_at_most limit xs =
  let rec loop n = function [] -> true | _ :: rest -> n > 0 && loop (n - 1) rest in
  limit >= 0 && loop limit xs

let string_set_of_keys xs = List.fold_left (fun acc key -> StringSet.add key acc) StringSet.empty xs

let keyed_hexprs (xs : hexpr list) : (string * hexpr) list =
  List.map (fun h -> (key_of_hexpr h, h)) xs

let bool_literals_have_complement (xs : hexpr list) : bool =
  let seen = Hashtbl.create 16 in
  List.exists
    (fun h ->
      match literal_key h with
      | None -> false
      | Some (key, sign) ->
          begin match Hashtbl.find_opt seen key with
          | Some prev when Bool.equal prev (not sign) -> true
          | _ ->
              Hashtbl.replace seen key sign;
              false
          end)
    xs
