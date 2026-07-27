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

open Core_syntax
open Core_syntax_builders

let ( let* ) = Result.bind

type atom_map = (ltl_atom * ident) list

type prepared_formula = {
  formula : ltl;
  atoms : atom_map;
}

type prepared_node = {
  node_name : ident;
  guarantee : prepared_formula;
  assumption : prepared_formula option;
}

let rec collect_atoms_ltl (formula : ltl) (acc : ltl_atom list) :
    ltl_atom list =
  match formula with
  | LTrue | LFalse -> acc
  | LAtom (left, relation, right) ->
      let atom = (left, relation, right) in
      if List.exists (( = ) atom) acc then acc else atom :: acc
  | LNot inner | LX inner | LG inner -> collect_atoms_ltl inner acc
  | LAnd (left, right)
  | LOr (left, right)
  | LImp (left, right)
  | LW (left, right) ->
      collect_atoms_ltl right (collect_atoms_ltl left acc)

let sanitize_ident (value : string) : string =
  let buffer = Buffer.create (String.length value) in
  let add_underscore () =
    if
      Buffer.length buffer = 0
      || Buffer.nth buffer (Buffer.length buffer - 1) <> '_'
    then Buffer.add_char buffer '_'
  in
  String.iter
    (function
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' as character ->
          Buffer.add_char buffer character
      | _ -> add_underscore ())
    value;
  let sanitized = Buffer.contents buffer |> String.lowercase_ascii in
  let sanitized =
    let length = String.length sanitized in
    if length > 0 && sanitized.[length - 1] = '_' then
      String.sub sanitized 0 (length - 1)
    else sanitized
  in
  let sanitized = if sanitized = "" then "atom" else sanitized in
  match sanitized.[0] with
  | '0' .. '9' -> "atom_" ^ sanitized
  | _ -> sanitized

let make_atom_names (atom_exprs : (ltl_atom * expr) list) : string list =
  let used = Hashtbl.create 16 in
  let fresh base =
    let rec loop suffix =
      let name =
        if suffix = 0 then base else base ^ "_" ^ string_of_int suffix
      in
      if Hashtbl.mem used name then loop (suffix + 1)
      else (
        Hashtbl.add used name ();
        name)
    in
    loop 0
  in
  List.map
    (fun (_atom, expression) ->
      "atom_" ^ sanitize_ident (Pretty.string_of_expr expression) |> fresh)
    atom_exprs

let infer_expr_type ~(var_types : (ident * ty) list) (expression : expr) :
    ty option =
  let rec infer = function
    | ELitBool _ -> Some TBool
    | ELitInt _ -> Some TInt
    | ELitEnum constructor | EVar constructor ->
        List.assoc_opt constructor var_types
    | EFunCall _ -> None
    | EUn (Not, _) -> Some TBool
    | EUn (Neg, _) -> Some TInt
    | EBin (And, _, _) | EBin (Or, _, _) -> Some TBool
    | EBin (Add, _, _) | EBin (Sub, _, _) | EBin (Mul, _, _)
    | EBin (Div, _, _) ->
        Some TInt
    | ECmp _ -> Some TBool
  in
  infer expression.expr

let mk_bool_eq (left : expr) (right : expr) : expr =
  mk_expr
    (EBin
       ( Or,
         mk_expr (EBin (And, left, right)),
         mk_expr
           (EBin
              ( And,
                mk_expr (EUn (Not, left)),
                mk_expr (EUn (Not, right)) )) ))

let mk_bool_neq (left : expr) (right : expr) : expr =
  mk_expr
    (EBin
       ( Or,
         mk_expr (EBin (And, left, mk_expr (EUn (Not, right)))),
         mk_expr (EBin (And, mk_expr (EUn (Not, left)), right)) ))

let atom_to_expr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(temporal_layout : Pre_k_layout.pre_k_info list)
    ((left, relation, right) : ltl_atom) : expr option =
  match
    ( Pre_k_lowering.hexpr_to_expr ~inputs ~var_types ~temporal_layout left,
      Pre_k_lowering.hexpr_to_expr ~inputs ~var_types ~temporal_layout right )
  with
  | Some left_expr, Some right_expr -> begin
      match
        ( infer_expr_type ~var_types left_expr,
          infer_expr_type ~var_types right_expr,
          relation )
      with
      | Some TBool, Some TBool, REq ->
          Some (mk_bool_eq left_expr right_expr)
      | Some TBool, Some TBool, RNeq ->
          Some (mk_bool_neq left_expr right_expr)
      | _ -> Some (mk_expr (ECmp (relation, left_expr, right_expr)))
    end
  | _ -> None

let collect_atoms (node : Verification_model.node_model)
    ~(formulas : ltl list) : (atom_map, string) result =
  let constructor_types =
    node.type_decls
    |> List.concat_map (fun (declaration : enum_decl) ->
           List.map
             (fun constructor ->
               (constructor, TCustom declaration.enum_name))
             declaration.enum_constructors)
  in
  let var_types =
    constructor_types
    @ List.map
        (fun declaration -> (declaration.vname, declaration.vty))
        (node.inputs @ node.locals @ node.ghosts @ node.outputs)
  in
  let temporal_layout = Pre_k_layout.build_pre_k_infos node in
  let inputs = List.map (fun declaration -> declaration.vname) node.inputs in
  let atoms =
    List.fold_left
      (fun acc formula -> collect_atoms_ltl formula acc)
      [] formulas
    |> List.sort_uniq compare
  in
  let converted, rejected =
    List.fold_left
      (fun (converted, rejected) atom ->
        match atom_to_expr ~inputs ~var_types ~temporal_layout atom with
        | Some expression -> ((atom, expression) :: converted, rejected)
        | None -> (converted, atom :: rejected))
      ([], []) atoms
  in
  match rejected with
  | _ :: _ ->
      let rendered =
        List.rev rejected
        |> List.map (fun (left, relation, right) ->
               Printf.sprintf "%s %s %s" (Pretty.string_of_hexpr left)
                 (Pretty.string_of_relop relation)
                 (Pretty.string_of_hexpr right))
        |> String.concat "; "
      in
      Error
        (Printf.sprintf
           "Cannot prepare automata for node %s: temporal atoms are not \
            translatable: %s"
           node.node_name rendered)
  | [] ->
      let converted = List.rev converted in
      let names = make_atom_names converted in
      Ok
        (List.map2
           (fun (atom, _expression) name -> (atom, name))
           converted names)

let validate_weak_until_positivity ~(context : string) (formula : ltl) :
    (unit, string) result =
  let rec validate ~(positive : bool) current =
    match current with
    | LTrue | LFalse | LAtom _ -> Ok ()
    | LNot inner -> validate ~positive:(not positive) inner
    | LAnd (left, right) | LOr (left, right) ->
        let* () = validate ~positive left in
        validate ~positive right
    | LImp (left, right) ->
        let* () = validate ~positive:(not positive) left in
        validate ~positive right
    | LX inner | LG inner -> validate ~positive inner
    | LW (left, right) ->
        if not positive then
          Error
            (Printf.sprintf
               "Unsupported LTL formula in %s: weak-until W appears in \
                negative position: %s"
               context (Pretty.string_of_ltl formula))
        else
          let* () = validate ~positive left in
          validate ~positive right
  in
  validate ~positive:true formula

let rec simplify_temporal_idempotence (formula : ltl) : ltl =
  match formula with
  | LTrue | LFalse | LAtom _ -> formula
  | LNot inner -> LNot (simplify_temporal_idempotence inner)
  | LX inner -> LX (simplify_temporal_idempotence inner)
  | LG inner -> begin
      match simplify_temporal_idempotence inner with
      | LG nested -> LG nested
      | simplified -> LG simplified
    end
  | LW (left, right) ->
      LW
        ( simplify_temporal_idempotence left,
          simplify_temporal_idempotence right )
  | LAnd (left, right) ->
      LAnd
        ( simplify_temporal_idempotence left,
          simplify_temporal_idempotence right )
  | LOr (left, right) ->
      LOr
        ( simplify_temporal_idempotence left,
          simplify_temporal_idempotence right )
  | LImp (left, right) ->
      LImp
        ( simplify_temporal_idempotence left,
          simplify_temporal_idempotence right )

let conjunction (formulas : ltl list) : ltl =
  let rec build = function
    | [] -> LTrue
    | [ formula ] -> formula
    | formula :: rest -> LAnd (formula, build rest)
  in
  build (List.rev formulas)

let prepare_formula ~(node : Verification_model.node_model)
    ~(role : string) (formulas : ltl list) :
    (prepared_formula, string) result =
  let rec validate index = function
    | [] -> Ok ()
    | formula :: rest ->
        let* () =
          validate_weak_until_positivity
            ~context:
              (Printf.sprintf "%s #%d of node %s" role index
                 node.node_name)
            formula
        in
        validate (index + 1) rest
  in
  let* () = validate 1 formulas in
  let* atoms = collect_atoms node ~formulas in
  Ok
    {
      formula = conjunction formulas |> simplify_temporal_idempotence;
      atoms;
    }

let prepare_node (node : Verification_model.node_model) :
    (prepared_node, string) result =
  let* guarantee =
    prepare_formula ~node ~role:"guarantee" node.guarantees
  in
  let* assumption =
    match node.assumes with
    | [] -> Ok None
    | assumes ->
        let* prepared =
          prepare_formula ~node ~role:"require" assumes
        in
        Ok (Some prepared)
  in
  Ok { node_name = node.node_name; guarantee; assumption }

let prepare_program (program : Verification_model.program_model) :
    (prepared_node list, string) result =
  let rec prepare acc = function
    | [] -> Ok (List.rev acc)
    | node :: rest ->
        let* prepared = prepare_node node in
        prepare (prepared :: acc) rest
  in
  prepare [] program
