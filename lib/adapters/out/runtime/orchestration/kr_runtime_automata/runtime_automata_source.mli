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

(** External automata production for the runtime verification pipeline.

    This module is outside [kr_runtime_core] on purpose. The reference
    pipeline consumes supplied automata; this adapter decides how those
    automata are produced today. Its production path is not part of the Rocq
    correction kernel. *)

type produced = {
  automata : (Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list;
  automata_info : Kr_engine.Kr_engine_flow_info.automata_info;
}

val produce_with_spot :
  Kr_verification_cases.t ->
  (produced, Kr_engine.Kr_engine_pipeline_error.t) result
