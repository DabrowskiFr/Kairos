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

(** C99 code generation for executable Kairos node models.

    This backend emits portable C only. Board support, pin mapping, sensor drivers, and PlatformIO
    project files belong to the external embedded packaging layer. *)

type generated_file = { file_name : string; contents : string }

val emit_program :
  ?header_name:string -> Verification_model.program_model -> (generated_file list, string) result
(** Emit [kairos_generated.h] and [kairos_generated.c] by default. The input program is expected to
    be the normalized frontend model, so source-order transition priority and implicit skip
    transitions are already reflected in the node steps. *)
