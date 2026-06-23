(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

module Step_names = Why_product_step_names

type goal_attribution = {
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
}

type t = (string, goal_attribution) Hashtbl.t

let product_state_source (st : Ir.product_state) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let attribution_step_class
    (step_class : Why_runtime_view.runtime_step_class) =
  match step_class with
  | Why_runtime_view.StepSafe ->
      ("product-step-safe", Some "guarantee-progress")
  | Why_runtime_view.StepBadGuarantee ->
      ("product-step-bad-guarantee", Some "guarantee-violation-exclusion")

let goal_name_lookup_key (goal_name : string) =
  match String.index_opt goal_name '\'' with
  | None -> goal_name
  | Some idx -> String.sub goal_name 0 idx

let attribution_of_step ~node_name ~index
    (step : Why_runtime_view.runtime_product_transition_view) =
  let obligation_kind, obligation_category =
    attribution_step_class step.step_class
  in
  let source =
    Printf.sprintf
      "helper=%s;product_src=%s;product_dst=%s;requires=%d;local_requires=%d;\
       propagates=%d;ensures=%d;forbidden=%d"
      (Step_names.product_step_helper_name ~index step)
      (product_state_source step.product_src)
      (product_state_source step.product_dst)
      (List.length step.requires)
      (List.length step.local_requires)
      (List.length step.propagates)
      (List.length step.ensures)
      (List.length step.forbidden)
  in
  {
    source;
    node = Some node_name;
    transition =
      Some
        (Printf.sprintf "%s -> %s (%s)" step.src_state step.dst_state
           step.transition_id);
    obligation_kind;
    obligation_family = Some "product-step";
    obligation_category;
  }

let attribution_of_group ~node_name ~index ~group_size
    (step : Why_runtime_view.runtime_product_transition_view) =
  let obligation_kind, obligation_category =
    attribution_step_class step.step_class
  in
  let source =
    Printf.sprintf
      "helper=%s;group_size=%d;product_src=%s;requires=%d;local_requires=%d;\
       propagates=%d;ensures=%d;forbidden=%d"
      (Step_names.product_step_group_helper_name ~index step)
      group_size
      (product_state_source step.product_src)
      (List.length step.requires)
      (List.length step.local_requires)
      (List.length step.propagates)
      (List.length step.ensures)
      (List.length step.forbidden)
  in
  {
    source;
    node = Some node_name;
    transition =
      Some
        (Printf.sprintf "%s -> %s (%s)" step.src_state step.dst_state
           step.transition_id);
    obligation_kind;
    obligation_family = Some "product-step-group";
    obligation_category;
  }

let build
    ~(opts : Pipeline_types.proof_optimizations)
    (instrumentation : Ir.node_ir list) : t =
  let table = Hashtbl.create 256 in
  let add_step_attributions (runtime : Why_runtime_view.t) =
    List.iteri
      (fun index step ->
        let helper_name = Step_names.product_step_helper_name ~index step in
        Hashtbl.replace table helper_name
          (attribution_of_step ~node_name:runtime.node_name ~index step))
      runtime.product_transitions
  in
  let add_group_attributions (runtime : Why_runtime_view.t) =
    let groups = Hashtbl.create 128 in
    let order = ref [] in
    let group_key (step : Why_runtime_view.runtime_product_transition_view) =
      let t =
        Why_runtime_view.transition_of_product_step
          ~simplify_runtime_actions:opts.simplify_why3_runtime_actions step
      in
      (step.step_class, t)
    in
    runtime.product_transitions
    |> List.iteri (fun index step ->
           let key = group_key step in
           if not (Hashtbl.mem groups key) then order := key :: !order;
           let previous =
             Hashtbl.find_opt groups key |> Option.value ~default:[]
           in
           Hashtbl.replace groups key ((index, step) :: previous));
    List.rev !order
    |> List.iter (fun key ->
           let indexed_steps = Hashtbl.find groups key |> List.rev in
           if List.length indexed_steps > 1 then
             indexed_steps
             |> List.iter (fun (index, representative) ->
                    let helper_name =
                      Step_names.product_step_group_helper_name ~index
                        representative
                    in
                    Hashtbl.replace table helper_name
                      (attribution_of_group ~node_name:runtime.node_name ~index
                         ~group_size:(List.length indexed_steps)
                         representative)))
  in
  instrumentation
  |> List.iter (fun (node : Ir.node_ir) ->
         let runtime =
           Why_runtime_view.of_ir_node
             ~simplify_runtime_actions:opts.simplify_why3_runtime_actions
             ~slice_transition_bodies:opts.slice_why3_transition_bodies node
         in
         add_step_attributions runtime;
         if opts.group_why3_product_steps then add_group_attributions runtime);
  table

let attribution_for_goal attributions goal_name =
  Hashtbl.find_opt attributions (goal_name_lookup_key goal_name)

let apply attributions ~goal_name (trace : Pipeline_types.proof_trace) =
  match attribution_for_goal attributions goal_name with
  | None -> trace
  | Some attribution ->
      {
        trace with
        source = attribution.source;
        node = attribution.node;
        transition = attribution.transition;
        obligation_kind = attribution.obligation_kind;
        obligation_family = attribution.obligation_family;
        obligation_category = attribution.obligation_category;
      }
