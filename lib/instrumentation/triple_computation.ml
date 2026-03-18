module Abs = Abstract_model

(** Pair raw transitions with their corresponding abstract transitions.
    Both lists originate from the same instrumented node and must be in the
    same order (they are produced by the same [List.map] in the instrumentation
    pass and in [Ir_production.build_raw_node]). *)
let zip_transitions (raws : Kairos_ir.raw_transition list)
    (abs_trans : Abs.transition list) :
    (Kairos_ir.raw_transition * Abs.transition) list =
  try List.combine raws abs_trans
  with Invalid_argument _ ->
    failwith
      "Triple_computation.annotate: raw transitions and abstract transitions \
       have different lengths — raw_node and abstract node must originate from \
       the same instrumentation pass output"

(** Lift an abstract transition's contracts into an annotated_transition. *)
let annotate_transition (raw : Kairos_ir.raw_transition)
    (abs_t : Abs.transition) : Kairos_ir.annotated_transition =
  { Kairos_ir.raw; requires = abs_t.requires; ensures = abs_t.ensures }

(** Annotate a raw node with Hoare triples.

    The [node] argument must be the result of
    [Instrumentation.finalize_instrumented_abstract_node]: its transitions
    already carry the requires/ensures computed by [apply_contract_pipeline]
    (user contracts + compatibility invariants). *)
let annotate ~(raw : Kairos_ir.raw_node) ~(node : Abs.node)
    ~(analysis : Product_build.analysis) : Kairos_ir.annotated_node =
  (* [analysis] is reserved for future independent recomputation of
     compat_invariants; for now the invariants are already present in
     [node.trans] after [apply_contract_pipeline]. *)
  ignore analysis;
  let pairs = zip_transitions raw.transitions node.trans in
  let transitions =
    List.map (fun (r, t) -> annotate_transition r t) pairs
  in
  {
    Kairos_ir.raw;
    transitions;
    coherency_goals    = node.attrs.coherency_goals;
    user_invariants    = node.attrs.invariants_user;
    state_invariants   = node.specification.spec_invariants_state_rel;
  }
