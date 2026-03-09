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

let rec simplify_iexpr (e : iexpr) : iexpr =
  let lit_value_equal a b =
    a = b
  in
  let rec as_cmp (e : iexpr) : (bool * ident * string) option =
    match e.iexpr with
    | IPar x -> as_cmp x
    | IUn (Not, x) -> begin
        match as_cmp x with
        | Some (true, v, c) -> Some (false, v, c)
        | Some (false, v, c) -> Some (true, v, c)
        | None -> None
      end
    | IBin (Eq, a, b) -> begin
        match (a.iexpr, b.iexpr) with
        | IVar v, ILitInt i | ILitInt i, IVar v -> Some (true, v, string_of_int i)
        | IVar v, ILitBool b | ILitBool b, IVar v -> Some (true, v, string_of_bool b)
        | _ -> None
      end
    | IBin (Neq, a, b) -> begin
        match (a.iexpr, b.iexpr) with
        | IVar v, ILitInt i | ILitInt i, IVar v -> Some (false, v, string_of_int i)
        | IVar v, ILitBool b | ILitBool b, IVar v -> Some (false, v, string_of_bool b)
        | _ -> None
      end
    | _ -> None
  in
  let simplify_cmp_pair_and (a : iexpr) (b : iexpr) : iexpr option =
    match (as_cmp a, as_cmp b) with
    | Some (true, va, ca), Some (true, vb, cb) when va = vb ->
        if lit_value_equal ca cb then Some a else Some (mk_bool false)
    | Some (true, va, ca), Some (false, vb, cb)
    | Some (false, vb, cb), Some (true, va, ca) when va = vb ->
        if lit_value_equal ca cb then Some (mk_bool false) else Some a
    | Some (false, va, ca), Some (false, vb, cb) when va = vb && lit_value_equal ca cb -> Some a
    | _ -> None
  in
  let simplify_cmp_pair_or (a : iexpr) (b : iexpr) : iexpr option =
    match (as_cmp a, as_cmp b) with
    | Some (true, va, ca), Some (true, vb, cb) when va = vb && lit_value_equal ca cb -> Some a
    | Some (true, va, ca), Some (false, vb, cb) when va = vb ->
        if lit_value_equal ca cb then Some (mk_bool true)
        else
          Some
            (mk_iexpr
               (IBin
                  ( Neq,
                    mk_var vb,
                    if cb = "true" then mk_bool true
                    else if cb = "false" then mk_bool false
                    else mk_int (int_of_string cb) )))
    | Some (false, va, ca), Some (true, vb, cb) when va = vb ->
        if lit_value_equal ca cb then Some (mk_bool true)
        else Some a
    | Some (false, va, ca), Some (false, vb, cb) when va = vb && lit_value_equal ca cb -> Some a
    | _ -> None
  in
  let rec flatten_and acc (x : iexpr) =
    match x.iexpr with
    | IPar y -> flatten_and acc y
    | IBin (And, a, b) -> flatten_and (flatten_and acc a) b
    | _ -> x :: acc
  in
  let rec flatten_or acc (x : iexpr) =
    match x.iexpr with
    | IPar y -> flatten_or acc y
    | IBin (Or, a, b) -> flatten_or (flatten_or acc a) b
    | _ -> x :: acc
  in
  let rec flatten_and_atoms acc (x : iexpr) =
    match x.iexpr with
    | IPar y -> flatten_and_atoms acc y
    | IBin (And, a, b) -> flatten_and_atoms (flatten_and_atoms acc a) b
    | _ -> x :: acc
  in
  let clause_of_expr (x : iexpr) : iexpr list =
    flatten_and_atoms [] x |> List.rev
  in
  let clause_subsumes a b =
    List.for_all (fun lit -> List.exists (( = ) lit) b) a
  in
  let clause_cmp_of_expr (x : iexpr) : (bool * ident * string) list option =
    let lits = clause_of_expr x in
    List.fold_right
      (fun lit acc ->
        match (as_cmp lit, acc) with
        | Some c, Some cs -> Some (c :: cs)
        | _ -> None)
      lits (Some [])
  in
  let upsert_constraint cs v update =
    let rec loop acc = function
      | [] ->
          let eq, neqs = update (None, []) in
          List.rev ((v, eq, neqs) :: acc)
      | ((v', eq, neqs) as item) :: rest ->
          if v' = v then
            let eq', neqs' = update (eq, neqs) in
            List.rev_append acc ((v, eq', neqs') :: rest)
          else
            loop (item :: acc) rest
    in
    loop [] cs
  in
  let normalize_clause_cmp lits : (ident * string option * string list) list option =
    let rec loop cs = function
      | [] -> Some cs
      | (is_eq, v, c) :: rest ->
          let updated =
            upsert_constraint cs v (fun (eq, neqs) ->
                if is_eq then
                  match eq with
                  | Some c' when not (lit_value_equal c c') -> raise Exit
                  | Some _ -> (eq, neqs)
                  | None ->
                      if List.exists (lit_value_equal c) neqs then raise Exit else (Some c, [])
                else
                  match eq with
                  | Some c' when lit_value_equal c c' -> raise Exit
                  | Some _ -> (eq, neqs)
                  | None ->
                      if List.exists (lit_value_equal c) neqs then (eq, neqs)
                      else (eq, c :: neqs))
          in
          loop updated rest
    in
    try loop [] lits with Exit -> None
  in
  let clause_constraints_to_lits (cs : (ident * string option * string list) list) =
    cs
    |> List.concat_map (fun (v, eq, neqs) ->
           match eq with
           | Some c -> [ (true, v, c) ]
           | None -> List.rev_map (fun c -> (false, v, c)) neqs)
  in
  let clause_entails_lit (cs : (ident * string option * string list) list) (is_eq, v, c) =
    match List.find_opt (fun (v', _, _) -> v' = v) cs with
    | None -> false
    | Some (_, eq, neqs) -> begin
        match (is_eq, eq) with
        | true, Some c' -> lit_value_equal c c'
        | true, None -> false
        | false, Some c' -> not (lit_value_equal c c')
        | false, None -> List.exists (lit_value_equal c) neqs
      end
  in
  let clause_cmp_subsumes a b =
    List.for_all (clause_entails_lit a) (clause_constraints_to_lits b)
  in
  let expr_key (x : iexpr) = Support.string_of_iexpr x in
  let expr_rank (x : iexpr) =
    match x.iexpr with
    | IVar _ -> 0
    | ILitInt _ | ILitBool _ -> 2
    | _ -> 1
  in
  let normalize_rel_pair (a : iexpr) (b : iexpr) =
    let ra = expr_rank a in
    let rb = expr_rank b in
    if ra < rb then (a, b)
    else if rb < ra then (b, a)
    else if String.compare (expr_key a) (expr_key b) <= 0 then (a, b)
    else (b, a)
  in
  let rec as_rel_lit (e : iexpr) : (bool * iexpr * iexpr) option =
    match e.iexpr with
    | IPar x -> as_rel_lit x
    | IUn (Not, x) -> begin
        match x.iexpr with
        | IBin (Eq, a, b) ->
            let a, b = normalize_rel_pair a b in
            Some (false, a, b)
        | IBin (Neq, a, b) ->
            let a, b = normalize_rel_pair a b in
            Some (true, a, b)
        | _ -> None
      end
    | IBin (Eq, a, b) ->
        let a, b = normalize_rel_pair a b in
        Some (true, a, b)
    | IBin (Neq, a, b) ->
        let a, b = normalize_rel_pair a b in
        Some (false, a, b)
    | _ -> None
  in
  let rel_lit_equal (eq1, a1, b1) (eq2, a2, b2) =
    eq1 = eq2 && a1 = a2 && b1 = b2
  in
  let rel_lit_complementary (eq1, a1, b1) (eq2, a2, b2) =
    eq1 <> eq2 && a1 = a2 && b1 = b2
  in
  let clause_rel_of_expr (x : iexpr) : (bool * iexpr * iexpr) list option =
    let lits = clause_of_expr x in
    List.fold_right
      (fun lit acc ->
        match (as_rel_lit lit, acc) with
        | Some c, Some cs -> Some (c :: cs)
        | _ -> None)
      lits (Some [])
  in
  let merge_rel_clauses c1 c2 =
    let only1 = List.filter (fun lit -> not (List.exists (rel_lit_equal lit) c2)) c1 in
    let only2 = List.filter (fun lit -> not (List.exists (rel_lit_equal lit) c1)) c2 in
    match (only1, only2) with
    | [l1], [l2] when rel_lit_complementary l1 l2 ->
        Some (List.filter (fun lit -> not (rel_lit_equal lit l1)) c1)
    | _ -> None
  in
  let rebuild_rel_lit = function
    | true, a, b -> mk_iexpr (IBin (Eq, a, b))
    | false, a, b -> mk_iexpr (IBin (Neq, a, b))
  in
  let rebuild_and = function
    | [] -> mk_bool true
    | x :: xs -> List.fold_left (fun acc y -> mk_iexpr (IBin (And, acc, y))) x xs
  in
  let rec merge_rel_clause_set xs =
    let rec try_merge left = function
      | [] -> None
      | x :: rest -> begin
          match clause_rel_of_expr x with
          | None -> try_merge (x :: left) rest
          | Some cx -> begin
              let rec against_left kept = function
                | [] -> try_merge (x :: left) rest
                | y :: ys -> begin
                    match clause_rel_of_expr y with
                    | Some cy -> begin
                        match merge_rel_clauses cx cy with
                        | Some merged ->
                            let rebuilt = rebuild_and (List.map rebuild_rel_lit merged) in
                            Some (List.rev_append kept (rebuilt :: List.rev_append ys rest))
                        | None -> against_left (y :: kept) ys
                      end
                    | None -> against_left (y :: kept) ys
                  end
              in
              against_left [] left
            end
        end
    in
    match try_merge [] xs with
    | Some xs' -> merge_rel_clause_set xs'
    | None -> xs
  in
  let rebuild_lit = function
    | true, v, c ->
        let rhs =
          if c = "true" then mk_bool true
          else if c = "false" then mk_bool false
          else mk_int (int_of_string c)
        in
        mk_iexpr (IBin (Eq, mk_var v, rhs))
    | false, v, c ->
        let rhs =
          if c = "true" then mk_bool true
          else if c = "false" then mk_bool false
          else mk_int (int_of_string c)
        in
        mk_iexpr (IBin (Neq, mk_var v, rhs))
  in
  let cmp_complementary a b =
    match (as_cmp a, as_cmp b) with
    | Some (ea, va, ca), Some (eb, vb, cb) -> va = vb && lit_value_equal ca cb && ea <> eb
    | _ -> false
  in
  let is_negation a b =
    match (a.iexpr, b.iexpr) with
    | IUn (Not, x), _ when x = b -> true
    | _, IUn (Not, x) when x = a -> true
    | _ -> false
  in
  let rebuild_or = function
    | [] -> mk_bool false
    | x :: xs -> List.fold_left (fun acc y -> mk_iexpr (IBin (Or, acc, y))) x xs
  in
  let simplify_assoc ~is_and (xs : iexpr list) : iexpr =
    let rec add_one acc x =
      let rec loop kept = function
        | [] -> List.rev (x :: kept)
        | y :: ys ->
            if x = y then List.rev_append kept (y :: ys)
            else if is_negation x y then [ mk_bool (not is_and) ]
            else
              let simplified =
                if is_and then simplify_cmp_pair_and x y else simplify_cmp_pair_or x y
              in
              match simplified with
              | Some s when s.iexpr = ILitBool false && is_and -> [ mk_bool false ]
              | Some s when s.iexpr = ILitBool true && not is_and -> [ mk_bool true ]
              | Some s -> List.rev_append kept (s :: ys)
              | None -> loop (y :: kept) ys
      in
      loop [] acc
    in
    let xs =
      xs
      |> List.filter (fun x ->
             if is_and then x.iexpr <> ILitBool true else x.iexpr <> ILitBool false)
    in
    if List.exists (fun x -> x.iexpr = ILitBool (not is_and)) xs then
      mk_bool (not is_and)
    else
      let xs = List.fold_left add_one [] xs in
      let xs =
        if is_and then xs
        else
          let xs =
            xs
            |> List.filter_map (fun x ->
                   match clause_cmp_of_expr x with
                   | None -> Some x
                   | Some lits -> begin
                       match normalize_clause_cmp lits with
                       | None -> None
                       | Some cs -> Some (rebuild_and (List.map rebuild_lit (clause_constraints_to_lits cs)))
                     end)
          in
          let literal_clauses =
            xs
            |> List.filter_map (fun x ->
                   match clause_cmp_of_expr x with
                   | Some lits -> begin
                       match normalize_clause_cmp lits with
                       | Some cs -> begin
                           match clause_constraints_to_lits cs with
                           | [ lit ] -> Some lit
                           | _ -> None
                         end
                       | None -> None
                     end
                   | None -> None)
          in
          let reduce_clause x =
            match clause_cmp_of_expr x with
            | None -> x
            | Some cx -> begin
                match normalize_clause_cmp cx with
                | None -> mk_bool false
                | Some cxs ->
                    let cx = clause_constraints_to_lits cxs in
                let cx' =
                  List.fold_left
                    (fun acc lit ->
                      if List.length acc <= 1 then acc
                      else
                        match List.find_opt (fun l -> cmp_complementary (rebuild_lit l) (rebuild_lit lit)) literal_clauses with
                        | Some _ -> List.filter (fun t -> t <> lit) acc
                        | None -> acc)
                    cx cx
                in
                rebuild_and (List.map rebuild_lit cx')
              end
          in
          let xs = List.map reduce_clause xs in
          let xs = merge_rel_clause_set xs in
          List.filter
            (fun x ->
              let cx =
                match clause_cmp_of_expr x with
                | Some lits -> Option.bind (normalize_clause_cmp lits) (fun cs -> Some cs)
                | None -> None
              in
              not
                (List.exists
                   (fun y ->
                     x <> y
                     &&
                     match (clause_cmp_of_expr y, cx) with
                     | Some cy, Some cx -> begin
                         match normalize_clause_cmp cy with
                         | Some cy -> clause_cmp_subsumes cy cx
                         | None -> false
                       end
                     | _ ->
                         let cy = clause_of_expr y in
                         let cx = clause_of_expr x in
                         clause_subsumes cy cx)
                   xs))
            xs
      in
      if List.exists (fun x -> x.iexpr = ILitBool (not is_and)) xs then mk_bool (not is_and)
      else if is_and && xs = [] then mk_bool true
      else if (not is_and) && xs = [] then mk_bool false
      else if is_and then rebuild_and (List.rev xs)
      else rebuild_or (List.rev xs)
  in
  match e.iexpr with
  | ILitInt _ | ILitBool _ | IVar _ -> e
  | IUn (Not, x) -> begin
      match simplify_iexpr x with
      | { iexpr = ILitBool true; _ } -> mk_bool false
      | { iexpr = ILitBool false; _ } -> mk_bool true
      | { iexpr = IUn (Not, y); _ } -> y
      | y -> mk_iexpr (IUn (Not, y))
    end
  | IUn (op, x) -> mk_iexpr (IUn (op, simplify_iexpr x))
  | IBin (And, a, b) ->
      let xs = flatten_and [] e |> List.rev |> List.map simplify_iexpr in
      simplify_assoc ~is_and:true xs
  | IBin (Or, a, b) ->
      let xs = flatten_or [] e |> List.rev |> List.map simplify_iexpr in
      simplify_assoc ~is_and:false xs
  | IBin (op, a, b) ->
      let a = simplify_iexpr a in
      let b = simplify_iexpr b in
      mk_iexpr (IBin (op, a, b))
  | IPar x -> mk_iexpr (IPar (simplify_iexpr x))

let valuations_to_iexpr (atom_names : string list) (vals_list : (string * bool) list list) : iexpr =
  match vals_list with
  | [] -> mk_bool false
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      terms_to_iexpr implicants
