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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3

let normalize_label (label:string) : string =
  let prefix = "Transition lemmas (" in
  if label = "User contract" then
    "user"
  else if label = "User contracts coherency" || label = "User constract coherency" then
    "coherency"
  else if String.length label >= String.length prefix
     && String.sub label 0 (String.length prefix) = prefix then
    "Transition lemmas"
  else if label = "" then
    "Other"
  else
    label

let sanitize_label (label:string) : string =
  let b = Buffer.create (String.length label) in
  String.iter
    (fun c ->
       if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') then
         Buffer.add_char b (Char.lowercase_ascii c)
       else
         Buffer.add_char b '_')
    label;
  Buffer.contents b

let attr_string (label:string) : string =
  "origin:" ^ sanitize_label (normalize_label label)

let attr_for_label (label:string) : Ident.attribute =
  Ident.create_attribute (attr_string label)

let known_labels : string list =
  [
    "user";
    "coherency";
    "Compatibility";
    "Monitor";
    "Internal";
    "Transition requires";
    "Contract requires";
    "Lemmas (pre)";
    "Atoms";
    "User invariants";
    "Instance links (pre)";
    "Initialization/first_step";
    "Internal links";
    "Transition lemmas";
    "Lemmas";
    "Contract ensures";
    "Instance links (post)";
    "Instance invariants";
    "pre_k history";
    "Result";
    "Bad state";
    "Other";
  ]

let label_attrs : (string * Ident.attribute) list =
  List.map (fun lbl -> (lbl, attr_for_label lbl)) known_labels

let label_of_attrs (attrs:Ident.Sattr.t) : string option =
  List.find_map
    (fun (label, attr) -> if Ident.Sattr.mem attr attrs then Some label else None)
    label_attrs
