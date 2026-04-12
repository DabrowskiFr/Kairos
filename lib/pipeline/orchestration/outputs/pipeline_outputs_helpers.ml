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

open Ast

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
        { Pipeline_types.start_offset = start_offset; end_offset = !offset } :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)

let stage_meta (infos : Pipeline_types.stage_infos) : (string * (string * string) list) list =
  let p = Option.value ~default:Stage_info.empty_parse_info infos.parse in
  let a = Option.value ~default:Stage_info.empty_automata_info infos.automata_generation in
  let s = Option.value ~default:Stage_info.empty_summaries_info infos.summaries in
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
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
        ("product_edges_full", string_of_int i.product_edge_count_full);
        ("product_edges_live", string_of_int i.product_edge_count_live);
        ("product_states_full", string_of_int i.product_state_count_full);
        ("product_states_live", string_of_int i.product_state_count_live);
      ] );
    ( "canonical_metrics",
      [
        ("canonical_summaries", string_of_int i.canonical_summary_count);
        ("canonical_cases_safe", string_of_int i.canonical_case_safe_count);
        ( "canonical_cases_bad_assumption",
          string_of_int i.canonical_case_bad_assumption_count );
        ( "canonical_cases_bad_guarantee",
          string_of_int i.canonical_case_bad_guarantee_count );
      ] );
  ]

let program_automaton_texts (asts : Pipeline_types.ast_stages) : string * string =
  match asts.automata_generation with
  | [] -> ("", "")
  | node :: _ ->
      let graph =
        Automata_graph_render.render_program_automaton ~node_name:node.semantics.sem_nname ~node
      in
      (graph.dot, graph.labels)
