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

(** Why3 proof execution and VC/SMT dump assembly for one IR program. *)

type run_output = {
  why_text : string;
  why_spans : (int * (int * int)) list;
  vc_text : string;
  vc_spans_ordered : Pipeline_types.text_span list;
  smt_text : string;
  smt_spans_ordered : Pipeline_types.text_span list;
  vc_ids_ordered : int list;
  vc_locs : (int * Loc.loc) list;
  vc_locs_ordered : Loc.loc list;
  goals : Pipeline_types.goal_info list;
  proof_traces : Pipeline_types.proof_trace list;
}

val run :
  cfg:Pipeline_types.config ->
  instrumentation:Ir.node_ir list ->
  (run_output, Pipeline_types.error) result
