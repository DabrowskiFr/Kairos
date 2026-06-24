(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

(** Text renderers for pipeline artifact bundles. *)

open Pretty

let first_non_empty (xs : string list) : string =
  match List.find_opt (fun s -> String.trim s <> "") xs with Some s -> s | None -> ""

let join_non_empty (xs : string list) : string =
  xs
  |> List.filter (fun s -> String.trim s <> "")
  |> String.concat "\n\n"

let string_of_product_state (st : Proof_kernel_types.product_state_ir) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let string_of_step_kind = function
  | Proof_kernel_types.StepSafe -> "safe"
  | Proof_kernel_types.StepBadAssumption -> "bad_assumption"
  | Proof_kernel_types.StepBadGuarantee -> "bad_guarantee"

let string_of_origin = function
  | Proof_kernel_types.OriginSourceProductSummary -> "source-product-summary"
  | Proof_kernel_types.OriginPhaseStepPreSummary -> "phase-step-pre"
  | Proof_kernel_types.OriginPhaseStepSummary -> "phase-step"
  | Proof_kernel_types.OriginSafety -> "safety"
  | Proof_kernel_types.OriginInitNodeInvariant -> "init-node-invariant"
  | Proof_kernel_types.OriginInitAutomatonCoherence -> "init-automaton-coherence"
  | Proof_kernel_types.OriginPropagationNodeInvariant -> "propagation-node-invariant"
  | Proof_kernel_types.OriginPropagationAutomatonCoherence ->
      "propagation-automaton-coherence"

let string_of_time = function
  | Proof_kernel_types.CurrentTick -> "current"
  | Proof_kernel_types.PreviousTick -> "previous"
  | Proof_kernel_types.StepTickContext -> "step"

let string_of_rel_desc = function
  | Proof_kernel_types.RelFactProgramState st -> "state = " ^ st
  | Proof_kernel_types.RelFactGuaranteeState idx ->
      Printf.sprintf "guarantee_state = %d" idx
  | Proof_kernel_types.RelFactPhaseFormula fo
  | Proof_kernel_types.RelFactFormula fo ->
      string_of_fo fo
  | Proof_kernel_types.RelFactFalse -> "false"

let string_of_rel_fact (fact : Proof_kernel_types.relational_clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_time fact.time) (string_of_rel_desc fact.desc)

let string_of_rel_clause (clause : Proof_kernel_types.relational_generated_clause_ir) =
  let side facts =
    match facts with
    | [] -> "true"
    | xs -> xs |> List.map string_of_rel_fact |> String.concat "; "
  in
  Printf.sprintf "[%s] %s ==> %s" (string_of_origin clause.origin)
    (side clause.hypotheses) (side clause.conclusions)

let helper_prefix_of_step (step : Proof_kernel_types.product_step_ir) =
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_*"
    (String.lowercase_ascii step.program_transition_id)
    (String.lowercase_ascii step.src.prog_state)
    step.src.assume_state_index step.src.guarantee_state_index
    (string_of_step_kind step.step_kind)

let render_canonical_node
    (node : Proof_kernel_types.exported_node_summary_ir) : string =
  let ir = node.normalized_ir in
  let transition_by_id = Hashtbl.create 16 in
  List.iter
    (fun (tr : Proof_kernel_types.reactive_transition_ir) ->
      Hashtbl.replace transition_by_id tr.transition_id tr)
    ir.reactive_program.transitions;
  let render_summary idx (summary : Proof_kernel_types.proof_step_summary_ir) =
    match summary.steps with
    | [] -> []
    | step :: _ ->
        let transition =
          match Hashtbl.find_opt transition_by_id step.program_transition_id with
          | Some tr -> Printf.sprintf "%s -> %s" tr.src_state tr.dst_state
          | None -> step.program_transition_id
        in
        let dsts =
          summary.steps
          |> List.map (fun (s : Proof_kernel_types.product_step_ir) ->
                 string_of_product_state s.dst)
          |> List.sort_uniq String.compare
          |> String.concat ", "
        in
        [
          Printf.sprintf "summary %03d" (idx + 1);
          "  source-transition: " ^ transition;
          "  helper-prefix: " ^ helper_prefix_of_step step;
          "  product-source: " ^ string_of_product_state step.src;
          "  product-destinations: " ^ dsts;
          "  kind: " ^ string_of_step_kind step.step_kind;
          Printf.sprintf "  grouped-product-steps: %d" (List.length summary.steps);
          Printf.sprintf "  entry-clauses: %d" (List.length summary.entry_clauses);
          Printf.sprintf "  post-clauses: %d" (List.length summary.clauses);
          "";
        ]
  in
  String.concat "\n"
    (("Node " ^ node.signature.node_name)
     :: (ir.proof_step_summaries |> List.mapi render_summary |> List.concat))

let render_canonical
    (nodes : Proof_kernel_types.exported_node_summary_ir list) =
  nodes |> List.map render_canonical_node |> join_non_empty

let render_obligations_map_node
    (node : Proof_kernel_types.exported_node_summary_ir) : string =
  let ir = node.normalized_ir in
  let transition_by_id = Hashtbl.create 16 in
  List.iter
    (fun (tr : Proof_kernel_types.reactive_transition_ir) ->
      Hashtbl.replace transition_by_id tr.transition_id tr)
    ir.reactive_program.transitions;
  let render_summary idx (summary : Proof_kernel_types.proof_step_summary_ir) =
    match summary.steps with
    | [] -> []
    | step :: _ ->
        let transition =
          match Hashtbl.find_opt transition_by_id step.program_transition_id with
          | Some tr ->
              Printf.sprintf "%s -> %s" tr.src_state tr.dst_state
          | None -> step.program_transition_id
        in
        let dsts =
          summary.steps
          |> List.map (fun (s : Proof_kernel_types.product_step_ir) ->
                 string_of_product_state s.dst)
          |> List.sort_uniq String.compare
          |> String.concat ", "
        in
        [
          Printf.sprintf "summary %03d" (idx + 1);
          "  node: " ^ node.signature.node_name;
          "  why3-helper-prefix: " ^ helper_prefix_of_step step;
          "  source-transition: " ^ transition;
          "  product-source: " ^ string_of_product_state step.src;
          "  product-destinations: " ^ dsts;
          "  kind: " ^ string_of_step_kind step.step_kind;
          Printf.sprintf "  grouped-product-steps: %d" (List.length summary.steps);
          Printf.sprintf "  entry-clauses: %d" (List.length summary.entry_clauses);
        ]
        @ List.mapi
            (fun i clause ->
              Printf.sprintf "    entry[%02d]: %s" (i + 1)
                (string_of_rel_clause clause))
            summary.entry_clauses
        @
        [
          Printf.sprintf "  post-clauses: %d" (List.length summary.clauses);
        ]
        @ List.mapi
            (fun i clause ->
              Printf.sprintf "    post[%02d]: %s" (i + 1)
                (string_of_rel_clause clause))
            summary.clauses
        @ [ "" ]
  in
  String.concat "\n"
    (("Node " ^ node.signature.node_name)
     :: (ir.proof_step_summaries |> List.mapi render_summary |> List.concat))

let render_obligations_map
    (nodes : Proof_kernel_types.exported_node_summary_ir list) =
  nodes |> List.map render_obligations_map_node |> join_non_empty
