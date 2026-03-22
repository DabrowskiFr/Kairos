module Abs = Normalized_program

(** Convert an optional imperative guard to a first-order formula. *)
let guard_fo (g : Ast.iexpr option) : Ast.ltl =
  match g with
  | None -> Ast.LTrue
  | Some e ->
      Fo_specs.iexpr_to_fo_with_atoms [] e |> Fo_simplifier.simplify_fo

(** Build a raw transition from a finalized abstract transition.
    requires/ensures are intentionally omitted — they belong to pass 4. *)
let raw_transition_of_abs (t : Abs.transition) : Proof_obligation_ir.raw_transition =
  {
    Proof_obligation_ir.src_state             = t.src;
    dst_state                       = t.dst;
    guard                           = guard_fo t.guard;
    guard_iexpr                     = t.guard;
    ghost_stmts                     = t.attrs.ghost;
    body_stmts                      = t.body;
    instrumentation_stmts           = t.attrs.instrumentation;
  }

(** Build a [Proof_obligation_ir.raw_node] from a finalized abstract node.

    The node carries:
    - the executable transition body exported by the middle-end
    - [specification.spec_assumes/guarantees] set to the user LTL contracts

    No requires/ensures are copied — those are the responsibility of pass 4. *)
let build_raw_node (node : Abs.node) : Proof_obligation_ir.raw_node =
  let ast_node = Abs.to_ast_node node in
  let pre_k_map = Collect.build_pre_k_infos ast_node in
  let transitions = List.map raw_transition_of_abs node.trans in
  {
    Proof_obligation_ir.node_name      = node.semantics.sem_nname;
    inputs                   = node.semantics.sem_inputs;
    outputs                  = node.semantics.sem_outputs;
    locals                   = node.semantics.sem_locals;
    control_states           = node.semantics.sem_states;
    init_state               = node.semantics.sem_init_state;
    instances                = node.semantics.sem_instances;
    pre_k_map;
    transitions;
    assumes                  = node.specification.spec_assumes;
    guarantees               = node.specification.spec_guarantees;
  }
