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

(* Parsed CLI arguments *)
module Pipeline = Kairos_engine.Api.Contract

type cli_args = {
  file : string;
  check_frontend : bool;
  prove : bool;
  timeout_s : int;
  proof_jobs : int;
  proof_encoding : Pipeline.proof_encoding;
  stop_on_first_nonvalid : bool;
  no_proof_optimizations : bool;
  no_proof_grouping : bool;
  no_why3_product_step_grouping : bool;
  dump_automata : string option;
  dump_automata_short : string option;
  dump_product : string option;
  dump_canonical : string option;
  dump_canonical_short : string option;
  dump_obligations_map : string option;
  dump_surface : string option;
  dump_elaborated : string option;
  dump_normalized_program : string option;
  dump_ir_pretty : string option;
  dump_cost_report : string option;
  emit_c : string option;
  dump_timings : string option;
  dump_goals : string option;
  dump_failed_smt : bool;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
}

(* Mutually exclusive dump modes. Each one corresponds to a single "artifact export"
   branch and bypasses the general run/prove flow. *)
type dump_mode =
  | Dump_product of { out : string }
  | Dump_automata of { out : string; short : bool }
  | Dump_canonical of { out : string; short : bool }
  | Dump_obligations_map of { out : string }
  | Dump_surface of { out : string }
  | Dump_elaborated of { out : string }
  | Dump_normalized_program of { out : string }
  | Dump_ir_pretty of { out : string }
  | Dump_cost_report of { out : string }
  | Emit_c of { out_dir : string }

(* Resolved action chosen after validation. This keeps execution code small and
   avoids mixing parsing concerns with backend dispatch. *)
type action =
  | Dump of dump_mode
  | Dump_why of { out : string }
  | Dump_why3_vc of { out : string }
  | Dump_smt2 of { out : string }
  | Check_frontend
  | Run of { prove : bool }
