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

type request = { protocol_version : Tool_protocol.version; filename : string; whyml_text : string }
[@@deriving yojson]

type response = { protocol_version : Tool_protocol.version; vc_text : string; smt_text : string }
[@@deriving yojson]

let make_request ?(filename = "<kairos-generated>") ~whyml_text () =
  { protocol_version = Tool_protocol.current_version; filename; whyml_text }

let validate_request (request : request) =
  match Tool_protocol.validate ~component:"proof backend request" request.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      if String.trim request.filename = "" then Error "proof backend request has an empty filename"
      else if String.trim request.whyml_text = "" then
        Error "proof backend request has an empty WhyML payload"
      else Ok ()

let make_response ~vc_text ~smt_text =
  { protocol_version = Tool_protocol.current_version; vc_text; smt_text }

let validate_response (response : response) =
  Tool_protocol.validate ~component:"proof backend response" response.protocol_version
