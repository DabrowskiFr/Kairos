module Abs = Ir

(** Convert an optional imperative guard to a first-order formula. *)
let guard_fo (g : Ast.iexpr option) : Fo_formula.t =
  match g with
  | None -> Fo_formula.FTrue
  | Some e ->
      Fo_specs.iexpr_to_fo_with_atoms [] e |> Fo_simplifier.simplify_fo

(** Build a raw transition from a finalized abstract transition.
    requires/ensures are intentionally omitted — they belong to pass 4. *)
let raw_transition_of_abs (t : Abs.transition) : Ir.raw_transition =
  {
    Ir.src_state             = t.src;
    dst_state                       = t.dst;
    guard                           = guard_fo t.guard;
    guard_iexpr                     = t.guard;
    body_stmts                      = t.body;
  }

(** Build a [Ir.raw_node] from a finalized abstract node.

    The node carries:
    - the executable transition body exported by the middle-end
    - the source assume/guarantee contracts kept in [source_info]

    No requires/ensures are copied — those are the responsibility of pass 4. *)
let build_raw_node (node : Abs.node) : Ir.raw_node =
  let contract_formulas =
    let transition_formulas =
      node.trans
      |> List.concat_map (fun (t : Abs.transition) -> Abs.values (t.requires @ t.ensures))
    in
    let product_formulas =
      node.product_transitions
      |> List.concat_map (fun (pc : Abs.product_contract) ->
             Abs.values (pc.requires @ pc.ensures @ pc.forbidden))
    in
    transition_formulas @ product_formulas @ Abs.values node.coherency_goals
  in
  let pre_k_map =
    Collect.build_pre_k_infos_from_parts ~inputs:node.semantics.sem_inputs
      ~locals:node.semantics.sem_locals ~outputs:node.semantics.sem_outputs
      ~ltl:(node.source_info.assumes @ node.source_info.guarantees @ contract_formulas)
      ~invariants_user:node.source_info.user_invariants
      ~invariants_state_rel:node.source_info.state_invariants
  in
  let transitions = List.map raw_transition_of_abs node.trans in
  {
    Ir.node_name      = node.semantics.sem_nname;
    inputs                   = node.semantics.sem_inputs;
    outputs                  = node.semantics.sem_outputs;
    locals                   = node.semantics.sem_locals;
    control_states           = node.semantics.sem_states;
    init_state               = node.semantics.sem_init_state;
    instances                = node.semantics.sem_instances;
    pre_k_map;
    transitions;
    assumes                  = node.source_info.assumes;
    guarantees               = node.source_info.guarantees;
  }

let apply_node (node : Abs.node) : Abs.node =
  { node with proof_views = { node.proof_views with raw = Some (build_raw_node node) } }

let apply_program (program : Abs.node list) : Abs.node list = List.map apply_node program
