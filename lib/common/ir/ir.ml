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

type product_contract = {
  program_transition_index : int;
  product_src : product_state;
  product_dst : product_state;
  assume_guard : Fo_formula.t;
  guarantee_guard : Fo_formula.t;
  requires : contract_formula list;
  ensures : contract_formula list;
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

type node = {
  semantics : node_semantics;
  trans : transition list;
  product_transitions : product_contract list;
  uid : int option;
  source_info : source_info;
  coherency_goals : contract_formula list;
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

let map_product_contract_formulas ~contract ~guard (pc : product_contract) : product_contract =
  {
    pc with
    requires = List.map (map_formula contract) pc.requires;
    ensures = List.map (map_formula contract) pc.ensures;
    assume_guard = guard pc.assume_guard;
    guarantee_guard = guard pc.guarantee_guard;
  }
