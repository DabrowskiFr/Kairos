(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type outputs = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  flow_meta : (string * (string * string) list) list;
  goals : Pipeline_proof_types.goal_info list;
  proof_traces : Pipeline_proof_types.proof_trace list;
  vc_locs : (int * Pipeline_proof_types.source_location) list;
  vc_locs_ordered : Pipeline_proof_types.source_location list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  why_time_s : float;
  automata_generation_time_s : float;
  automata_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
}

type automata_outputs = {
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
  flow_meta : (string * (string * string) list) list;
}

type why_outputs = {
  why_text : string;
  flow_meta : (string * (string * string) list) list;
}

type obligations_outputs = {
  vc_text : string;
  smt_text : string;
}

type cost_report_outputs = { cost_report_json : string }
