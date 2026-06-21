open Core_syntax
open Core_syntax_builders

type bool_lit = { name : ident; value : bool }

type rel_lit = { op : relop; lhs : string; rhs : string }

let simplify_fo (f : hexpr) : hexpr = Core_fo_simplifier.simplify f

let is_hfalse (f : hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool false -> true | _ -> false

let flatten_bool (op : binop) (f : hexpr) : hexpr list =
  let rec loop acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> loop (loop acc b) a
    | _ -> h :: acc
  in
  List.rev (loop [] (simplify_fo f))

let bool_lit_of_hexpr (h : hexpr) : bool_lit option =
  match h.hexpr with
  | HVar name -> Some { name; value = true }
  | HUn (Not, { hexpr = HVar name; _ }) -> Some { name; value = false }
  | HCmp (REq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ })
  | HCmp (REq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }) ->
      Some { name; value }
  | HCmp (RNeq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ })
  | HCmp (RNeq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }) ->
      Some { name; value = not value }
  | HUn
      ( Not,
        { hexpr = HCmp (REq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ }); _ }
      )
  | HUn
      ( Not,
        { hexpr = HCmp (REq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }); _ }
      ) ->
      Some { name; value = not value }
  | _ -> None

let flip_relop = function
  | REq -> REq
  | RNeq -> RNeq
  | RLt -> RGt
  | RLe -> RGe
  | RGt -> RLt
  | RGe -> RLe

let negate_relop = function
  | REq -> RNeq
  | RNeq -> REq
  | RLt -> RGe
  | RLe -> RGt
  | RGt -> RLe
  | RGe -> RLt

let rec additive_terms (h : hexpr) : hexpr list =
  match (simplify_fo h).hexpr with
  | HBin (Add, a, b) -> additive_terms a @ additive_terms b
  | _ -> [ h ]

let rec multiplicative_terms (h : hexpr) : hexpr list =
  match (simplify_fo h).hexpr with
  | HBin (Mul, a, b) -> multiplicative_terms a @ multiplicative_terms b
  | _ -> [ h ]

let rec term_key (h : hexpr) : string =
  match (simplify_fo h).hexpr with
  | HBin (Add, _, _) ->
      additive_terms h
      |> List.map term_key
      |> List.sort String.compare
      |> String.concat "+"
      |> Printf.sprintf "add(%s)"
  | HBin (Mul, _, _) ->
      multiplicative_terms h
      |> List.map term_key
      |> List.sort String.compare
      |> String.concat "*"
      |> Printf.sprintf "mul(%s)"
  | _ -> Core_fo_simplifier.key_of_hexpr (simplify_fo h)

let canonical_rel_lit op a b : rel_lit =
  let lhs = term_key a in
  let rhs = term_key b in
  match op with
  | REq | RNeq ->
      if String.compare lhs rhs <= 0 then { op; lhs; rhs }
      else { op; lhs = rhs; rhs = lhs }
  | RLt | RLe | RGt | RGe ->
      if String.compare lhs rhs <= 0 then { op; lhs; rhs }
      else { op = flip_relop op; lhs = rhs; rhs = lhs }

let rel_lit_of_hexpr (h : hexpr) : rel_lit option =
  match h.hexpr with
  | HCmp (op, a, b) -> Some (canonical_rel_lit op a b)
  | HUn (Not, { hexpr = HCmp (op, a, b); _ }) ->
      Some (canonical_rel_lit (negate_relop op) a b)
  | _ -> None

let same_rel_subject (a : rel_lit) (b : rel_lit) : bool =
  String.equal a.lhs b.lhs && String.equal a.rhs b.rhs

let exact_complement (a : hexpr) (b : hexpr) : bool =
  match (a.hexpr, b.hexpr) with
  | HUn (Not, inner), _ when inner = b -> true
  | _, HUn (Not, inner) when inner = a -> true
  | _ -> (
      match (rel_lit_of_hexpr a, rel_lit_of_hexpr b) with
      | Some ra, Some rb ->
          same_rel_subject ra rb && ra.op = negate_relop rb.op
      | _ -> false)

let and_has_contradiction (xs : hexpr list) : bool =
  let lits = Hashtbl.create 16 in
  let lit_contradiction =
    xs
    |> List.exists (fun h ->
           match bool_lit_of_hexpr h with
           | None -> false
           | Some lit -> (
               match Hashtbl.find_opt lits lit.name with
               | Some previous when previous <> lit.value -> true
               | _ ->
                   Hashtbl.replace lits lit.name lit.value;
                   false))
  in
  lit_contradiction
  || List.exists
       (fun a -> List.exists (fun b -> exact_complement a b) xs)
       xs

let contradictory_context context candidate : bool =
  let xs = context @ flatten_bool And candidate in
  is_hfalse (List.fold_left mk_hand (mk_hbool true) xs)
  || and_has_contradiction xs

let conjunction_obviously_false (f : hexpr) : bool =
  let f = simplify_fo f in
  if is_hfalse f then true
  else
    let conjuncts = flatten_bool And f in
    and_has_contradiction conjuncts
    || List.exists
         (fun h ->
           match h.hexpr with
           | HBin (Or, _, _) ->
               flatten_bool Or h
               |> List.for_all
                    (contradictory_context
                       (List.filter (( != ) h) conjuncts))
           | _ -> false)
         conjuncts
