(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Uniform facts produced by one auxiliary product-invariant analysis. *)

type t

val of_reachability : Kr_verification_reachability.t -> t
val of_characteristics : Kr_verification_characteristics.t -> t

val entry_facts :
  t list ->
  Kr_verification_ir.product_state ->
  (string * Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list) list

val preservation_facts :
  t list ->
  node:Kr_domain_core_syntax.historical Kr_verification_ir.node_ir ->
  Kr_domain_core_syntax.historical Kr_verification_ir.product_step_summary ->
  (string * Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list) list
