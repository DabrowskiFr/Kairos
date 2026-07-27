(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t =
  | Parse_error of string
  | Elaboration_error of string
  | Type_error of string
  | Well_formedness_error of string
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string
  | Internal_error of string

let to_string = function
  | Parse_error msg -> msg
  | Elaboration_error msg -> msg
  | Type_error msg -> msg
  | Well_formedness_error msg -> msg
  | Flow_error msg -> msg
  | Why3_error msg -> msg
  | Prove_error msg -> msg
  | Io_error msg -> msg
  | Internal_error msg -> msg
