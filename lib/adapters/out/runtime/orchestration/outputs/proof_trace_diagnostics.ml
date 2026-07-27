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

module Contract = Kairos_why3_contract.Why3_contract

let build ~(status : string) ~(goal_text : string)
    ~(native_probe : Contract.solver_probe option) :
    Pipeline_proof_types.proof_diagnostic =
  let status_norm = String.lowercase_ascii (String.trim status) in
  let native_probe_status =
    Option.map
      (fun (probe : Contract.solver_probe) -> probe.status)
      native_probe
  in
  let native_probe_detail =
    Option.bind native_probe (fun (probe : Contract.solver_probe) ->
        probe.detail)
  in
  let native_probe_model =
    Option.bind native_probe (fun (probe : Contract.solver_probe) ->
        probe.model_text)
  in
  let category, probable_cause, suggestions, detail =
    match (status_norm, native_probe_status, native_probe_model) with
    | _, _, Some _ ->
        ( "counterexample_found",
          Some
            "The native solver produced a satisfying model for the negated VC.",
          [
            "Inspect the native model first, then compare against the VC and source intent.";
          ],
          Printf.sprintf
            "Goal `%s` is falsifiable: the native solver returned a concrete model."
            goal_text )
    | ("valid" | "proved"), _, _ ->
        ( "proved",
          Some "This VC was discharged successfully.",
          [ "No action required." ],
          Printf.sprintf "Goal `%s` was proved successfully." goal_text )
    | "timeout", _, _ ->
        ( "solver_timeout",
          Some "The solver reached its time limit before closing this VC.",
          [ "Retry with a larger timeout and inspect the generated VC." ],
          Printf.sprintf "Goal `%s` timed out." goal_text )
    | "unknown", _, _ ->
        ( "solver_inconclusive",
          Some
            (match native_probe_detail with
            | Some detail ->
                Printf.sprintf
                  "The solver returned an inconclusive result (%s)." detail
            | None -> "The solver returned an inconclusive result."),
          [ "Inspect VC/SMT artifacts to identify unsupported or hard patterns." ],
          Printf.sprintf "Goal `%s` is inconclusive." goal_text )
    | "invalid", _, _ ->
        ( "counterexample_found",
          Some
            "The VC is falsifiable: the solver established the negated obligation as satisfiable.",
          [ "Inspect the failing VC and SMT dump first." ],
          Printf.sprintf
            "Goal `%s` is falsifiable under the current assumptions."
            goal_text )
    | _ ->
        ( "solver_failure",
          Some
            (match native_probe_detail with
            | Some detail ->
                Printf.sprintf
                  "The prover failed before a conclusive result (%s)." detail
            | None -> "The prover failed before a conclusive proof result."),
          [ "Inspect the dumped SMT task and prover configuration." ],
          Printf.sprintf
            "Goal `%s` failed without a conclusive proof result." goal_text )
  in
  {
    category;
    summary = category;
    detail;
    probable_cause;
    missing_elements = [];
    goal_symbols = [];
    analysis_method =
      (match native_probe_model with
      | Some _ ->
          "Native SMT model recovered from the targeted solver on the focused VC"
      | None -> "Status-based diagnostic without structured provenance mapping");
    solver_detail = native_probe_detail;
    native_unsat_core_solver = None;
    native_unsat_core_hypothesis_ids = [];
    native_counterexample_solver =
      Option.bind native_probe (fun (probe : Contract.solver_probe) ->
          match probe.model_text with Some _ -> Some probe.solver | None -> None);
    native_counterexample_model = native_probe_model;
    kairos_core_hypotheses = [];
    why3_noise_hypotheses = [];
    relevant_hypotheses = [];
    context_hypotheses = [];
    unused_hypotheses = [];
    suggestions;
    limitations =
      [
        "This diagnostic view is status-oriented and does not rely on provenance/origin graph mapping.";
        "Native counterexample extraction currently relies on a direct Z3 SMT replay path when available.";
      ];
  }
