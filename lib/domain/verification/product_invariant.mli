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

val of_reachability : Product_reachability.t -> t
val of_characteristics : Product_characteristics.t -> t

val entry_facts :
  t list ->
  Ir.product_state ->
  (string * Core_syntax.historical Core_syntax.hexpr list) list

val preservation_facts :
  t list ->
  node:Core_syntax.historical Ir.node_ir ->
  Core_syntax.historical Ir.product_step_summary ->
  (string * Core_syntax.historical Core_syntax.hexpr list) list
