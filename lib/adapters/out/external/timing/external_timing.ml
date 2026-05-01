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

type snapshot = {
  spot_s : float;
  spot_calls : int;
  z3_s : float;
  z3_calls : int;
  product_s : float;
  canonical_s : float;
  why_gen_s : float;
  vc_smt_s : float;
}

let spot_s = ref 0.0
let spot_calls = ref 0
let z3_s = ref 0.0
let z3_calls = ref 0
let product_s = ref 0.0
let canonical_s = ref 0.0
let why_gen_s = ref 0.0
let vc_smt_s = ref 0.0

let reset () =
  spot_s := 0.0;
  spot_calls := 0;
  z3_s := 0.0;
  z3_calls := 0;
  product_s := 0.0;
  canonical_s := 0.0;
  why_gen_s := 0.0;
  vc_smt_s := 0.0

let snapshot () : snapshot =
  {
    spot_s = !spot_s;
    spot_calls = !spot_calls;
    z3_s = !z3_s;
    z3_calls = !z3_calls;
    product_s = !product_s;
    canonical_s = !canonical_s;
    why_gen_s = !why_gen_s;
    vc_smt_s = !vc_smt_s;
  }

let diff ~before ~(after_ : snapshot) : snapshot =
  {
    spot_s = max 0.0 (after_.spot_s -. before.spot_s);
    spot_calls = max 0 (after_.spot_calls - before.spot_calls);
    z3_s = max 0.0 (after_.z3_s -. before.z3_s);
    z3_calls = max 0 (after_.z3_calls - before.z3_calls);
    product_s = max 0.0 (after_.product_s -. before.product_s);
    canonical_s = max 0.0 (after_.canonical_s -. before.canonical_s);
    why_gen_s = max 0.0 (after_.why_gen_s -. before.why_gen_s);
    vc_smt_s = max 0.0 (after_.vc_smt_s -. before.vc_smt_s);
  }

let record_spot ~elapsed_s =
  incr spot_calls;
  spot_s := !spot_s +. max 0.0 elapsed_s

let record_z3 ~elapsed_s =
  incr z3_calls;
  z3_s := !z3_s +. max 0.0 elapsed_s

let record_product ~elapsed_s = product_s := !product_s +. max 0.0 elapsed_s

let record_canonical ~elapsed_s = canonical_s := !canonical_s +. max 0.0 elapsed_s

let record_why_gen ~elapsed_s = why_gen_s := !why_gen_s +. max 0.0 elapsed_s

let record_vc_smt ~elapsed_s = vc_smt_s := !vc_smt_s +. max 0.0 elapsed_s
