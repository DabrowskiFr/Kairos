(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Proof-generation policy and runtime execution configuration. *)

type proof_encoding = Explicit_product

val string_of_proof_encoding : proof_encoding -> string
val proof_encoding_of_string : string -> proof_encoding option
val default_proof_encoding : proof_encoding

type verification_optimizations = {
  group_public_non_w_guarantees : bool;
}

type why3_optimizations = { group_product_steps : bool }

type proof_optimizations = {
  verification : verification_optimizations;
  why3 : why3_optimizations;
}

val reference_proof_optimizations : proof_optimizations
val default_proof_optimizations : proof_optimizations

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
