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

type produced = {
  automata : (Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list;
  automata_info : Kr_engine.Kr_engine_flow_info.automata_info;
}

let ( let* ) = Result.bind

let produce_with_spot (proof_case_program : Kr_verification_cases.t) :
    (produced, Kr_engine.Kr_engine_pipeline_error.t) result =
  try
    let build_automaton request =
      Kr_spot_adapter.Spot_automaton_builder.build
        ~record_elapsed:(fun elapsed_s ->
          Runtime_metrics.record_spot ~elapsed_s)
        request
    in
    let t_automata = Unix.gettimeofday () in
    let* automata, automata_info =
      Automata_generation.run proof_case_program
        ~build_automaton
      |> Result.map_error (fun message ->
             Kr_engine.Kr_engine_pipeline_error.Flow_error message)
    in
    Runtime_metrics.record_automata_generation
      ~elapsed_s:(Unix.gettimeofday () -. t_automata);
    Ok { automata; automata_info }
  with exn -> Error (Kr_engine.Kr_engine_pipeline_error.Flow_error (Printexc.to_string exn))
