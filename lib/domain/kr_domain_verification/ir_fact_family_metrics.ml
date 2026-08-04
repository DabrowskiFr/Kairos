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
  pass_name : string;
  family_name : string;
  candidate_count : int;
  inserted_count : int;
  unique_candidate_count : int;
  unique_inserted_count : int;
}

type observer = snapshot -> unit

type bucket = {
  pass_name : string;
  family_name : string;
  mutable candidate_count : int;
  mutable inserted_count : int;
  mutable candidates : Core_syntax.historical Core_syntax.hexpr list;
  mutable inserted : Core_syntax.historical Core_syntax.hexpr list;
}

type collector = (string, bucket) Hashtbl.t

let create () = Hashtbl.create 16

let key ~pass_name ~family_name = pass_name ^ "\000" ^ family_name

let bucket tbl ~pass_name ~family_name =
  let key = key ~pass_name ~family_name in
  match Hashtbl.find_opt tbl key with
  | Some bucket -> bucket
  | None ->
      let bucket =
        {
          pass_name;
          family_name;
          candidate_count = 0;
          inserted_count = 0;
          candidates = [];
          inserted = [];
        }
      in
      Hashtbl.add tbl key bucket;
      bucket

let add tbl ~pass_name ~family_name ~candidates ~inserted =
  let bucket = bucket tbl ~pass_name ~family_name in
  bucket.candidate_count <- bucket.candidate_count + List.length candidates;
  bucket.inserted_count <- bucket.inserted_count + List.length inserted;
  bucket.candidates <- List.rev_append candidates bucket.candidates;
  bucket.inserted <- List.rev_append inserted bucket.inserted

let unique_count formulas =
  List.length (List.sort_uniq Stdlib.compare formulas)

let snapshot_of_bucket bucket =
  {
    pass_name = bucket.pass_name;
    family_name = bucket.family_name;
    candidate_count = bucket.candidate_count;
    inserted_count = bucket.inserted_count;
    unique_candidate_count = unique_count bucket.candidates;
    unique_inserted_count = unique_count bucket.inserted;
  }

let emit tbl observer =
  tbl
  |> Hashtbl.to_seq_values
  |> List.of_seq
  |> List.sort (fun left right ->
         match String.compare left.pass_name right.pass_name with
         | 0 -> String.compare left.family_name right.family_name
         | n -> n)
  |> List.iter (fun bucket -> observer (snapshot_of_bucket bucket))
