(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

type entry = Why_compile_product_group_boundary.entry

type individual_reason =
  | Grouping_disabled
  | Empty_group
  | Singleton_group
  | Non_safe_step
  | Has_local_cuts
  | Split_singleton

type decision =
  | Groupable
  | Individual of individual_reason

let individual_reason_name = function
  | Grouping_disabled -> "grouping_disabled"
  | Empty_group -> "empty_group"
  | Singleton_group -> "singleton_group"
  | Non_safe_step -> "non_safe_step"
  | Has_local_cuts -> "has_local_cuts"
  | Split_singleton -> "split_singleton"

let group_is_safe = function
  | [] -> false
  | (_i, (sc : Why_contracts.step_contract_info), _t) :: _ ->
      sc.step.step_class = Why_runtime_view.StepSafe

let has_local_cuts entries =
  List.exists
    (fun (_i, (sc : Why_contracts.step_contract_info), _t) ->
      sc.local_cuts <> [])
    entries

let decide_group ~(group_why3_product_steps : bool) entries =
  if not group_why3_product_steps then Individual Grouping_disabled
  else
    match entries with
    | [] -> Individual Empty_group
    | [ _ ] -> Individual Singleton_group
    | _ when not (group_is_safe entries) -> Individual Non_safe_step
    | _ when has_local_cuts entries -> Individual Has_local_cuts
    | _ -> Groupable
