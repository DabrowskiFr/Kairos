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

let ( let* ) = Result.bind

type run_metrics = {
  product_s : float;
  canonical_s : float;
}

let build_initial_ir ~(automata : Automata_generation.node_builds) (parsed : Stage_types.parsed) :
    (Ir.node_ir list, string) result =
  From_ast.of_ast_program ~automata parsed

let collect_formula_origins (nodes : Ir.node_ir list) : (int * Formula_origin.t option) list =
  let collect_formula acc (formula : Ir.summary_formula) =
    (formula.meta.oid, formula.meta.origin) :: acc
  in
  let collect_product_transition acc (transition : Ir.product_step_summary) =
    transition.requires |> List.fold_left collect_formula acc |> fun acc ->
    transition.ensures |> List.fold_left collect_formula acc |> fun acc ->
    transition.safe_cases
    |> List.fold_left
         (fun acc (case : Ir.safe_product_case) ->
           collect_formula acc case.admissible_guard)
         acc
    |> fun acc ->
    transition.unsafe_cases
    |> List.fold_left
         (fun acc (case : Ir.unsafe_product_case) -> collect_formula acc case.excluded_guard)
         acc
  in
  nodes
  |> List.fold_left
       (fun acc (node : Ir.node_ir) ->
         List.fold_left collect_product_transition acc node.summaries)
       []
  |> List.rev

let formula_origin_map_of_nodes (nodes : Ir.node_ir list) : (int * Formula_origin.t option) list =
  collect_formula_origins nodes

let run_with_metrics (parsed : Stage_types.parsed) (automata : Automata_generation.node_builds) :
    ((Ir.program_ir * run_metrics), string) result =
  (* Phase 1: initial IR construction = AST context projection + minimal summaries. *)
  let t_product = Unix.gettimeofday () in
  let* initial_nodes = build_initial_ir ~automata parsed in
  let product_s = Unix.gettimeofday () -. t_product in
  let t_canonical = Unix.gettimeofday () in
  let nodes =
    initial_nodes
    |> Pre.run_program
    |> Post.run_program
    |> Temporal_lower.run_program
  in
  let canonical_s = Unix.gettimeofday () -. t_canonical in
  let program = ({ nodes; formula_origin_map = formula_origin_map_of_nodes nodes } : Ir.program_ir) in
  Ok (program, { product_s; canonical_s })

let run (parsed : Stage_types.parsed) (automata : Automata_generation.node_builds) :
    (Ir.program_ir, string) result =
  run_with_metrics parsed automata |> Result.map fst
