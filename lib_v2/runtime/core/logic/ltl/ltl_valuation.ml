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

open Ast
open Ast_builders

let valuation_label (vals : (string * bool) list) : string =
  vals |> List.map (fun (n, b) -> n ^ "=" ^ if b then "1" else "0") |> String.concat ","

type term = (string * bool option) list

let lookup_val (vals : (string * bool) list) (name : string) : bool =
  match List.assoc_opt name vals with Some b -> b | None -> false

let term_of_vals (atom_names : string list) (vals : (string * bool) list) : term =
  List.map (fun name -> (name, Some (lookup_val vals name))) atom_names

let can_merge_terms (t1 : term) (t2 : term) : bool =
  let diff = ref 0 in
  let rec loop = function
    | [], [] -> !diff = 1
    | (_, v1) :: r1, (_, v2) :: r2 -> begin
        match (v1, v2) with
        | Some b1, Some b2 when b1 = b2 -> loop (r1, r2)
        | Some _, Some _ ->
            incr diff;
            !diff <= 1 && loop (r1, r2)
        | None, None -> loop (r1, r2)
        | None, Some _ | Some _, None -> false
      end
    | _ -> false
  in
  loop (t1, t2)

let merge_terms (t1 : term) (t2 : term) : term =
  List.map2
    (fun (n1, v1) (_n2, v2) ->
      let v =
        match (v1, v2) with
        | Some b1, Some b2 when b1 = b2 -> Some b1
        | Some _, Some _ -> None
        | None, None -> None
        | None, Some b | Some b, None -> Some b
      in
      (n1, v))
    t1 t2

let uniq_terms (terms : term list) : term list =
  let rec loop acc = function
    | [] -> List.rev acc
    | t :: rest -> if List.exists (( = ) t) acc then loop acc rest else loop (t :: acc) rest
  in
  loop [] terms

let prime_implicants (terms : term list) : term list =
  let rec loop terms primes =
    let terms = uniq_terms terms in
    let n = List.length terms in
    let used = Array.make n false in
    let merged = ref [] in
    for i = 0 to n - 1 do
      for j = i + 1 to n - 1 do
        let ti = List.nth terms i in
        let tj = List.nth terms j in
        if can_merge_terms ti tj then (
          used.(i) <- true;
          used.(j) <- true;
          merged := merge_terms ti tj :: !merged)
      done
    done;
    let new_primes =
      List.fold_left
        (fun acc (i, t) -> if used.(i) then acc else t :: acc)
        primes
        (List.mapi (fun i t -> (i, t)) terms)
    in
    if !merged = [] then uniq_terms new_primes else loop !merged new_primes
  in
  loop terms []

let term_covers (term : term) (vals : (string * bool) list) : bool =
  List.for_all
    (fun (name, v) -> match v with None -> true | Some b -> lookup_val vals name = b)
    term

let choose_implicants (atom_names : string list) (vals_list : (string * bool) list list) : term list
    =
  if vals_list = [] then []
  else
    let minterms = List.map (term_of_vals atom_names) vals_list in
    let primes = prime_implicants minterms in
    let remaining = ref vals_list in
    let chosen = ref [] in
    let cover_count term =
      List.fold_left (fun acc vals -> if term_covers term vals then acc + 1 else acc) 0 !remaining
    in
    let rec loop () =
      let unique_cover =
        List.find_map
          (fun vals ->
            let covering = List.filter (fun t -> term_covers t vals) primes in
            match covering with [ t ] -> Some t | _ -> None)
          !remaining
      in
      begin match unique_cover with
      | Some t ->
          if not (List.exists (( = ) t) !chosen) then chosen := t :: !chosen;
          remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
          if !remaining <> [] then loop ()
      | None ->
          if !remaining <> [] then (
            let t =
              List.fold_left
                (fun best cand -> if cover_count cand > cover_count best then cand else best)
                (List.hd primes) primes
            in
            if not (List.exists (( = ) t) !chosen) then chosen := t :: !chosen;
            remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
            if !remaining <> [] then loop ())
      end
    in
    loop ();
    uniq_terms !chosen

let term_to_string (term : term) : string =
  let parts =
    List.filter_map
      (fun (name, v) ->
        match v with None -> None | Some true -> Some name | Some false -> Some ("not " ^ name))
      term
  in
  match parts with [] -> "true" | _ -> String.concat " && " parts

let valuations_to_formula (atom_names : string list) (vals_list : (string * bool) list list) :
    string =
  match vals_list with
  | [] -> "false"
  | _ -> (
      let implicants = choose_implicants atom_names vals_list in
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) implicants then "true"
      else
        let parts = List.map term_to_string implicants in
        match parts with [] -> "false" | [ p ] -> p | _ -> String.concat " || " parts)

let term_to_iexpr (term : term) : iexpr =
  let parts =
    List.filter_map
      (fun (name, v) ->
        match v with
        | None -> None
        | Some true -> Some (mk_var name)
        | Some false -> Some (mk_iexpr (IUn (Not, mk_var name))))
      term
  in
  match parts with
  | [] -> mk_bool true
  | [ p ] -> p
  | p :: rest -> List.fold_left (fun acc x -> mk_iexpr (IBin (And, acc, x))) p rest

let terms_to_iexpr (terms : term list) : iexpr =
  match terms with
  | [] -> mk_bool false
  | _ -> (
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) terms then mk_bool true
      else
        let parts = List.map term_to_iexpr terms in
        match parts with
        | [] -> mk_bool false
        | [ p ] -> p
        | p :: rest -> List.fold_left (fun acc x -> mk_iexpr (IBin (Or, acc, x))) p rest)

let valuations_to_iexpr (atom_names : string list) (vals_list : (string * bool) list list) : iexpr =
  match vals_list with
  | [] -> mk_bool false
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      terms_to_iexpr implicants
