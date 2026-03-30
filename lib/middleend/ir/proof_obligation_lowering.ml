open Ast

let unique_pre_k_infos (pre_k_map : (hexpr * Temporal_support.pre_k_info) list) : Temporal_support.pre_k_info list =
  pre_k_map
  |> List.fold_left
       (fun acc (_, info) ->
         if List.exists (fun existing -> existing.Temporal_support.names = info.Temporal_support.names) acc then
           acc
         else acc @ [ info ])
       []

(** {2 Pre-k locals}

    Compute the [__pre_k{k}_x] vdecls that must be added to the node locals.
    Replicates [Proof_kernel_types.pre_k_locals_of_ast] but works directly from
    the [pre_k_map] stored in the [raw_node] (avoids a round-trip through the
    AST). *)
let pre_k_extra_locals ~(existing_names : ident list)
    (pre_k_map : (hexpr * Temporal_support.pre_k_info) list) : vdecl list =
  unique_pre_k_infos pre_k_map
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing_names then None
             else Some { vname = name; vty = info.Temporal_support.vty })
           info.Temporal_support.names)

(** {2 Shift statements}

    Generate the [pre_k_updates] statements for a node:
      [__pre_k2_x := __pre_k1_x;  __pre_k1_x := x;  ...]

    Replicates [Why_runtime_view.pre_k_updates_of_map] to avoid a dependency
    from a middle-end pass on a backend/why module. *)
let pre_k_shift_stmts (pre_k_map : (hexpr * Temporal_support.pre_k_info) list) : stmt list =
  let s desc = { stmt = desc; loc = None } in
  let mk_ivar name = { iexpr = IVar name; loc = None } in
  unique_pre_k_infos pre_k_map
  |> List.concat_map (fun info ->
      let names = info.Temporal_support.names in
      (* Shift deeper slots first: __pre_k{n}_x := __pre_k{n-1}_x, …  *)
      let shifts =
        let rec loop i acc =
          if i <= 1 then acc
          else
            let tgt = List.nth names (i - 1) in
            let src = List.nth names (i - 2) in
            loop (i - 1) (acc @ [ s (SAssign (tgt, mk_ivar src)) ])
        in
        loop (List.length names) []
      in
      (* Capture current value into the shallowest slot: __pre_k1_x := x *)
      let first =
        match names with
        | [] -> []
        | name :: _ -> [ s (SAssign (name, info.Temporal_support.expr)) ]
      in
      shifts @ first)

(** {2 Formula substitution}

    Substitute [HPreK(x, k)] → [HNow (IVar "__pre_k{k}_x")] in an [ltl_o].
    Uses [Fo_specs.lower_fo_pre_k] which returns [None] when a [HPreK] is not
    found in the map; in that case we keep the formula verbatim. *)
let lower_fo_o (pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (f : Ir.contract_formula) : Ir.contract_formula =
  match Fo_specs.lower_ltl_pre_k ~pre_k_map f.value with
  | Some fo_atom' -> { f with value = fo_atom' }
  | None -> f

let lower_product_transition ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (pc : Ir.product_contract) : Ir.product_contract =
  let lower = lower_fo_o pre_k_map in
  {
    pc with
    requires = List.map lower pc.requires;
    cases =
      List.map
        (fun (case : Ir.product_case) ->
          {
            case with
            propagates = List.map lower case.propagates;
            ensures = List.map lower case.ensures;
            forbidden = List.map lower case.forbidden;
          })
        pc.cases;
  }

(** {2 Main pass} *)

let eliminate (annotated : Ir.annotated_node) : Ir.verified_node =
  let raw = annotated.raw in
  let pre_k_map = raw.pre_k_map in
  let existing_names = List.map (fun (v : vdecl) -> v.vname) raw.locals in
  let extra_locals = pre_k_extra_locals ~existing_names pre_k_map in
  let updates = pre_k_shift_stmts pre_k_map in
  let lower = lower_fo_o pre_k_map in
  let transitions =
    List.map
      (fun (t : Ir.annotated_transition) ->
        {
          Ir.src_state             = t.raw.src_state;
          dst_state                       = t.raw.dst_state;
          guard                           = t.raw.guard;
          guard_iexpr                     = t.raw.guard_iexpr;
          body_stmts                      = t.raw.body_stmts;
          pre_k_updates                   = updates;
          requires                        = List.map lower t.requires;
          ensures                         = List.map lower t.ensures;
        })
      annotated.transitions
  in
  {
    node_name                   = raw.node_name;
    inputs                     = raw.inputs;
    outputs                    = raw.outputs;
    locals                     = raw.locals @ extra_locals;
    control_states             = raw.control_states;
    init_state                 = raw.init_state;
    instances                  = raw.instances;
    transitions;
    product_transitions        = [];
    assumes                    = raw.assumes;
    guarantees                 = raw.guarantees;
    coherency_goals            = List.map lower annotated.coherency_goals;
    user_invariants            = annotated.user_invariants;
  }

let apply_node (node : Ir.node) : Ir.node =
  let annotated =
    match node.proof_views.annotated with
    | Some annotated -> annotated
    | None -> failwith "Proof_obligation_lowering.apply_node: missing annotated proof view"
  in
  let lowered = eliminate annotated in
  let verified =
    {
      lowered with
      product_transitions =
        List.map (lower_product_transition ~pre_k_map:annotated.raw.pre_k_map) node.product_transitions;
    }
  in
  { node with proof_views = { node.proof_views with verified = Some verified } }

let apply_program (program : Ir.node list) : Ir.node list = List.map apply_node program
