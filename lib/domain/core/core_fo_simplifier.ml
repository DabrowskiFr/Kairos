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

open Core_syntax

let mk_h desc = Core_syntax_builders.mk_hexpr desc
let htrue = Core_syntax_builders.mk_hbool true
let hfalse = Core_syntax_builders.mk_hbool false

let is_htrue = function { hexpr = HLitBool true; _ } -> true | _ -> false
let is_hfalse = function { hexpr = HLitBool false; _ } -> true | _ -> false

let rec key_of_hexpr (h : hexpr) : string =
  match h.hexpr with
  | HLitInt n -> "i:" ^ string_of_int n
  | HLitBool b -> "b:" ^ string_of_bool b
  | HLitEnum c -> "e:" ^ c
  | HVar v -> "v:" ^ v
  | HPreK (v, k) -> "p:" ^ string_of_int k ^ ":" ^ v
  | HPred (id, hs) -> "pred:" ^ id ^ "(" ^ String.concat "," (List.map key_of_hexpr hs) ^ ")"
  | HFunCall (id, hs) -> "fun:" ^ id ^ "(" ^ String.concat "," (List.map key_of_hexpr hs) ^ ")"
  | HUn (op, inner) ->
      let op_s = match op with Neg -> "neg" | Not -> "not" in
      op_s ^ "(" ^ key_of_hexpr inner ^ ")"
  | HBin (op, a, b) ->
      let op_s =
        match op with
        | Add -> "+"
        | Sub -> "-"
        | Mul -> "*"
        | Div -> "/"
        | And -> "and"
        | Or -> "or"
      in
      op_s ^ "(" ^ key_of_hexpr a ^ "," ^ key_of_hexpr b ^ ")"
  | HCmp (op, a, b) ->
      let op_s =
        match op with
        | REq -> "="
        | RNeq -> "<>"
        | RLt -> "<"
        | RLe -> "<="
        | RGt -> ">"
        | RGe -> ">="
      in
      op_s ^ "(" ^ key_of_hexpr a ^ "," ^ key_of_hexpr b ^ ")"

let const_key_of_hexpr = function
  | { hexpr = HLitInt n; _ } -> Some ("i:" ^ string_of_int n)
  | { hexpr = HLitBool b; _ } -> Some ("b:" ^ string_of_bool b)
  | { hexpr = HLitEnum c; _ } -> Some ("e:" ^ c)
  | _ -> None

let subject_key_of_hexpr = function
  | { hexpr = HVar v; _ } -> Some ("v:" ^ v)
  | { hexpr = HPreK (v, k); _ } -> Some ("p:" ^ string_of_int k ^ ":" ^ v)
  | _ -> None

type rel_lit = { subject : string; op : relop; value : string }

let rel_lit_of_hexpr (h : hexpr) : rel_lit option =
  match h.hexpr with
  | HCmp ((REq | RNeq as op), a, b) -> begin
      match (subject_key_of_hexpr a, const_key_of_hexpr b) with
      | Some subject, Some value -> Some { subject; op; value }
      | _ -> begin
          match (subject_key_of_hexpr b, const_key_of_hexpr a) with
          | Some subject, Some value -> Some { subject; op; value }
          | _ -> None
        end
    end
  | _ -> None

let rec literal_key (h : hexpr) : (string * bool) option =
  match rel_lit_of_hexpr h with
  | Some { subject; op = REq; value } -> Some ("rel:" ^ subject ^ ":" ^ value, true)
  | Some { subject; op = RNeq; value } -> Some ("rel:" ^ subject ^ ":" ^ value, false)
  | Some _ -> None
  | None -> begin
      match h.hexpr with
      | HUn (Not, inner) -> Option.map (fun (key, sign) -> (key, not sign)) (literal_key inner)
      | HVar _ | HPred _ | HFunCall _ -> Some ("bool:" ^ key_of_hexpr h, true)
      | _ -> None
    end

let are_complements a b =
  match (literal_key a, literal_key b) with
  | Some (ka, sa), Some (kb, sb) -> String.equal ka kb && Bool.equal sa (not sb)
  | _ -> false

let negate_relop = function
  | REq -> RNeq
  | RNeq -> REq
  | RLt -> RGe
  | RLe -> RGt
  | RGt -> RLe
  | RGe -> RLt

let eval_const_rel (op : relop) (a : hexpr) (b : hexpr) : bool option =
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
      Some
        (match op with
        | REq -> x = y
        | RNeq -> x <> y
        | RLt | RLe | RGt | RGe -> false)
  | HLitEnum x, HLitEnum y ->
      Some
        (match op with
        | REq -> String.equal x y
        | RNeq -> not (String.equal x y)
        | RLt | RLe | RGt | RGe -> false)
  | _ -> None

let rec flatten_bool (op : binop) (h : hexpr) : hexpr list =
  match h.hexpr with
  | HBin (op', a, b) when op = op' -> flatten_bool op a @ flatten_bool op b
  | _ -> [ h ]

let dedup_hexprs (xs : hexpr list) : hexpr list =
  let seen = Hashtbl.create (List.length xs * 2 + 1) in
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

let bool_literals_have_complement (xs : hexpr list) : bool =
  let seen = Hashtbl.create 16 in
  List.exists
    (fun h ->
      match literal_key h with
      | None -> false
      | Some (key, sign) -> begin
          match Hashtbl.find_opt seen key with
          | Some prev when Bool.equal prev (not sign) -> true
          | _ ->
              Hashtbl.replace seen key sign;
              false
        end)
    xs

let and_has_contradiction (xs : hexpr list) : bool =
  let equalities = Hashtbl.create 16 in
  let disequalities = Hashtbl.create 16 in
  bool_literals_have_complement xs
  ||
  List.exists
    (fun h ->
      match rel_lit_of_hexpr h with
      | None -> false
      | Some { subject; op = REq; value } -> begin
          match Hashtbl.find_opt equalities subject with
          | Some prev when not (String.equal prev value) -> true
          | _ ->
              Hashtbl.replace equalities subject value;
              Hashtbl.mem disequalities (subject, value)
        end
      | Some { subject; op = RNeq; value } ->
          Hashtbl.replace disequalities (subject, value) ();
          begin
            match Hashtbl.find_opt equalities subject with
            | Some prev -> String.equal prev value
            | None -> false
          end
      | Some _ -> false)
    xs

let prune_redundant_disequalities (xs : hexpr list) : hexpr list =
  let equalities = Hashtbl.create 16 in
  List.iter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = REq; value } -> Hashtbl.replace equalities subject value
      | _ -> ())
    xs;
  List.filter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = RNeq; value } -> begin
          match Hashtbl.find_opt equalities subject with
          | Some known -> String.equal known value
          | None -> true
        end
      | _ -> true)
    xs

let or_has_tautology (xs : hexpr list) : bool =
  let seen_eq = Hashtbl.create 16 in
  let seen_neq = Hashtbl.create 16 in
  bool_literals_have_complement xs
  ||
  List.exists
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = REq; value } ->
          let key = (subject, value) in
          if Hashtbl.mem seen_neq key then true
          else (
            Hashtbl.replace seen_eq key ();
            false)
      | Some { subject; op = RNeq; value } ->
          let key = (subject, value) in
          if Hashtbl.mem seen_eq key then true
          else (
            Hashtbl.replace seen_neq key ();
            false)
      | _ -> false)
    xs

let rec rebuild_and_syntax (xs : hexpr list) : hexpr =
  let xs = List.concat_map (flatten_bool And) xs in
  if List.exists is_hfalse xs || and_has_contradiction xs then hfalse
  else
    let xs =
      xs |> List.filter (fun h -> not (is_htrue h)) |> dedup_hexprs
      |> prune_redundant_disequalities |> dedup_hexprs
    in
    match xs with
    | [] -> htrue
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hand x rest

and simplify_disjunct_against_simple (simple : hexpr) (h : hexpr) : hexpr option =
  let conjuncts = flatten_bool And h in
  match conjuncts with
  | [ _ ] -> Some h
  | _ ->
      if List.exists (fun c -> key_of_hexpr c = key_of_hexpr simple) conjuncts then None
      else
        let pruned = List.filter (fun c -> not (are_complements simple c)) conjuncts in
        Some (rebuild_and_syntax pruned)

and resolve_or_pair (a : hexpr) (b : hexpr) : hexpr option =
  let ca = flatten_bool And a |> dedup_hexprs in
  let cb = flatten_bool And b |> dedup_hexprs in
  let common =
    ca
    |> List.filter (fun h ->
           List.exists (fun other -> String.equal (key_of_hexpr h) (key_of_hexpr other)) cb)
  in
  let diff_a =
    ca
    |> List.filter (fun h ->
           not (List.exists (fun c -> String.equal (key_of_hexpr h) (key_of_hexpr c)) common))
  in
  let diff_b =
    cb
    |> List.filter (fun h ->
           not (List.exists (fun c -> String.equal (key_of_hexpr h) (key_of_hexpr c)) common))
  in
  match (diff_a, diff_b) with
  | [ da ], [ db ] when are_complements da db -> Some (rebuild_and_syntax common)
  | _ -> None

and resolve_or_once (xs : hexpr list) : hexpr list * bool =
  match xs with
  | [] -> ([], false)
  | x :: rest -> begin
      match List.find_map (fun y -> Option.map (fun r -> (y, r)) (resolve_or_pair x y)) rest with
      | Some (y, resolved) ->
          let rest = List.filter (fun z -> key_of_hexpr z <> key_of_hexpr y) rest in
          (resolved :: rest, true)
      | None ->
          let rest, changed = resolve_or_once rest in
          (x :: rest, changed)
    end

and resolve_or_all xs =
  let xs, changed = resolve_or_once xs in
  if changed then resolve_or_all (dedup_hexprs xs) else xs

and conjunction_keys (h : hexpr) : string list =
  flatten_bool And h |> List.map key_of_hexpr |> List.sort_uniq String.compare

and keys_subset a b = List.for_all (fun x -> List.mem x b) a

and remove_absorbed_disjuncts (xs : hexpr list) : hexpr list =
  let keyed = List.map (fun h -> (h, conjunction_keys h)) xs in
  keyed
  |> List.filter (fun (h, keys) ->
         not
           (List.exists
              (fun (other, other_keys) ->
                key_of_hexpr h <> key_of_hexpr other && keys_subset other_keys keys)
              keyed))
  |> List.map fst

type cube_lit = {
  cube_key : string;
  cube_sign : bool;
  cube_expr : hexpr;
}

let cube_of_conjunction (h : hexpr) : cube_lit list option =
  let add_lit acc atom =
    match literal_key atom with
    | None -> None
    | Some (key, sign) -> begin
        match List.find_opt (fun lit -> String.equal lit.cube_key key) acc with
        | Some prev when Bool.equal prev.cube_sign sign -> Some acc
        | Some _ -> None
        | None -> Some ({ cube_key = key; cube_sign = sign; cube_expr = atom } :: acc)
      end
  in
  let atoms = flatten_bool And h in
  if List.exists is_hfalse atoms then Some []
  else
    atoms
    |> List.filter (fun atom -> not (is_htrue atom))
    |> List.fold_left
         (fun acc atom -> Option.bind acc (fun acc -> add_lit acc atom))
         (Some [])
    |> Option.map List.rev

let cube_contains_literal lit cube =
  List.exists
    (fun other ->
      String.equal lit.cube_key other.cube_key
      && Bool.equal lit.cube_sign other.cube_sign)
    cube

let common_cube_literals cubes =
  match cubes with
  | [] -> []
  | first :: rest ->
      first
      |> List.filter (fun lit -> List.for_all (cube_contains_literal lit) rest)
      |> List.sort_uniq (fun a b -> compare (a.cube_key, a.cube_sign) (b.cube_key, b.cube_sign))

let remove_cube_literals common cube =
  cube
  |> List.filter (fun lit ->
         not
           (List.exists
              (fun c ->
                String.equal lit.cube_key c.cube_key
                && Bool.equal lit.cube_sign c.cube_sign)
              common))

let rec assignments = function
  | [] -> [ [] ]
  | key :: rest ->
      let rest = assignments rest in
      List.map (fun a -> (key, false) :: a) rest
      @ List.map (fun a -> (key, true) :: a) rest

let cube_satisfied assignment cube =
  List.for_all
    (fun lit ->
      match List.assoc_opt lit.cube_key assignment with
      | Some value -> Bool.equal value lit.cube_sign
      | None -> false)
    cube

let dnf_tautology cubes =
  let vars =
    cubes
    |> List.concat_map (List.map (fun lit -> lit.cube_key))
    |> List.sort_uniq String.compare
  in
  List.length vars <= 12
  && List.for_all
       (fun assignment -> List.exists (cube_satisfied assignment) cubes)
       (assignments vars)

let simplify_common_dnf_tautology (xs : hexpr list) : hexpr option =
  let cubes =
    List.fold_right
      (fun cube acc ->
        Option.bind cube (fun cube -> Option.map (fun acc -> cube :: acc) acc))
      (List.map cube_of_conjunction xs)
      (Some [])
  in
  match cubes with
  | None -> None
  | Some cubes ->
      let common = common_cube_literals cubes in
      let residuals = List.map (remove_cube_literals common) cubes in
      if dnf_tautology residuals then
        Some (rebuild_and_syntax (List.map (fun lit -> lit.cube_expr) common))
      else None

let rec rebuild_or_syntax (xs : hexpr list) : hexpr =
  let xs = List.concat_map (flatten_bool Or) xs in
  if List.exists is_htrue xs || or_has_tautology xs then htrue
  else
    let xs = xs |> List.filter (fun h -> not (is_hfalse h)) |> dedup_hexprs in
    let simple_terms =
      xs |> List.filter (fun h -> match flatten_bool And h with [ _ ] -> true | _ -> false)
    in
    let xs =
      List.fold_left
        (fun acc simple ->
          acc |> List.filter_map (simplify_disjunct_against_simple simple) |> dedup_hexprs)
        xs simple_terms
      |> resolve_or_all
      |> remove_absorbed_disjuncts
      |> dedup_hexprs
    in
    let xs =
      match simplify_common_dnf_tautology xs with
      | Some simplified -> [ simplified ]
      | None -> xs
    in
    match xs with
    | [] -> hfalse
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hor x rest

let rec simplify (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  match f.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ | HFunCall _ -> f
  | HUn (Neg, inner) -> mk_h (HUn (Neg, simplify inner))
  | HUn (Not, inner) -> begin
      match (simplify inner).hexpr with
      | HLitBool b -> Core_syntax_builders.mk_hbool (not b)
      | HUn (Not, nested) -> nested
      | HCmp (op, a, b) -> simplify (mk_h (HCmp (negate_relop op, a, b)))
      | HBin (And, a, b) ->
          rebuild_or_syntax
            [ simplify (Core_syntax_builders.mk_hnot a);
              simplify (Core_syntax_builders.mk_hnot b) ]
      | HBin (Or, a, b) ->
          rebuild_and_syntax
            [ simplify (Core_syntax_builders.mk_hnot a);
              simplify (Core_syntax_builders.mk_hnot b) ]
      | simplified -> mk_h (HUn (Not, { f with hexpr = simplified }))
    end
  | HBin (And, a, b) -> rebuild_and_syntax [ simplify a; simplify b ]
  | HBin (Or, a, b) -> rebuild_or_syntax [ simplify a; simplify b ]
  | HBin (op, a, b) -> mk_h (HBin (op, simplify a, simplify b))
  | HCmp (op, a, b) ->
      let a = simplify a in
      let b = simplify b in
      begin
        match eval_const_rel op a b with
        | Some value -> Core_syntax_builders.mk_hbool value
        | None when a = b ->
            Core_syntax_builders.mk_hbool
              (match op with REq | RLe | RGe -> true | RNeq | RLt | RGt -> false)
        | None -> begin
            match (op, a.hexpr, b.hexpr) with
            | REq, _, HLitBool true -> a
            | REq, HLitBool true, _ -> b
            | RNeq, _, HLitBool true -> simplify (Core_syntax_builders.mk_hnot a)
            | RNeq, HLitBool true, _ -> simplify (Core_syntax_builders.mk_hnot b)
            | REq, _, HLitBool false -> simplify (Core_syntax_builders.mk_hnot a)
            | REq, HLitBool false, _ -> simplify (Core_syntax_builders.mk_hnot b)
            | RNeq, _, HLitBool false -> a
            | RNeq, HLitBool false, _ -> b
            | _ -> mk_h (HCmp (op, a, b))
          end
      end
