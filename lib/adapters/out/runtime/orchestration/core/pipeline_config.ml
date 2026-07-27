(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type proof_encoding = Explicit_product

let string_of_proof_encoding = function Explicit_product -> "explicit-product"

let proof_encoding_of_string = function
  | "explicit-product" -> Some Explicit_product
  | _ -> None

let default_proof_encoding = Explicit_product

type verification_optimizations = {
  group_public_non_w_guarantees : bool;
}

type why3_optimizations = { group_product_steps : bool }

type proof_optimizations = {
  verification : verification_optimizations;
  why3 : why3_optimizations;
}

let reference_proof_optimizations =
  {
    verification = { group_public_non_w_guarantees = false };
    why3 = { group_product_steps = false };
  }

let default_proof_optimizations =
  {
    verification = { group_public_non_w_guarantees = true };
    why3 = { group_product_steps = true };
  }

type config = {
  input_file : string;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  compute_proof_diagnostics : bool;
  prove : bool;
  proof_jobs : int;
  generate_why_text : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_dot_png : bool;
  dump_failed_smt : bool;
  collect_ir_metrics : bool;
  proof_progress_path : string option;
  stop_on_first_nonvalid : bool;
  proof_encoding : proof_encoding;
  proof_optimizations : proof_optimizations;
}
