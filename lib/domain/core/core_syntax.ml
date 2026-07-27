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

(** {1 Core syntax}

    This module defines the shared syntax core used by the frontend,
    middle-end, and backends. It separates two expression layers:
    - [expr]: executable expressions.
    - [hexpr]: historical/logical expressions. *)

(** Identifiers (variables, states, symbols). *)
type ident = string 
  [@@deriving yojson]

(** Source types supported by the core. *)
type ty = TInt | TBool | TReal | TCustom of string 
  [@@deriving yojson]

(** Finite algebraic type declaration. *)
type enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]

(** Binary operators. *)
type binop = Add | Sub | Mul | Div | And | Or
  [@@deriving yojson]

(** Unary operators. *)
type unop = Neg | Not
  [@@deriving yojson]

(** Comparison operators. *)
type relop = REq | RNeq | RLt | RLe | RGt | RGe 
  [@@deriving yojson]

(** Imperative/executable expression.

    Used in transition guards and imperative statements. *)
type expr = { expr : expr_desc; loc : Loc.loc option }

and expr_desc =
  | ELitInt of int
  | ELitBool of bool
  | ELitEnum of ident
  | EVar of ident
  | EFunCall of ident * expr list
  | EBin of binop * expr * expr
  | ECmp of relop * expr * expr
  | EUn of unop * expr
[@@deriving yojson]

(** Static capability of a logical expression. *)
type historical = Historical
type history_free = HistoryFree

(** Logical expression indexed by its history capability. *)
type 'phase hexpr = {
  hexpr : 'phase hexpr_desc;
  loc : Loc.loc option;
}

and _ hexpr_desc =
  | HLitInt : int -> 'phase hexpr_desc
  | HLitBool : bool -> 'phase hexpr_desc
  | HLitEnum : ident -> 'phase hexpr_desc
  | HVar : ident -> 'phase hexpr_desc
  | HPreK : ident * int -> historical hexpr_desc
  (** Explicit core-level predicate application. The Kairos source frontend
      does not emit this as a fallback for undeclared local predicates. *)
  | HPred : ident * 'phase hexpr list -> 'phase hexpr_desc
  | HFunCall : ident * 'phase hexpr list -> 'phase hexpr_desc
  | HBin :
      binop * 'phase hexpr * 'phase hexpr ->
      'phase hexpr_desc
  | HCmp :
      relop * 'phase hexpr * 'phase hexpr ->
      'phase hexpr_desc
  | HUn : unop * 'phase hexpr -> 'phase hexpr_desc

let rec hexpr_json : type phase. phase hexpr -> Yojson.Safe.t =
 fun formula ->
  let desc =
    match formula.hexpr with
    | HLitInt value -> `List [ `String "HLitInt"; `Int value ]
    | HLitBool value -> `List [ `String "HLitBool"; `Bool value ]
    | HLitEnum name -> `List [ `String "HLitEnum"; `String name ]
    | HVar name -> `List [ `String "HVar"; `String name ]
    | HPreK (name, depth) ->
        `List [ `String "HPreK"; `List [ `String name; `Int depth ] ]
    | HPred (name, args) ->
        `List
          [
            `String "HPred";
            `List
              [
                `String name;
                `List (List.map hexpr_json args);
              ];
          ]
    | HFunCall (name, args) ->
        `List
          [
            `String "HFunCall";
            `List
              [
                `String name;
                `List (List.map hexpr_json args);
              ];
          ]
    | HBin (op, lhs, rhs) ->
        `List
          [
            `String "HBin";
            `List
              [
                binop_to_yojson op;
                hexpr_json lhs;
                hexpr_json rhs;
              ];
          ]
    | HCmp (op, lhs, rhs) ->
        `List
          [
            `String "HCmp";
            `List
              [
                relop_to_yojson op;
                hexpr_json lhs;
                hexpr_json rhs;
              ];
          ]
    | HUn (op, inner) ->
        `List
          [
            `String "HUn";
            `List [ unop_to_yojson op; hexpr_json inner ];
          ]
  in
  `Assoc
    [
      ("hexpr", desc);
      ( "loc",
        match formula.loc with
        | None -> `Null
        | Some source_loc -> Loc.loc_to_yojson source_loc );
    ]

let hexpr_json_of_yojson (json : Yojson.Safe.t) :
    (historical hexpr, string) result =
  let ( let* ) = Result.bind in
  let rec decode json =
    let* desc_json, loc_json =
      match json with
      | `Assoc fields -> (
          match (List.assoc_opt "hexpr" fields, List.assoc_opt "loc" fields) with
          | Some desc, Some loc -> Ok (desc, loc)
          | _ -> Error "hexpr: missing hexpr or loc field")
      | _ -> Error "hexpr: expected object"
    in
    let* loc =
      match loc_json with
      | `Null -> Ok None
      | value -> Result.map Option.some (Loc.loc_of_yojson value)
    in
    let* hexpr =
      match desc_json with
      | `List [ `String "HLitInt"; `Int value ] -> Ok (HLitInt value)
      | `List [ `String "HLitBool"; `Bool value ] -> Ok (HLitBool value)
      | `List [ `String "HLitEnum"; `String name ] -> Ok (HLitEnum name)
      | `List [ `String "HVar"; `String name ] -> Ok (HVar name)
      | `List
          [ `String "HPreK"; `List [ `String name; `Int depth ] ] ->
          Ok (HPreK (name, depth))
      | `List
          [ (`String "HPred" as tag); `List [ `String name; `List args ] ]
      | `List
          [ (`String "HFunCall" as tag); `List [ `String name; `List args ] ]
        ->
          let* args = decode_list args in
          if tag = `String "HPred" then Ok (HPred (name, args))
          else Ok (HFunCall (name, args))
      | `List
          [ `String "HBin"; `List [ op_json; lhs_json; rhs_json ] ] ->
          let* op = binop_of_yojson op_json in
          let* lhs = decode lhs_json in
          let* rhs = decode rhs_json in
          Ok (HBin (op, lhs, rhs))
      | `List
          [ `String "HCmp"; `List [ op_json; lhs_json; rhs_json ] ] ->
          let* op = relop_of_yojson op_json in
          let* lhs = decode lhs_json in
          let* rhs = decode rhs_json in
          Ok (HCmp (op, lhs, rhs))
      | `List [ `String "HUn"; `List [ op_json; inner_json ] ] ->
          let* op = unop_of_yojson op_json in
          let* inner = decode inner_json in
          Ok (HUn (op, inner))
      | _ -> Error "hexpr: invalid constructor"
    in
    Ok { hexpr; loc }
  and decode_list = function
    | [] -> Ok []
    | item :: rest ->
        let* item = decode item in
        let* rest = decode_list rest in
        Ok (item :: rest)
  in
  decode json

let hexpr_to_yojson = hexpr_json
let historical_hexpr_of_yojson = hexpr_json_of_yojson

let rec history_free_of_historical
    (formula : historical hexpr) : history_free hexpr option =
  let rebuild hexpr = { hexpr; loc = formula.loc } in
  match formula.hexpr with
  | HLitInt value -> Some (rebuild (HLitInt value))
  | HLitBool value -> Some (rebuild (HLitBool value))
  | HLitEnum name -> Some (rebuild (HLitEnum name))
  | HVar name -> Some (rebuild (HVar name))
  | HPreK _ -> None
  | HPred (name, args) ->
      Option.map
        (fun args -> rebuild (HPred (name, args)))
        (List.fold_right
           (fun arg acc ->
             match (history_free_of_historical arg, acc) with
             | Some arg, Some args -> Some (arg :: args)
             | _ -> None)
           args (Some []))
  | HFunCall (name, args) ->
      Option.map
        (fun args -> rebuild (HFunCall (name, args)))
        (List.fold_right
           (fun arg acc ->
             match (history_free_of_historical arg, acc) with
             | Some arg, Some args -> Some (arg :: args)
             | _ -> None)
           args (Some []))
  | HBin (op, lhs, rhs) -> (
      match
        (history_free_of_historical lhs, history_free_of_historical rhs)
      with
      | Some lhs, Some rhs -> Some (rebuild (HBin (op, lhs, rhs)))
      | _ -> None)
  | HCmp (op, lhs, rhs) -> (
      match
        (history_free_of_historical lhs, history_free_of_historical rhs)
      with
      | Some lhs, Some rhs -> Some (rebuild (HCmp (op, lhs, rhs)))
      | _ -> None)
  | HUn (op, inner) ->
      Option.map
        (fun inner -> rebuild (HUn (op, inner)))
        (history_free_of_historical inner)

let rec historical_of_history_free
    (formula : history_free hexpr) : historical hexpr =
  let rebuild hexpr = { hexpr; loc = formula.loc } in
  match formula.hexpr with
  | HLitInt value -> rebuild (HLitInt value)
  | HLitBool value -> rebuild (HLitBool value)
  | HLitEnum name -> rebuild (HLitEnum name)
  | HVar name -> rebuild (HVar name)
  | HPred (name, args) ->
      rebuild (HPred (name, List.map historical_of_history_free args))
  | HFunCall (name, args) ->
      rebuild (HFunCall (name, List.map historical_of_history_free args))
  | HBin (op, lhs, rhs) ->
      rebuild
        (HBin
           ( op,
             historical_of_history_free lhs,
             historical_of_history_free rhs ))
  | HCmp (op, lhs, rhs) ->
      rebuild
        (HCmp
           ( op,
             historical_of_history_free lhs,
             historical_of_history_free rhs ))
  | HUn (op, inner) ->
      rebuild (HUn (op, historical_of_history_free inner))

let history_free_hexpr_of_yojson json =
  let ( let* ) = Result.bind in
  let* formula = historical_hexpr_of_yojson json in
  match history_free_of_historical formula with
  | Some formula -> Ok formula
  | None -> Error "historical operator in history-free formula"

let history_free_hexpr_list_to_yojson formulas =
  `List (List.map hexpr_json formulas)

let history_free_hexpr_list_of_yojson = function
  | `List formulas ->
      let ( let* ) = Result.bind in
      let rec decode = function
        | [] -> Ok []
        | formula :: rest ->
            let* formula = history_free_hexpr_of_yojson formula in
            let* rest = decode rest in
            Ok (formula :: rest)
      in
      decode formulas
  | _ -> Error "expected history-free formula list"

(** LTL formulas (safety-oriented fragment used by the tool). *)
type ltl_atom =
  (historical hexpr
    [@to_yojson hexpr_to_yojson]
    [@of_yojson historical_hexpr_of_yojson])
  * relop
  * (historical hexpr
      [@to_yojson hexpr_to_yojson]
      [@of_yojson historical_hexpr_of_yojson])
[@@deriving yojson]

(** LTL formulas (safety-oriented fragment used by the tool). *)
type ltl =
  | LTrue
  | LFalse
  | LAtom of ltl_atom
  | LNot of ltl
  | LAnd of ltl * ltl
  | LOr of ltl * ltl
  | LImp of ltl * ltl
  | LX of ltl
  | LG of ltl
  | LW of ltl * ltl
[@@deriving yojson]

(** LTL formula tagged with a stable identifier and optional source location *)
type ltl_o = { value : ltl; oid : int; loc : Loc.loc option }
[@@deriving yojson]

(** Typed variable declaration. *)
type vdecl = { vname : ident; vty : ty } [@@deriving yojson]

(** Pure first-order function declaration.

    Functions are translated as Why3 functions. The [result] identifier is
    reserved for postconditions and denotes the returned value. *)
type pure_function_decl = {
  function_name : ident;
  function_params : vdecl list;
  function_return : ty;
  function_requires : history_free hexpr list
      [@to_yojson history_free_hexpr_list_to_yojson]
      [@of_yojson history_free_hexpr_list_of_yojson];
  function_ensures : history_free hexpr list
      [@to_yojson history_free_hexpr_list_to_yojson]
      [@of_yojson history_free_hexpr_list_of_yojson];
  function_body : expr;
}
[@@deriving yojson]

(** Internal imperative statement language used by the verification model and IR.

    Source-language adapters may define their own ASTs and lower into these
    statements at the domain boundary. *)
type stmt = { stmt : stmt_desc; loc : Loc.loc option }

and stmt_desc =
  | SAssign of ident * expr
  | SAssert of history_free hexpr
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * history_free hexpr list * expr option * stmt list
  | SMatch of expr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * expr list * ident list

let rec stmt_to_yojson statement =
  let statements_to_yojson statements =
    `List (List.map stmt_to_yojson statements)
  in
  let desc =
    match statement.stmt with
    | SAssign (name, value) ->
        `List
          [
            `String "SAssign";
            `List [ `String name; expr_to_yojson value ];
          ]
    | SAssert formula ->
        `List [ `String "SAssert"; hexpr_json formula ]
    | SIf (condition, then_branch, else_branch) ->
        `List
          [
            `String "SIf";
            `List
              [
                expr_to_yojson condition;
                statements_to_yojson then_branch;
                statements_to_yojson else_branch;
              ];
          ]
    | SWhile (condition, invariants, variant, body) ->
        `List
          [
            `String "SWhile";
            `List
              [
                expr_to_yojson condition;
                `List (List.map hexpr_json invariants);
                (match variant with
                | None -> `Null
                | Some expression -> expr_to_yojson expression);
                statements_to_yojson body;
              ];
          ]
    | SMatch (scrutinee, branches, default) ->
        let branch_to_yojson (constructor, body) =
          `List [ `String constructor; statements_to_yojson body ]
        in
        `List
          [
            `String "SMatch";
            `List
              [
                expr_to_yojson scrutinee;
                `List (List.map branch_to_yojson branches);
                statements_to_yojson default;
              ];
          ]
    | SSkip -> `String "SSkip"
    | SCall (name, arguments, results) ->
        `List
          [
            `String "SCall";
            `List
              [
                `String name;
                `List (List.map expr_to_yojson arguments);
                `List (List.map (fun result -> `String result) results);
              ];
          ]
  in
  `Assoc
    [
      ("stmt", desc);
      ( "loc",
        match statement.loc with
        | None -> `Null
        | Some source_loc -> Loc.loc_to_yojson source_loc );
    ]

let rec decode_json_list decode_item = function
  | [] -> Ok []
  | item :: rest ->
      let ( let* ) = Result.bind in
      let* item = decode_item item in
      let* rest = decode_json_list decode_item rest in
      Ok (item :: rest)

let stmt_of_yojson json =
  let ( let* ) = Result.bind in
  let rec decode statement_json =
    let* desc_json, loc_json =
      match statement_json with
      | `Assoc fields -> (
          match (List.assoc_opt "stmt" fields, List.assoc_opt "loc" fields) with
          | Some desc, Some loc -> Ok (desc, loc)
          | _ -> Error "stmt: missing stmt or loc field")
      | _ -> Error "stmt: expected object"
    in
    let* loc =
      match loc_json with
      | `Null -> Ok None
      | value -> Result.map Option.some (Loc.loc_of_yojson value)
    in
    let* stmt = decode_desc desc_json in
    Ok { stmt; loc }
  and decode_statements = function
    | `List statements -> decode_json_list decode statements
    | _ -> Error "stmt: expected statement list"
  and decode_exprs = function
    | `List expressions -> decode_json_list expr_of_yojson expressions
    | _ -> Error "stmt: expected expression list"
  and decode_names = function
    | `List names ->
        decode_json_list
          (function
            | `String name -> Ok name
            | _ -> Error "stmt: expected identifier")
          names
    | _ -> Error "stmt: expected identifier list"
  and decode_formula json =
    history_free_hexpr_of_yojson json
  and decode_formulas = function
    | `List formulas -> decode_json_list decode_formula formulas
    | _ -> Error "stmt: expected formula list"
  and decode_branches = function
    | `List branches ->
        decode_json_list
          (function
            | `List [ `String constructor; body_json ] ->
                let* body = decode_statements body_json in
                Ok (constructor, body)
            | _ -> Error "stmt: invalid match branch")
          branches
    | _ -> Error "stmt: expected match branches"
  and decode_desc = function
    | `List
        [ `String "SAssign"; `List [ `String name; expression_json ] ] ->
        let* expression = expr_of_yojson expression_json in
        Ok (SAssign (name, expression))
    | `List [ `String "SAssert"; formula_json ] ->
        let* formula = decode_formula formula_json in
        Ok (SAssert formula)
    | `List
        [
          `String "SIf";
          `List [ condition_json; then_json; else_json ];
        ] ->
        let* condition = expr_of_yojson condition_json in
        let* then_branch = decode_statements then_json in
        let* else_branch = decode_statements else_json in
        Ok (SIf (condition, then_branch, else_branch))
    | `List
        [
          `String "SWhile";
          `List [ condition_json; invariants_json; variant_json; body_json ];
        ] ->
        let* condition = expr_of_yojson condition_json in
        let* invariants = decode_formulas invariants_json in
        let* variant =
          match variant_json with
          | `Null -> Ok None
          | value -> Result.map Option.some (expr_of_yojson value)
        in
        let* body = decode_statements body_json in
        Ok (SWhile (condition, invariants, variant, body))
    | `List
        [
          `String "SMatch";
          `List [ scrutinee_json; branches_json; default_json ];
        ] ->
        let* scrutinee = expr_of_yojson scrutinee_json in
        let* branches = decode_branches branches_json in
        let* default = decode_statements default_json in
        Ok (SMatch (scrutinee, branches, default))
    | `String "SSkip" -> Ok SSkip
    | `List
        [
          `String "SCall";
          `List [ `String name; arguments_json; results_json ];
        ] ->
        let* arguments = decode_exprs arguments_json in
        let* results = decode_names results_json in
        Ok (SCall (name, arguments, results))
    | _ -> Error "stmt: invalid constructor"
  in
  decode json
