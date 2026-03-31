open Ast

type contract_formula = {
  value : ltl;
  origin : Formula_origin.t option;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

type product_state = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

type product_step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type product_case = {
  step_class : product_step_class;
  product_dst : product_state;
  guarantee_guard : Fo_formula.t;
  propagates : contract_formula list;
  ensures : contract_formula list;
  forbidden : contract_formula list;
}

type product_contract = {
  program_transition_index : int;
  product_src : product_state;
  assume_guard : Fo_formula.t;
  requires : contract_formula list;
  ensures : contract_formula list;
  safe_product_dst : product_state option;
  safe_guarantee_guard : Fo_formula.t option;
  safe_propagates : contract_formula list;
  safe_ensures : contract_formula list;
  cases : product_case list;
}

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : contract_formula list;
  ensures : contract_formula list;
  body : stmt list;
  uid : int option;
  warnings : string list;
}

type node_semantics = Ast.node_semantics

type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  user_invariants : invariant_user list;
  state_invariants : invariant_state_rel list;
}

type raw_transition = {
  src_state : ident;
  dst_state : ident;
  guard : Fo_formula.t;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
}

type raw_node = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
  pre_k_map : (hexpr * Temporal_support.pre_k_info) list;
  transitions : raw_transition list;
  assumes : ltl list;
  guarantees : ltl list;
}

type annotated_transition = {
  raw : raw_transition;
  requires : contract_formula list;
  ensures : contract_formula list;
}

type annotated_node = {
  raw : raw_node;
  transitions : annotated_transition list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

type verified_transition = {
  src_state : ident;
  dst_state : ident;
  guard : Fo_formula.t;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
  pre_k_updates : stmt list;
  requires : contract_formula list;
  ensures : contract_formula list;
}

type verified_node = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
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
  contract_origin_map : (int * Formula_origin.t option) list;
  warnings : string list;
}

type node = {
  semantics : node_semantics;
  trans : transition list;
  product_transitions : product_contract list;
  uid : int option;
  source_info : source_info;
  coherency_goals : contract_formula list;
  proof_views : proof_views;
}

type program = {
  nodes : node list;
  contracts_info : contracts_info;
}

let to_ast_contract_formula (f : contract_formula) : Ast.ltl_o =
  { value = f.value; oid = f.oid; loc = f.loc }

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

let map_transitions (f : transition list -> transition list) (n : node) : node =
  { n with trans = f n.trans }

let with_origin ?loc origin value : contract_formula =
  { value; origin = Some origin; oid = Provenance.fresh_id (); loc }

let map_formula f (x : contract_formula) : contract_formula = { x with value = f x.value }
let values xs = List.map (fun x -> x.value) xs

let dedup_contract_formulas (xs : contract_formula list) : contract_formula list =
  List.sort_uniq
    (fun (a : contract_formula) (b : contract_formula) -> Int.compare a.oid b.oid)
    xs

let refresh_safe_summary (pc : product_contract) : product_contract =
  let safe_cases = List.filter (fun (c : product_case) -> c.step_class = Safe) pc.cases in
  let safe_product_dst =
    match (pc.safe_product_dst, safe_cases) with
    | Some dst, _ :: _ -> Some dst
    | None, first_safe :: _ -> Some first_safe.product_dst
    | _ -> None
  in
  let safe_guarantee_guard =
    match (pc.safe_guarantee_guard, safe_cases) with
    | Some guard, _ :: _ -> Some guard
    | None, first_safe :: rest ->
        Some
          (List.fold_left
             (fun acc (c : product_case) -> Fo_formula.FOr (acc, c.guarantee_guard))
             first_safe.guarantee_guard rest)
    | _ -> None
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
  { pc with safe_product_dst; safe_guarantee_guard; safe_propagates; safe_ensures }

let map_product_contract_formulas ~contract ~guard (pc : product_contract) : product_contract =
  {
    pc with
    requires = List.map (map_formula contract) pc.requires;
    ensures = List.map (map_formula contract) pc.ensures;
    safe_propagates = List.map (map_formula contract) pc.safe_propagates;
    safe_ensures = List.map (map_formula contract) pc.safe_ensures;
    assume_guard = guard pc.assume_guard;
    safe_guarantee_guard = Option.map guard pc.safe_guarantee_guard;
    cases =
      List.map
        (fun (c : product_case) ->
          {
            c with
            guarantee_guard = guard c.guarantee_guard;
            propagates = List.map (map_formula contract) c.propagates;
            ensures = List.map (map_formula contract) c.ensures;
            forbidden = List.map (map_formula contract) c.forbidden;
          })
        pc.cases;
  }

let empty_proof_views : proof_views = { raw = None; annotated = None; verified = None }
