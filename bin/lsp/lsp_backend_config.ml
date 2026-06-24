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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let pipeline_config_of_protocol
    (cfg : Lsp_protocol.config) :
    Pipeline_types.config =
  {
    input_file = cfg.input_file;
    wp_only = cfg.wp_only;
    smoke_tests = cfg.smoke_tests;
    timeout_s = cfg.timeout_s;
    compute_proof_diagnostics = cfg.compute_proof_diagnostics;
    prove = cfg.prove;
    proof_jobs = cfg.proof_jobs;
    generate_why_text = not cfg.prove;
    generate_vc_text = cfg.generate_vc_text;
    generate_smt_text = cfg.generate_smt_text;
    generate_dot_png = cfg.generate_dot_png;
    dump_failed_smt = false;
    collect_ir_metrics = false;
    proof_progress_path = None;
    stop_on_first_nonvalid = false;
    proof_encoding = Pipeline_types.default_proof_encoding;
    proof_optimizations = Pipeline_types.default_proof_optimizations;
  }
