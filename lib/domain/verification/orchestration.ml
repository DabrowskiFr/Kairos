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

(** Orchestration entrypoint for domain IR construction.

    The reference-product entry point names the correction-critical path from
    an elaborated program plus supplied automata to product summaries. The
    instrumentation passes remain separate: they are useful for proof/backend
    construction, but they must not be confused with external tool choices,
    dumps, profiling, or backend-specific grouping. *)

open Automaton_types

(** Helper value. *)

let ( let* ) = Result.bind

let rec all_results = function
  | [] -> Ok []
  | result :: rest ->
      let* value = result in
      let* values = all_results rest in
      Ok (value :: values)

(** Type [reference_product_input]. *)

type reference_product_input = {
  reference_program : Verification_model.program_model;
  reference_automata : (Core_syntax.ident * automata_spec) list;
  reference_provenance : Contract_partition.provenance list;
}

(** Type [reference_product]. *)

type reference_node = {
  source_node_name : Core_syntax.ident;
  reference_model : Verification_model.node_model;
  analysis : Temporal_automata.node_data;
  ir : Core_syntax.historical Ir.node_ir;
}

type reference_product = {
  reference_nodes : reference_node list;
}

(** Type [instrumented_ir_pass]. *)

type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass

(** Pass observers for historical enrichment and the typed temporal-lowering
    boundary. *)
type pass_runner = {
  run_historical :
    instrumented_ir_pass ->
    (Core_syntax.historical Ir.node_ir list ->
    Core_syntax.historical Ir.node_ir list) ->
    Core_syntax.historical Ir.node_ir list ->
    Core_syntax.historical Ir.node_ir list;
  run_lowering :
    instrumented_ir_pass ->
    (Core_syntax.historical Ir.node_ir list ->
    Core_syntax.history_free Ir.node_ir list) ->
    Core_syntax.historical Ir.node_ir list ->
    Core_syntax.history_free Ir.node_ir list;
}

let direct_pass_runner =
  {
    run_historical = (fun _ pass nodes -> pass nodes);
    run_lowering = (fun _ pass nodes -> pass nodes);
  }

(** [build_reference_product] helper value. *)

let build_reference_product
    ({ reference_program; reference_automata; reference_provenance } :
      reference_product_input) :
    (reference_product, string) result =
  let* analyzed_nodes =
    From_model.analyze_model_program ~automata:reference_automata
      reference_program
  in
  let* reference_nodes =
    analyzed_nodes
    |> List.map (fun (node : From_model.analyzed_node) ->
           let node_name = node.model.node_name in
           match
             List.find_opt
               (fun (provenance : Contract_partition.provenance) ->
                 provenance.reference_node_name = node_name)
               reference_provenance
           with
           | Some provenance ->
               Ok
                 {
                   source_node_name = provenance.source_node_name;
                   reference_model = node.model;
                   analysis = node.analysis;
                   ir = node.ir;
                 }
           | None ->
               Error
                 (Printf.sprintf
                    "Missing source provenance for reference node %s"
                    node_name))
    |> all_results
  in
  Ok { reference_nodes }

(** [build_instrumented_ir] helper value. *)

let build_instrumented_ir
    ?observe_fact_family
    ?(pass_runner = direct_pass_runner)
    (initial_nodes : Core_syntax.historical Ir.node_ir list) :
    Ir.program_ir =
  let product_characteristics =
    initial_nodes
    |> List.map (fun (node : Core_syntax.historical Ir.node_ir) ->
           Product_characteristics.build ~node)
  in
  let pre_nodes =
    initial_nodes
    |> pass_runner.run_historical Pre_pass
         (Pre.run_program ?observe_family:observe_fact_family
            ~product_characteristics)
    |> pass_runner.run_historical Product_reachability_pass
         Product_reachability.run_program
    |> pass_runner.run_historical Post_pass
         (Post.run_program ?observe_family:observe_fact_family
            ~product_characteristics)
  in
  let backend_nodes =
    pre_nodes
    |> pass_runner.run_lowering Temporal_lower_pass Temporal_lower.run_program
  in
  ({ nodes = backend_nodes } : Ir.program_ir)
