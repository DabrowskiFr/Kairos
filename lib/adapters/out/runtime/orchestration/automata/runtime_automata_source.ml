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
  automata : (Core_syntax.ident * Automaton_types.automata_spec) list;
  automata_info : Flow_info.automata_info;
}

let ( let* ) = Result.bind

let produce_with_spot (program : Verification_model.program_model) :
    (produced, Pipeline_error.t) result =
  try
    let build_automaton request =
      Kairos_spot_adapter.Spot_automaton_builder.build
        ~record_elapsed:(fun elapsed_s ->
          Runtime_metrics.record_spot ~elapsed_s)
        request
    in
    let t_automata = Unix.gettimeofday () in
    let* automata, automata_info =
      Automata_generation.run program
        ~build_automaton
      |> Result.map_error (fun message ->
             Pipeline_error.Flow_error message)
    in
    Runtime_metrics.record_automata_generation
      ~elapsed_s:(Unix.gettimeofday () -. t_automata);
    Ok { automata; automata_info }
  with exn -> Error (Pipeline_error.Flow_error (Printexc.to_string exn))
