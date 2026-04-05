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
  let rec lower_formula (formula : Fo_formula.t) : Fo_formula.t option =
    match formula with
    | Fo_formula.FTrue | Fo_formula.FFalse -> Some formula
    | Fo_formula.FAtom atom ->
        Fo_specs.lower_fo_pre_k ~pre_k_map atom |> Option.map (fun atom' -> Fo_formula.FAtom atom')
    | Fo_formula.FNot a -> lower_formula a |> Option.map (fun a' -> Fo_formula.FNot a')
    | Fo_formula.FAnd (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FAnd (a', b'))
        | _ -> None
      end
    | Fo_formula.FOr (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FOr (a', b'))
        | _ -> None
      end
    | Fo_formula.FImp (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FImp (a', b'))
        | _ -> None
      end
  in
  match lower_formula f.logic with Some logic -> { f with logic } | None -> f

let lower_product_transition ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (pc : Ir.product_contract) : Ir.product_contract =
  let lower = lower_fo_o pre_k_map in
  {
    pc with
    common =
      {
        requires = List.map lower pc.common.requires;
        ensures = List.map lower pc.common.ensures;
      };
    safe_summary =
      {
        pc.safe_summary with
        safe_propagates = List.map lower pc.safe_summary.safe_propagates;
        safe_ensures = List.map lower pc.safe_summary.safe_ensures;
      };
    safe_cases =
      List.map
        (fun (c : Ir.safe_product_case) ->
          {
            c with
            propagates = List.map lower c.propagates;
            ensures = List.map lower c.ensures;
          })
        pc.safe_cases;
    unsafe_cases =
      List.map
        (fun (c : Ir.unsafe_product_case) ->
          {
            c with
            ensures = List.map lower c.ensures;
            forbidden = List.map lower c.forbidden;
          })
        pc.unsafe_cases;
  }

(** {2 Main pass} *)

let eliminate (annotated : Ir.annotated_node) : Ir.verified_node =
  let raw = annotated.raw in
  let pre_k_map = raw.pre_k_map in
  let existing_names = List.map (fun (v : vdecl) -> v.vname) raw.core.locals in
  let extra_locals = pre_k_extra_locals ~existing_names pre_k_map in
  let updates = pre_k_shift_stmts pre_k_map in
  let lower = lower_fo_o pre_k_map in
  let transitions =
    List.map
      (fun (t : Ir.annotated_transition) ->
        ({
          Ir.core = t.raw.core;
          guard = t.raw.guard;
          pre_k_updates = updates;
          contracts =
            {
              requires = List.map lower t.contracts.requires;
              ensures = List.map lower t.contracts.ensures;
            };
        } : Ir.verified_transition))
      annotated.transitions
  in
  {
    Ir.core = { raw.core with locals = raw.core.locals @ extra_locals };
    transitions;
    product_transitions = [];
    assumes = raw.assumes;
    guarantees = raw.guarantees;
    coherency_goals = List.map lower annotated.coherency_goals;
    user_invariants = annotated.user_invariants;
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
