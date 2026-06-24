let available_parallelism () =
  try max 1 (Domain.recommended_domain_count ()) with _ -> 1

let default_proof_jobs () =
  match available_parallelism () with
  | n when n <= 2 -> 1
  | n -> n - 1
