open Ast
open Ir_shared_types

let ( let* ) = Result.bind

type formula_meta = {
  origin : Formula_origin.t option;
  oid : formula_id;
  loc : loc option;
}

type contract_formula = {
  logic : ltl;
  meta : formula_meta;
}

let formula_meta_to_yojson (m : formula_meta) : Yojson.Safe.t =
  let option_to_yojson f = function None -> `Null | Some x -> f x in
  `Assoc
    [
      ("origin", option_to_yojson Formula_origin.to_yojson m.origin);
      ("oid", `Int m.oid);
      ("loc", option_to_yojson Ast.loc_to_yojson m.loc);
    ]

let formula_meta_of_yojson (json : Yojson.Safe.t) : (formula_meta, string) result =
  let option_of_yojson f = function `Null -> Ok None | x -> Result.map Option.some (f x) in
  match json with
  | `Assoc fields ->
      let find name = List.assoc_opt name fields in
      let* origin_json = Option.to_result ~none:"formula_meta: missing field 'origin'" (find "origin") in
      let* oid_json = Option.to_result ~none:"formula_meta: missing field 'oid'" (find "oid") in
      let* loc_json = Option.to_result ~none:"formula_meta: missing field 'loc'" (find "loc") in
      let* origin = option_of_yojson Formula_origin.of_yojson origin_json in
      let* loc = option_of_yojson Ast.loc_of_yojson loc_json in
      let oid =
        match oid_json with
        | `Int n -> Ok n
        | _ -> Error "formula_meta.oid: expected int"
      in
      let* oid = oid in
      Ok { origin; oid; loc }
  | _ -> Error "formula_meta: expected object"

let contract_formula_to_yojson (f : contract_formula) : Yojson.Safe.t =
  `Assoc
    [
      ("logic", Ast.ltl_to_yojson f.logic);
      ("meta", formula_meta_to_yojson f.meta);
    ]

let contract_formula_of_yojson (json : Yojson.Safe.t) : (contract_formula, string) result =
  match json with
  | `Assoc fields ->
      let find name =
        match List.assoc_opt name fields with
        | Some v -> Ok v
        | None -> Error (Printf.sprintf "contract_formula: missing field '%s'" name)
      in
      let* logic_json = find "logic" in
      let* meta_json = find "meta" in
      let* logic = Ast.ltl_of_yojson logic_json in
      let* meta = formula_meta_of_yojson meta_json in
      Ok { logic; meta }
  | _ -> Error "contract_formula: expected object"

type product_state = {
  prog_state : ident;
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

type product_step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type product_case = {
  step_class : product_step_class;
  product_dst_id : string;
  product_dst : product_state;
  guarantee_guard : Fo_formula.t;
  propagates : contract_formula list;
  ensures : contract_formula list;
  forbidden : contract_formula list;
}

type product_contract_identity = {
  program_transition_index : transition_index;
  product_src_id : string;
  product_src : product_state;
  assume_guard : Fo_formula.t;
}

type product_contract_common = {
  requires : contract_formula list;
  ensures : contract_formula list;
}

type product_contract_safe_summary = {
  safe_destination_id : string option;
  safe_product_dsts : product_state list;
  safe_propagates : contract_formula list;
  safe_ensures : contract_formula list;
}

type product_contract = {
  identity : product_contract_identity;
  common : product_contract_common;
  safe_summary : product_contract_safe_summary;
  cases : product_case list;
}

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  body : stmt list;
}

type node_semantics = Ast.node_semantics

type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  user_invariants : invariant_user list;
  state_invariants : invariant_state_rel list;
}

type transition_core = {
  src_state : ident;
  dst_state : ident;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
}

type transition_contracts = {
  requires : contract_formula list;
  ensures : contract_formula list;
}

type raw_transition = {
  core : transition_core;
  guard : Fo_formula.t;
}

type node_core = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
}

type raw_node = {
  core : node_core;
  pre_k_map : (hexpr * Temporal_support.pre_k_info) list;
  transitions : raw_transition list;
  assumes : ltl list;
  guarantees : ltl list;
}

type annotated_transition = {
  raw : raw_transition;
  contracts : transition_contracts;
}

type annotated_node = {
  raw : raw_node;
  transitions : annotated_transition list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

type verified_transition = {
  core : transition_core;
  guard : Fo_formula.t;
  pre_k_updates : stmt list;
  contracts : transition_contracts;
}

type verified_node = {
  core : node_core;
  transitions : verified_transition list;
  product_transitions : product_contract list;
  assumes : ltl list;
  guarantees : ltl list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

type proof_views = {
  raw : raw_node option;
  annotated : annotated_node option;
  verified : verified_node option;
}

type contracts_info = {
  contract_origin_map : formula_origin_entry list;
  warnings : string list;
}

type node = {
  semantics : node_semantics;
  trans : transition list;
  product_transitions : product_contract list;
  source_info : source_info;
  coherency_goals : contract_formula list;
  proof_views : proof_views;
}

type program = {
  nodes : node list;
  contracts_info : contracts_info;
}

let to_ast_transition (t : transition) : Ast.transition =
  { src = t.src; dst = t.dst; guard = t.guard; body = t.body }

let to_ast_node (n : node) : Ast.node =
  {
    semantics =
      {
        n.semantics with
        sem_trans = List.map to_ast_transition n.trans;
      };
    specification =
      {
        spec_assumes = n.source_info.assumes;
        spec_guarantees = n.source_info.guarantees;
        spec_invariants_state_rel = n.source_info.state_invariants;
      };
  }

let with_origin ?loc origin logic : contract_formula =
  { logic; meta = { origin = Some origin; oid = Provenance.fresh_id (); loc } }
let values xs = List.map (fun x -> x.logic) xs

let dedup_contract_formulas (xs : contract_formula list) : contract_formula list =
  List.sort_uniq
    (fun (a : contract_formula) (b : contract_formula) -> Int.compare a.meta.oid b.meta.oid)
    xs

let refresh_safe_summary (pc : product_contract) : product_contract =
  let safe_cases = List.filter (fun (c : product_case) -> c.step_class = Safe) pc.cases in
  let safe_product_dsts =
    match (pc.safe_summary.safe_product_dsts, safe_cases) with
    | existing, _ :: _ when existing <> [] -> existing
    | _, _ ->
        safe_cases
        |> List.map (fun (c : product_case) -> c.product_dst)
        |> List.sort_uniq Stdlib.compare
  in
  let safe_destination_id =
    match safe_cases with
    | [] -> None
    | _ :: _ -> pc.safe_summary.safe_destination_id
  in
  let safe_propagates =
    safe_cases
    |> List.concat_map (fun (c : product_case) -> c.propagates)
    |> dedup_contract_formulas
  in
  let safe_ensures =
    safe_cases
    |> List.concat_map (fun (c : product_case) -> c.ensures)
    |> dedup_contract_formulas
  in
  {
    pc with
    safe_summary = { safe_destination_id; safe_product_dsts; safe_propagates; safe_ensures };
  }

let empty_proof_views : proof_views = { raw = None; annotated = None; verified = None }
