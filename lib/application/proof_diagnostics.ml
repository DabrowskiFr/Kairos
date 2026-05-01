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

module Types = Pipeline_types

let generic_diagnostic_for_status ~(status : string)
    (diagnostic : Types.proof_diagnostic) : Types.proof_diagnostic =
  let normalized = String.lowercase_ascii status in
  match normalized with
  | "valid" | "proved" ->
      {
        diagnostic with
        category = "proved";
        summary = "The goal was proved.";
        detail = "Kairos proved this verification condition on the standard proof path.";
        solver_detail = None;
      }
  | "pending" -> diagnostic
  | "timeout" ->
      {
        diagnostic with
        category = "solver_timeout";
        summary = "The prover timed out on this goal.";
        detail = "Re-run with a larger timeout or inspect the VC/SMT artifacts.";
      }
  | "unknown" ->
      {
        diagnostic with
        category = "solver_inconclusive";
        summary = "The prover returned an inconclusive result.";
        detail = "Inspect solver feedback and generated VC/SMT artifacts.";
      }
  | _ ->
      {
        diagnostic with
        category = "solver_failure";
        summary = "The goal failed on the standard proof path.";
        detail = "Inspect the failing VC and dumped SMT artifact.";
      }

let apply_goal_results_to_outputs ~(out : Types.outputs)
    ~(goal_results :
       (int * string * string * float * string option * string option) list) :
    Types.outputs =
  let results_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun ((idx, _, _, _, _, _) as item) -> Hashtbl.replace results_tbl idx item)
    goal_results;
  let proof_traces =
    List.map
      (fun (trace : Types.proof_trace) ->
        match Hashtbl.find_opt results_tbl trace.goal_index with
        | None -> trace
        | Some (_idx, goal_name, status, time_s, dump_path, vc_id) ->
            {
              trace with
              goal_name;
              status;
              solver_status = status;
              time_s;
              vc_id;
              dump_path;
              diagnostic = generic_diagnostic_for_status ~status trace.diagnostic;
            })
      out.proof_traces
  in
  let goals =
    List.map
      (fun (trace : Types.proof_trace) ->
        ( trace.goal_name,
          trace.status,
          trace.time_s,
          trace.dump_path,
          trace.vc_id ))
      proof_traces
  in
  { out with proof_traces; goals }
