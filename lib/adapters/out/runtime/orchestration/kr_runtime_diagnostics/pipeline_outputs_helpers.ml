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

(** Helpers for assembling pipeline outputs.

    This module contains shared utilities used by output assembly:
    block concatenation with spans, flow metadata projection, and initial
    program-automaton textual rendering. *)

(** [join_blocks_with_spans] helper value. *)

let join_blocks_with_spans ~sep blocks =
  let b = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  List.iteri
    (fun i s ->
      if i > 0 then (
        Buffer.add_string b sep;
        offset := !offset + String.length sep);
      let start_offset = !offset in
      Buffer.add_string b s;
      offset := !offset + String.length s;
      spans :=
        { Kr_engine.Pipeline_proof_types.start_offset = start_offset; end_offset = !offset } :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)

(** [flow_meta] helper value. *)

let bool_s b = if b then "true" else "false"

let optimization_meta (proof_optimizations : Kr_engine.Pipeline_config.proof_optimizations option) =
  match proof_optimizations with
  | None -> []
  | Some opts ->
      [
        ( "proof_optimizations",
          [
            ( "proof_case_decomposition_strategy",
              Kr_engine.Pipeline_config.string_of_proof_case_decomposition_strategy
                opts.verification.proof_case_decomposition_strategy );
            ( "reachability_strategy",
              Kr_engine.Pipeline_config.string_of_reachability_strategy
                opts.verification.reachability_strategy );
            ( "group_step_contracts",
              bool_s
                (Kr_engine.Pipeline_config.groups_step_contracts
                   opts.verification.proof_plan_strategy) );
            ( "deduplicate_obligation_conditions",
              bool_s
                (Kr_engine.Pipeline_config.deduplicates_obligation_conditions
                   opts.verification.proof_plan_strategy) );
            ( "share_contract_formulas",
              bool_s
                (Kr_engine.Pipeline_config.shares_contract_formulas
                   opts.verification.proof_plan_strategy) );
            ( "bundle_individual_postconditions",
              bool_s
                (Kr_engine.Pipeline_config.bundles_individual_postconditions
                   opts.verification.proof_plan_strategy) );
          ] );
      ]

let flow_meta ?proof_optimizations
    (infos : Kr_engine.Flow_info.pipeline_info) :
    (string * (string * string) list) list =
  let p = Option.value ~default:Kr_engine.Flow_info.empty_parse_info infos.parse in
  let a = Option.value ~default:Kr_engine.Flow_info.empty_automata_info infos.automata_generation in
  let s = Option.value ~default:Kr_engine.Flow_info.empty_summaries_info infos.summaries in
  let i = Option.value ~default:Kr_engine.Flow_info.empty_instrumentation_info infos.instrumentation in
  [
    ("user", [ ("source_path", Option.value ~default:"" p.source_path); ("warnings", string_of_int (List.length p.warnings)) ]);
    ("automata", [ ("states", string_of_int a.residual_state_count); ("edges", string_of_int a.residual_edge_count) ]);
    ("summaries", [ ("warnings", string_of_int (List.length s.warnings)) ]);
    ( "graph_metrics",
      [
        ("require_automata_states", string_of_int i.require_automata_state_count);
        ("require_automata_edges", string_of_int i.require_automata_edge_count);
        ("ensures_automata_states", string_of_int i.ensures_automata_state_count);
        ("ensures_automata_edges", string_of_int i.ensures_automata_edge_count);
        ("product_edges", string_of_int i.product_edge_count);
        ("product_states", string_of_int i.product_state_count);
      ] );
    ( "canonical_metrics",
      [
        ("canonical_summaries", string_of_int i.canonical_summary_count);
        ( "canonical_product_cases",
          string_of_int i.canonical_product_case_count );
      ] );
  ]
  @ optimization_meta proof_optimizations

(** [program_automaton_texts] helper value. *)

let program_automaton_texts
    (proof_cases : Proof_case_program.t) : string * string =
  match Proof_case_program.program proof_cases with
  | [] -> ("", "")
  | node :: _ ->
      let graph =
        Automata_graph_render.render_program_automaton ~node_name:node.node_name ~node
      in
      (graph.dot, graph.labels)
