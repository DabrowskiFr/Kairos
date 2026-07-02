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

module K = Core_fo_simplifier_keys
module StringSet = K.StringSet

type hexpr = Core_syntax.hexpr

let htrue = K.htrue
let hfalse = K.hfalse
let is_htrue = K.is_htrue
let is_hfalse = K.is_hfalse
let key_of_hexpr = K.key_of_hexpr
let rel_lit_of_hexpr = K.rel_lit_of_hexpr
let literal_key = K.literal_key
let are_complements = K.are_complements
let flatten_bool = K.flatten_bool
let dedup_hexprs = K.dedup_hexprs
let length_at_most = K.length_at_most
let string_set_of_keys = K.string_set_of_keys
let keyed_hexprs = K.keyed_hexprs
let bool_literals_have_complement = K.bool_literals_have_complement
let simple_absorption_disjunct_limit = 32
let simple_absorption_term_limit = 8
let pairwise_resolution_disjunct_limit = 0
let absorption_disjunct_limit = 32
let common_dnf_tautology_disjunct_limit = 16

let and_has_contradiction (xs : hexpr list) : bool =
  let open K in
  let equalities = Hashtbl.create 16 in
  let disequalities = Hashtbl.create 16 in
  bool_literals_have_complement xs
  || List.exists
       (fun h ->
         match rel_lit_of_hexpr h with
         | None -> false
         | Some { subject; op = Core_syntax.REq; value } ->
             begin match Hashtbl.find_opt equalities subject with
             | Some prev when not (String.equal prev value) -> true
             | _ ->
                 Hashtbl.replace equalities subject value;
                 Hashtbl.mem disequalities (subject, value)
             end
         | Some { subject; op = Core_syntax.RNeq; value } ->
             Hashtbl.replace disequalities (subject, value) ();
             begin match Hashtbl.find_opt equalities subject with
             | Some prev -> String.equal prev value
             | None -> false
             end
         | Some _ -> false)
       xs

let prune_redundant_disequalities (xs : hexpr list) : hexpr list =
  let open K in
  let equalities = Hashtbl.create 16 in
  List.iter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = Core_syntax.REq; value } -> Hashtbl.replace equalities subject value
      | _ -> ())
    xs;
  List.filter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = Core_syntax.RNeq; value } ->
          begin match Hashtbl.find_opt equalities subject with
          | Some known -> String.equal known value
          | None -> true
          end
      | _ -> true)
    xs

let or_has_tautology (xs : hexpr list) : bool =
  let open K in
  let seen_eq = Hashtbl.create 16 in
  let seen_neq = Hashtbl.create 16 in
  bool_literals_have_complement xs
  || List.exists
       (fun h ->
         match rel_lit_of_hexpr h with
         | Some { subject; op = Core_syntax.REq; value } ->
             let key = (subject, value) in
             if Hashtbl.mem seen_neq key then true
             else (
               Hashtbl.replace seen_eq key ();
               false)
         | Some { subject; op = Core_syntax.RNeq; value } ->
             let key = (subject, value) in
             if Hashtbl.mem seen_eq key then true
             else (
               Hashtbl.replace seen_neq key ();
               false)
         | _ -> false)
       xs

let rec rebuild_and_syntax (xs : hexpr list) : hexpr =
  let xs = List.concat_map (flatten_bool Core_syntax.And) xs in
  if List.exists is_hfalse xs || and_has_contradiction xs then hfalse
  else
    let xs =
      xs
      |> List.filter (fun h -> not (is_htrue h))
      |> dedup_hexprs |> prune_redundant_disequalities |> dedup_hexprs
    in
    match xs with
    | [] -> htrue
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hand x rest

and simplify_disjunct_against_simple (simple : hexpr) (h : hexpr) : hexpr option =
  let conjuncts = flatten_bool Core_syntax.And h in
  match conjuncts with
  | [ _ ] -> Some h
  | _ ->
      if List.exists (fun c -> key_of_hexpr c = key_of_hexpr simple) conjuncts then None
      else
        let pruned = List.filter (fun c -> not (are_complements simple c)) conjuncts in
        Some (rebuild_and_syntax pruned)

and resolve_or_pair (a : hexpr) (b : hexpr) : hexpr option =
  let ca = flatten_bool Core_syntax.And a |> dedup_hexprs |> keyed_hexprs in
  let cb = flatten_bool Core_syntax.And b |> dedup_hexprs |> keyed_hexprs in
  let keys_b = string_set_of_keys (List.map fst cb) in
  let common = ca |> List.filter (fun (key, _h) -> StringSet.mem key keys_b) in
  let common_keys = string_set_of_keys (List.map fst common) in
  let diff_a =
    ca |> List.filter (fun (key, _h) -> not (StringSet.mem key common_keys)) |> List.map snd
  in
  let diff_b =
    cb |> List.filter (fun (key, _h) -> not (StringSet.mem key common_keys)) |> List.map snd
  in
  match (diff_a, diff_b) with
  | [ da ], [ db ] when are_complements da db -> Some (rebuild_and_syntax (List.map snd common))
  | _ -> None

and resolve_or_once (xs : hexpr list) : hexpr list * bool =
  match xs with
  | [] -> ([], false)
  | x :: rest ->
      begin match
        List.find_map (fun y -> Option.map (fun r -> (y, r)) (resolve_or_pair x y)) rest
      with
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

and conjunction_key_set (h : hexpr) : StringSet.t =
  flatten_bool Core_syntax.And h
  |> List.fold_left (fun acc h -> StringSet.add (key_of_hexpr h) acc) StringSet.empty

and remove_absorbed_disjuncts (xs : hexpr list) : hexpr list =
  let keyed = List.map (fun h -> (h, key_of_hexpr h, conjunction_key_set h)) xs in
  keyed
  |> List.filter (fun (_h, key, keys) ->
      not
        (List.exists
           (fun (_other, other_key, other_keys) ->
             (not (String.equal key other_key)) && StringSet.subset other_keys keys)
           keyed))
  |> List.map (fun (h, _key, _keys) -> h)

type cube_lit = { cube_key : string; cube_sign : bool; cube_expr : hexpr }

let cube_of_conjunction (h : hexpr) : cube_lit list option =
  let add_lit acc atom =
    match literal_key atom with
    | None -> None
    | Some (key, sign) ->
        begin match List.find_opt (fun lit -> String.equal lit.cube_key key) acc with
        | Some prev when Bool.equal prev.cube_sign sign -> Some acc
        | Some _ -> None
        | None -> Some ({ cube_key = key; cube_sign = sign; cube_expr = atom } :: acc)
        end
  in
  let atoms = flatten_bool Core_syntax.And h in
  if List.exists is_hfalse atoms then Some []
  else
    atoms
    |> List.filter (fun atom -> not (is_htrue atom))
    |> List.fold_left (fun acc atom -> Option.bind acc (fun acc -> add_lit acc atom)) (Some [])
    |> Option.map List.rev

let cube_contains_literal lit cube =
  List.exists
    (fun other ->
      String.equal lit.cube_key other.cube_key && Bool.equal lit.cube_sign other.cube_sign)
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
           (fun c -> String.equal lit.cube_key c.cube_key && Bool.equal lit.cube_sign c.cube_sign)
           common))

let rec assignments = function
  | [] -> [ [] ]
  | key :: rest ->
      let rest = assignments rest in
      List.map (fun a -> (key, false) :: a) rest @ List.map (fun a -> (key, true) :: a) rest

let cube_satisfied assignment cube =
  List.for_all
    (fun lit ->
      match List.assoc_opt lit.cube_key assignment with
      | Some value -> Bool.equal value lit.cube_sign
      | None -> false)
    cube

let dnf_tautology cubes =
  let vars =
    cubes |> List.concat_map (List.map (fun lit -> lit.cube_key)) |> List.sort_uniq String.compare
  in
  List.length vars <= 12
  && List.for_all
       (fun assignment -> List.exists (cube_satisfied assignment) cubes)
       (assignments vars)

let simplify_common_dnf_tautology (xs : hexpr list) : hexpr option =
  let cubes =
    List.fold_right
      (fun cube acc -> Option.bind cube (fun cube -> Option.map (fun acc -> cube :: acc) acc))
      (List.map cube_of_conjunction xs) (Some [])
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
  let xs = List.concat_map (flatten_bool Core_syntax.Or) xs in
  if List.exists is_htrue xs || or_has_tautology xs then htrue
  else
    let xs = xs |> List.filter (fun h -> not (is_hfalse h)) |> dedup_hexprs in
    let simple_terms =
      xs
      |> List.filter (fun h ->
          match flatten_bool Core_syntax.And h with [ _ ] -> true | _ -> false)
    in
    let xs =
      if
        length_at_most simple_absorption_disjunct_limit xs
        && length_at_most simple_absorption_term_limit simple_terms
      then
        List.fold_left
          (fun acc simple ->
            acc |> List.filter_map (simplify_disjunct_against_simple simple) |> dedup_hexprs)
          xs simple_terms
      else xs
    in
    let xs =
      if length_at_most pairwise_resolution_disjunct_limit xs then resolve_or_all xs else xs
    in
    let xs =
      if length_at_most absorption_disjunct_limit xs then remove_absorbed_disjuncts xs else xs
    in
    let xs = dedup_hexprs xs in
    let xs =
      if length_at_most common_dnf_tautology_disjunct_limit xs then
        match simplify_common_dnf_tautology xs with Some simplified -> [ simplified ] | None -> xs
      else xs
    in
    match xs with
    | [] -> hfalse
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hor x rest
