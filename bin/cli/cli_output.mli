(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** CLI text and side-file output helpers. *)

val write_target : string -> string -> unit

val report_failed_goals :
  Cli_pipeline_service.goal_info list -> string list

val write_text_output : string -> string -> [> `Ok of unit ]

val write_generated_files :
  out_dir:string ->
  C_codegen.generated_file list ->
  [> `Error of bool * string | `Ok of unit ]

val write_timing_dump :
  string -> (string * (string * string) list) list -> unit

val write_goals_dump :
  string -> Pipeline_types.proof_trace list -> unit

val write_automata_bundle :
  out:string ->
  short:bool ->
  Cli_pipeline_service.automata_dump_data ->
  [> `Ok of unit ]

val write_product_bundle :
  out:string ->
  Cli_pipeline_service.automata_dump_data ->
  [> `Ok of unit ]

val write_canonical_bundle :
  out:string ->
  short:bool ->
  Cli_pipeline_service.automata_dump_data ->
  [> `Ok of unit ]
