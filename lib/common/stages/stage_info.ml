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

type parse_error = { loc : Ast.loc option; message : string }

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

type monitor_generation_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

type contracts_info = {
  contract_origin_map : (int * Ast.origin option) list;
  warnings : string list;
}

type monitor_info = { monitor_state_ctors : string list; atom_count : int; warnings : string list }

type obc_info = {
  ghost_locals_added : string list;
  pre_k_infos : string list list;
  warnings : string list;
}

let empty_parse_info : parse_info =
  { source_path = None; text_hash = None; parse_errors = []; warnings = [] }

let empty_monitor_generation_info : monitor_generation_info =
  { residual_state_count = 0; residual_edge_count = 0; warnings = [] }

let empty_contracts_info : contracts_info = { contract_origin_map = []; warnings = [] }
let empty_monitor_info : monitor_info = { monitor_state_ctors = []; atom_count = 0; warnings = [] }
let empty_obc_info : obc_info = { ghost_locals_added = []; pre_k_infos = []; warnings = [] }
