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

(** Neutral contract for submitting generated WhyML to a proof backend.

    The payload contains no Kairos IR and no Why3 value. WhyML is the stable ownership boundary:
    Kairos generates it, while a Why3 adapter parses it and produces backend-neutral textual
    obligations. *)

type request = { protocol_version : Tool_protocol.version; filename : string; whyml_text : string }
[@@deriving yojson]

type response = { protocol_version : Tool_protocol.version; vc_text : string; smt_text : string }
[@@deriving yojson]

val make_request : ?filename:string -> whyml_text:string -> unit -> request
val validate_request : request -> (unit, string) result
val make_response : vc_text:string -> smt_text:string -> response
val validate_response : response -> (unit, string) result
