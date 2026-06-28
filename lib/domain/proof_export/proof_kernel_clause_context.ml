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

module K = Kernel_clause_projection
module PT = Product_types
open Proof_kernel_types

let product_state_to_kernel (st : product_state_ir) : K.product_state_anchor =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state_index;
    guarantee_state_index = st.guarantee_state_index;
  }

let product_state_of_kernel (st : K.product_state_anchor) : product_state_ir =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state_index;
    guarantee_state_index = st.guarantee_state_index;
  }

let product_step_class_to_kernel = function
  | StepSafe -> K.StepSafe
  | StepBadAssumption -> K.StepBadAssumption
  | StepBadGuarantee -> K.StepBadGuarantee

let product_step_class_of_kernel = function
  | K.StepSafe -> StepSafe
  | K.StepBadAssumption -> StepBadAssumption
  | K.StepBadGuarantee -> StepBadGuarantee

let product_step_to_kernel (step : product_step_ir) : K.product_step =
  let step_anchor : K.product_step_anchor =
    {
      K.psta_src = product_state_to_kernel step.src;
      psta_dst = product_state_to_kernel step.dst;
      psta_transition_id = step.program_transition_id;
    }
  in
  {
    K.step_anchor;
    program_guard = step.program_guard;
    assume_guard = step.assume_edge.guard;
    guarantee_guard = step.guarantee_edge.guard;
    step_class = product_step_class_to_kernel step.step_kind;
  }

let product_step_of_kernel (step : K.product_step) : product_step_ir =
  let step_anchor = K.product_step_anchor step in
  let src = product_state_of_kernel step_anchor.K.psta_src in
  let dst = product_state_of_kernel step_anchor.K.psta_dst in
  {
    src;
    dst;
    program_transition_id = step_anchor.K.psta_transition_id;
    program_transition = (src.prog_state, dst.prog_state);
    program_guard = step.K.program_guard;
    assume_edge =
      {
        src_index = src.assume_state_index;
        dst_index = dst.assume_state_index;
        guard = step.K.assume_guard;
      };
    guarantee_edge =
      {
        src_index = src.guarantee_state_index;
        dst_index = dst.guarantee_state_index;
        guard = step.K.guarantee_guard;
      };
    step_kind = product_step_class_of_kernel step.K.step_class;
    step_origin = StepFromExplicitExploration;
  }

let product_state_to_product_types (st : K.product_state_anchor) : PT.product_state =
  {
    PT.prog_state = st.prog_state;
    assume_state = st.assume_state_index;
    guarantee_state = st.guarantee_state_index;
  }

let same_product_state (left : K.product_state_anchor) (right : product_state_ir) =
  String.equal left.prog_state right.prog_state
  && left.assume_state_index = right.assume_state_index
  && left.guarantee_state_index = right.guarantee_state_index

let same_product_step (left : K.product_step) (right : product_step_ir) =
  let anchor = K.product_step_anchor left in
  same_product_state anchor.K.psta_src right.src
  && same_product_state anchor.K.psta_dst right.dst
  && String.equal anchor.K.psta_transition_id right.program_transition_id
  && left.K.program_guard = right.program_guard
  && left.K.assume_guard = right.assume_edge.guard
  && left.K.guarantee_guard = right.guarantee_edge.guard
  && product_step_class_of_kernel left.K.step_class = right.step_kind
