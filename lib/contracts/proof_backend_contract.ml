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

type optimization_policy = {
  share_facts : bool;
  simplify_formulas : bool;
  slice_transition_bodies : bool;
  simplify_runtime_actions : bool;
  deduplicate_terms : bool;
  group_product_steps : bool;
  product_step_group_max_cost : int;
}

type request = {
  protocol_version : Tool_protocol.version;
  nodes : Ir.node_ir list;
  optimizations : optimization_policy;
}

type obligations_outputs = {
  vc_text : string;
  smt_text : string;
}

let make_request ~nodes ~optimizations =
  { protocol_version = Tool_protocol.current_version; nodes; optimizations }

let validate_request (request : request) =
  match Tool_protocol.validate ~component:"proof backend request" request.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      if request.optimizations.product_step_group_max_cost < 0 then
        Error "proof backend request has a negative product-step group cost"
      else Ok ()
