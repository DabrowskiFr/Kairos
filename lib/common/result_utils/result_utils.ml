let ( let* ) = Result.bind

let find_assoc ~missing key xs =
  match List.assoc_opt key xs with
  | Some value -> Ok value
  | None -> Error (missing key)

let rec all = function
  | [] -> Ok []
  | x :: xs ->
      let* x = x in
      let* xs = all xs in
      Ok (x :: xs)

let rec map4 ~length_mismatch f xs ys zs ws =
  match (xs, ys, zs, ws) with
  | [], [], [], [] -> Ok []
  | x :: xs, y :: ys, z :: zs, w :: ws ->
      let* x = f x y z w in
      let* xs = map4 ~length_mismatch f xs ys zs ws in
      Ok (x :: xs)
  | _ -> Error length_mismatch
