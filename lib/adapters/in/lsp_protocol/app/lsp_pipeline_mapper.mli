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

(** Map application pipeline records to public LSP protocol records. *)

val map_outputs : Kairos_engine.Api.Types.outputs -> Lsp_protocol.outputs

val map_automata :
  Kairos_engine.Api.Types.automata_outputs -> Lsp_protocol.automata_outputs

val map_why : Kairos_engine.Api.Types.why_outputs -> Lsp_protocol.why_outputs

val map_oblig :
  Kairos_engine.Api.Types.obligations_outputs ->
  Lsp_protocol.obligations_outputs
