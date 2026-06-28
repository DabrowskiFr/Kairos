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

module PK = Proof_kernel_types
module K = Kernel_clause_projection

let clause_family_string =
  Obligation_family_projection.stable_name

let phase_string = function
  | K.CurrentTick -> "current_tick"
  | K.PreviousTick -> "previous_tick"
  | K.StepTickContext -> "step_tick_context"

let step_kind_string = function
  | PK.StepSafe -> "safe"
  | PK.StepBadAssumption -> "bad_assumption"
  | PK.StepBadGuarantee -> "bad_guarantee"

let string_of_product_state (st : PK.product_state_ir) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let origin_for_node node_name suffix = node_name ^ "." ^ suffix
