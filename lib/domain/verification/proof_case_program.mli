(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Core-owned representation of source nodes and their current proof cases.

    The source program remains the semantic reference. A proof case may only
    rename a source node and select occurrences from its source guarantee list;
    executable declarations, assumptions, transitions, and invariants are
    reconstructed by this module and cannot be changed by an optimization. *)

type proof_case = private {
  source_node_name : Core_syntax.ident;
  guarantee_indices : int list;
  model : Verification_model.node_model;
}

type case_spec = {
  source_node_name : Core_syntax.ident;
  proof_case_node_name : Core_syntax.ident;
  guarantee_indices : int list;
}

type t

val minimal : Verification_model.program_model -> t
(** One unchanged proof case per source node. *)

val source_program : t -> Verification_model.program_model
val cases : t -> proof_case list
val program : t -> Verification_model.program_model

val find_case :
  t ->
  Core_syntax.ident ->
  proof_case option

val rebuild :
  t ->
  case_spec list ->
  (t, string) result
(** Rebuild proof cases from the source program.

    The case names must be unique. For each source node, selected guarantee
    indices must be valid, duplicate-free within a case, and cover every
    source guarantee occurrence at least once across its cases. A source node
    without guarantees must still have exactly one or more cases. *)
