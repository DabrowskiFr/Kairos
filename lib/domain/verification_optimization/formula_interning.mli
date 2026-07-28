(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Optional physical sharing over the core-owned lowered IR.

    [Preserve_allocations] is the literal identity. [Intern_location_free]
    shares structurally equal formula trees only when neither their root nor
    any descendant carries a source location. Both strategies preserve the
    structural value of the IR. *)

type strategy =
  | Preserve_allocations
  | Intern_location_free

val apply_node :
  strategy:strategy ->
  Core_syntax.history_free Ir.node_ir ->
  Core_syntax.history_free Ir.node_ir

val apply_program :
  strategy:strategy ->
  Ir.program_ir ->
  Ir.program_ir
