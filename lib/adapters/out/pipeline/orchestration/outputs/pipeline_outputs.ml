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

include Pipeline_outputs_helpers

let build_outputs ~(cfg : Pipeline_types.config)
    ~(snapshot : Pipeline_types.pipeline_snapshot) :
    (Pipeline_types.outputs, Pipeline_types.error) result =
  let asts = snapshot.asts in
  match Pipeline_artifact_bundle.build ~asts with
  | Error msg -> Error (Pipeline_types.Stage_error msg)
  | Ok artifacts ->
      let obligation_summary =
        Obligation_taxonomy.summarize_program asts.instrumentation
      in
      (match Proof_runner.run ~cfg ~instrumentation:asts.instrumentation with
      | Error _ as err -> err
      | Ok proof ->
          Ok
            (Output_mapper.map_outputs ~cfg ~snapshot ~artifacts ~proof
               ~obligation_summary))
