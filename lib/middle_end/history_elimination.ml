open Ast

let unique_pre_k_infos (pre_k_map : (hexpr * Support.pre_k_info) list) : Support.pre_k_info list =
  pre_k_map
  |> List.fold_left
       (fun acc (_, info) ->
         if List.exists (fun existing -> existing.Support.expr = info.Support.expr && existing.Support.names = info.Support.names) acc then
           acc
         else acc @ [ info ])
       []

(** {2 Pre-k locals}

    Compute the [__pre_k{k}_x] vdecls that must be added to the node locals.
    Replicates [Product_kernel_ir.pre_k_locals_of_ast] but works directly from
    the [pre_k_map] stored in the [raw_node] (avoids a round-trip through the
    AST). *)
let pre_k_extra_locals ~(existing_names : ident list)
    (pre_k_map : (hexpr * Support.pre_k_info) list) : vdecl list =
  unique_pre_k_infos pre_k_map
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing_names then None
             else Some { vname = name; vty = info.Support.vty })
           info.Support.names)

(** {2 Shift statements}

    Generate the [pre_k_updates] statements for a node:
      [__pre_k2_x := __pre_k1_x;  __pre_k1_x := x;  ...]

    Replicates [Why_runtime_view.pre_k_updates_of_map] to avoid a dependency
    from a middle-end pass on a backend/why module. *)
let pre_k_shift_stmts (pre_k_map : (hexpr * Support.pre_k_info) list) : stmt list =
  let s desc = { stmt = desc; loc = None } in
  let mk_ivar name = { iexpr = IVar name; loc = None } in
  unique_pre_k_infos pre_k_map
  |> List.concat_map (fun info ->
      let names = info.Support.names in
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
        | name :: _ -> [ s (SAssign (name, info.Support.expr)) ]
      in
      shifts @ first)

(** {2 Formula substitution}

    Substitute [HPreK(x, k)] → [HNow (IVar "__pre_k{k}_x")] in an [ltl_o].
    Uses [Fo_specs.lower_fo_pre_k] which returns [None] when a [HPreK] is not
    found in the map; in that case we keep the formula verbatim. *)
let lower_fo_o (pre_k_map : (hexpr * Support.pre_k_info) list) (f : ltl_o) : ltl_o =
  match Fo_specs.lower_ltl_pre_k ~pre_k_map f.value with
  | Some fo' -> { f with value = fo' }
  | None -> f

let lower_state_inv (pre_k_map : (hexpr * Support.pre_k_info) list)
    (inv : invariant_state_rel) : invariant_state_rel =
  match Fo_specs.lower_ltl_pre_k ~pre_k_map inv.formula with
  | Some f -> { inv with formula = f }
  | None -> inv

(** {2 Main pass} *)

let eliminate (annotated : Kairos_ir.annotated_node) : Kairos_ir.verified_node =
  let raw = annotated.raw in
  let pre_k_map = raw.pre_k_map in
  let existing_names = List.map (fun (v : vdecl) -> v.vname) raw.locals in
  let extra_locals = pre_k_extra_locals ~existing_names pre_k_map in
  let updates = pre_k_shift_stmts pre_k_map in
  let lower = lower_fo_o pre_k_map in
  let transitions =
    List.map
      (fun (t : Kairos_ir.annotated_transition) ->
        {
          Kairos_ir.src_state             = t.raw.src_state;
          dst_state                       = t.raw.dst_state;
          guard                           = t.raw.guard;
          guard_iexpr                     = t.raw.guard_iexpr;
          ghost_stmts                     = t.raw.ghost_stmts;
          body_stmts                      = t.raw.body_stmts;
          instrumentation_stmts           = t.raw.instrumentation_stmts;
          pre_k_updates                   = updates;
          requires                        = List.map lower t.requires;
          ensures                         = List.map lower t.ensures;
        })
      annotated.transitions
  in
  {
    Kairos_ir.node_name        = raw.node_name;
    inputs                     = raw.inputs;
    outputs                    = raw.outputs;
    locals                     = raw.locals @ extra_locals;
    control_states             = raw.control_states;
    init_state                 = raw.init_state;
    instances                  = raw.instances;
    transitions;
    assumes                    = raw.assumes;
    guarantees                 = raw.guarantees;
    coherency_goals            = List.map lower annotated.coherency_goals;
    user_invariants            = annotated.user_invariants;
    state_invariants           = List.map (lower_state_inv pre_k_map) annotated.state_invariants;
  }
