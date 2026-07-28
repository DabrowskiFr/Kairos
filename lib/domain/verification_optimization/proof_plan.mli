(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Optional endomorphisms over the core-owned proof IR.

    [Direct] is the literal identity. [Planned] selects independent,
    obligation-preserving representation strategies. This module owns only
    those algorithms; the input/output representation belongs to
    {!Kairos_verification_obligations.Verification_proof_ir}. *)

type step_strategy =
  | Preserve_individual
  | Group_safe

type condition_strategy =
  | Preserve_occurrences
  | Deduplicate

type formula_strategy =
  | Inline_formulas
  | Share_repeated

type postcondition_strategy =
  | Inline_postconditions
  | Bundle_repeated

type strategy =
  | Direct
  | Planned of {
      steps : step_strategy;
      conditions : condition_strategy;
      formulas : formula_strategy;
      postconditions : postcondition_strategy;
    }

val apply :
  strategy:strategy ->
  Kairos_verification_obligations.Verification_proof_ir.t ->
  (Kairos_verification_obligations.Verification_proof_ir.t, string) result

val apply_program :
  strategy:strategy ->
  Kairos_verification_obligations.Verification_proof_ir.t list ->
  (Kairos_verification_obligations.Verification_proof_ir.t list, string) result
