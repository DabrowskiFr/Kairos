open Ast

let escape_dot s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '\\' -> Buffer.add_string b "\\\\"
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let escape_dot_label s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let all_valuations names =
  let rec aux acc = function
    | [] -> [List.rev acc]
    | n :: rest ->
        let t = aux ((n, true) :: acc) rest in
        let f = aux ((n, false) :: acc) rest in
        t @ f
  in
  aux [] names

let valuation_label vals =
  vals
  |> List.map (fun (n,b) -> n ^ "=" ^ (if b then "1" else "0"))
  |> String.concat ","

type term = (string * bool option) list

let lookup_val vals name =
  match List.assoc_opt name vals with
  | Some b -> b
  | None -> false

let term_of_vals atom_names vals =
  List.map (fun name -> (name, Some (lookup_val vals name))) atom_names

let can_merge_terms t1 t2 =
  let diff = ref 0 in
  let rec loop = function
    | [], [] -> !diff = 1
    | (_, v1) :: r1, (_, v2) :: r2 ->
        begin match v1, v2 with
        | Some b1, Some b2 when b1 = b2 -> loop (r1, r2)
        | Some _, Some _ ->
            incr diff;
            !diff <= 1 && loop (r1, r2)
        | None, None -> loop (r1, r2)
        | None, Some _ | Some _, None -> false
        end
    | _ -> false
  in
  loop (t1, t2)

let merge_terms t1 t2 =
  List.map2
    (fun (n1, v1) (_n2, v2) ->
       let v =
         match v1, v2 with
         | Some b1, Some b2 when b1 = b2 -> Some b1
         | Some _, Some _ -> None
         | None, None -> None
         | None, Some b | Some b, None -> Some b
       in
       (n1, v))
    t1 t2

let uniq_terms terms =
  let rec loop acc = function
    | [] -> List.rev acc
    | t :: rest -> if List.exists ((=) t) acc then loop acc rest else loop (t :: acc) rest
  in
  loop [] terms

let prime_implicants terms =
  let rec loop terms primes =
    let terms = uniq_terms terms in
    let n = List.length terms in
    let used = Array.make n false in
    let merged = ref [] in
    for i = 0 to n - 1 do
      for j = i + 1 to n - 1 do
        let ti = List.nth terms i in
        let tj = List.nth terms j in
        if can_merge_terms ti tj then (
          used.(i) <- true;
          used.(j) <- true;
          merged := merge_terms ti tj :: !merged
        )
      done
    done;
    let new_primes =
      List.fold_left
        (fun acc (i, t) -> if used.(i) then acc else t :: acc)
        primes
        (List.mapi (fun i t -> (i, t)) terms)
    in
    if !merged = [] then uniq_terms new_primes
    else loop !merged new_primes
  in
  loop terms []

let term_covers term vals =
  List.for_all
    (fun (name, v) ->
       match v with
       | None -> true
       | Some b -> lookup_val vals name = b)
    term

let choose_implicants atom_names vals_list =
  if vals_list = [] then []
  else
    let minterms = List.map (term_of_vals atom_names) vals_list in
    let primes = prime_implicants minterms in
    let remaining = ref vals_list in
    let chosen = ref [] in
    let cover_count term =
      List.fold_left
        (fun acc vals -> if term_covers term vals then acc + 1 else acc)
        0
        !remaining
    in
    let rec loop () =
      let unique_cover =
        List.find_map
          (fun vals ->
             let covering = List.filter (fun t -> term_covers t vals) primes in
             match covering with
             | [t] -> Some t
             | _ -> None)
          !remaining
      in
      begin match unique_cover with
      | Some t ->
          if not (List.exists ((=) t) !chosen) then chosen := t :: !chosen;
          remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
          if !remaining <> [] then loop ()
      | None ->
          if !remaining <> [] then (
            let t =
              List.fold_left
                (fun best cand ->
                   if cover_count cand > cover_count best then cand else best)
                (List.hd primes)
                primes
            in
            if not (List.exists ((=) t) !chosen) then chosen := t :: !chosen;
            remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
            if !remaining <> [] then loop ()
          )
      end
    in
    loop ();
    uniq_terms !chosen

let term_to_string term =
  let parts =
    List.filter_map
      (fun (name, v) ->
         match v with
         | None -> None
         | Some true -> Some name
         | Some false -> Some ("not " ^ name))
      term
  in
  match parts with
  | [] -> "true"
  | _ -> String.concat " && " parts

let valuations_to_formula atom_names vals_list =
  match vals_list with
  | [] -> "false"
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) implicants then
        "true"
      else
        let parts = List.map term_to_string implicants in
        match parts with
        | [] -> "false"
        | [p] -> p
        | _ -> String.concat " || " parts

let term_to_iexpr term =
  let parts =
    List.filter_map
      (fun (name, v) ->
         match v with
         | None -> None
         | Some true -> Some (IVar name)
         | Some false -> Some (IUn (Not, IVar name)))
      term
  in
  match parts with
  | [] -> ILitBool true
  | [p] -> p
  | p :: rest -> List.fold_left (fun acc x -> IBin (And, acc, x)) p rest

let terms_to_iexpr terms =
  match terms with
  | [] -> ILitBool false
  | _ ->
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) terms then
        ILitBool true
      else
        let parts = List.map term_to_iexpr terms in
        match parts with
        | [] -> ILitBool false
        | [p] -> p
        | p :: rest -> List.fold_left (fun acc x -> IBin (Or, acc, x)) p rest

let valuations_to_iexpr atom_names vals_list =
  match vals_list with
  | [] -> ILitBool false
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      terms_to_iexpr implicants

let rec nnf_ltl ?(neg=false) f =
  match f with
  | LTrue -> if neg then LFalse else LTrue
  | LFalse -> if neg then LTrue else LFalse
  | LAtom a -> if neg then LNot (LAtom a) else LAtom a
  | LNot a -> nnf_ltl ~neg:(not neg) a
  | LAnd (a,b) ->
      if neg then LOr (nnf_ltl ~neg:true a, nnf_ltl ~neg:true b)
      else LAnd (nnf_ltl a, nnf_ltl b)
  | LOr (a,b) ->
      if neg then LAnd (nnf_ltl ~neg:true a, nnf_ltl ~neg:true b)
      else LOr (nnf_ltl a, nnf_ltl b)
  | LImp (a,b) ->
      nnf_ltl ~neg (LOr (LNot a, b))
  | LX a ->
      if neg then LX (nnf_ltl ~neg:true a) else LX (nnf_ltl a)
  | LG a ->
      if neg then
        let msg =
          "NNF: negation above G not supported in G/X fragment: not G("
          ^ Whygen_support.string_of_ltl a ^ ")"
        in
        failwith msg
      else
        LG (nnf_ltl a)

let rec simplify_ltl f =
  match f with
  | LAnd _ ->
      let rec flatten acc = function
        | LAnd (x,y) -> flatten (flatten acc x) y
        | LTrue -> acc
        | LFalse -> LFalse :: acc
        | x -> x :: acc
      in
      let parts = flatten [] f |> List.map simplify_ltl in
      if List.exists ((=) LFalse) parts then LFalse
      else
        let parts = List.filter (fun x -> x <> LTrue) parts in
        let parts =
          List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] parts
          |> List.rev
        in
        begin match parts with
        | [] -> LTrue
        | [x] -> x
        | x :: xs -> List.fold_left (fun acc y -> LAnd (acc, y)) x xs
        end
  | LOr _ ->
      let rec flatten acc = function
        | LOr (x,y) -> flatten (flatten acc x) y
        | LFalse -> acc
        | LTrue -> LTrue :: acc
        | x -> x :: acc
      in
      let parts = flatten [] f |> List.map simplify_ltl in
      if List.exists ((=) LTrue) parts then LTrue
      else
        let parts = List.filter (fun x -> x <> LFalse) parts in
        let parts =
          List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] parts
          |> List.rev
        in
        begin match parts with
        | [] -> LFalse
        | [x] -> x
        | x :: xs -> List.fold_left (fun acc y -> LOr (acc, y)) x xs
        end
  | LImp (a,b) ->
      simplify_ltl (LOr (LNot a, b))
  | LNot a ->
      let a = simplify_ltl a in
      begin match a with
      | LTrue -> LFalse
      | LFalse -> LTrue
      | _ -> LNot a
      end
  | LG a -> LG (simplify_ltl a)
  | LX a -> LX (simplify_ltl a)
  | _ -> f

let eval_atom _atom_map vals = function
  | FRel (HNow (IVar name), REq, HNow (ILitBool true)) ->
      lookup_val vals name
  | _ -> false

let rec eval_ltl atom_map vals f =
  match f with
  | LTrue -> true
  | LFalse -> false
  | LAtom a -> eval_atom atom_map vals a
  | LNot a -> not (eval_ltl atom_map vals a)
  | LAnd (a,b) -> eval_ltl atom_map vals a && eval_ltl atom_map vals b
  | LOr (a,b) -> eval_ltl atom_map vals a || eval_ltl atom_map vals b
  | LImp (a,b) -> (not (eval_ltl atom_map vals a)) || eval_ltl atom_map vals b
  | LX _ -> true
  | LG a -> eval_ltl atom_map vals a

let rec progress_ltl atom_map vals f =
  let f =
    match f with
    | LTrue | LFalse -> f
    | LAtom a -> if eval_atom atom_map vals a then LTrue else LFalse
    | LNot a -> LNot (progress_ltl atom_map vals a)
    | LAnd (a,b) -> LAnd (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LOr (a,b) -> LOr (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LImp (a,b) -> LImp (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LX a -> a
    | LG a ->
        let a_now = progress_ltl atom_map vals a in
        LAnd (a_now, LG a)
  in
  simplify_ltl f

type residual_state = ltl

type residual_transition = int * (string * bool) list * int

let build_residual_graph atom_map valuations f0 =
  let f0 = nnf_ltl f0 |> simplify_ltl in
  let tbl = Hashtbl.create 16 in
  let states = ref [] in
  let transitions = ref [] in
  let add_state f =
    let key = Whygen_support.string_of_ltl f in
    match Hashtbl.find_opt tbl key with
    | Some i -> (i, false)
    | None ->
        let i = List.length !states in
        states := !states @ [f];
        Hashtbl.add tbl key i;
        (i, true)
  in
  let q = Queue.create () in
  let _ = add_state f0 in
  Queue.add f0 q;
  while not (Queue.is_empty q) do
    let f = Queue.take q in
    let i = Hashtbl.find tbl (Whygen_support.string_of_ltl f) in
    List.iter
      (fun vals ->
         let f' = progress_ltl atom_map vals f in
         let (j, is_new) = add_state f' in
         transitions := (i, vals, j) :: !transitions;
         if is_new then Queue.add f' q)
      valuations
  done;
  (!states, List.rev !transitions)

let minimize_residual_graph valuations states transitions =
  let n_states = List.length states in
  let val_index =
    let tbl = Hashtbl.create 16 in
    List.iteri (fun i v -> Hashtbl.add tbl (valuation_label v) i) valuations;
    tbl
  in
  let n_inputs = List.length valuations in
  let delta = Array.make_matrix n_states n_inputs 0 in
  List.iter
    (fun (i, vals, j) ->
       let key = valuation_label vals in
       match Hashtbl.find_opt val_index key with
       | Some k -> delta.(i).(k) <- j
       | None -> ())
    transitions;
  let is_accept i =
    match List.nth states i with
    | LFalse -> false
    | _ -> true
  in
  let class_of = Array.make n_states 0 in
  for i = 0 to n_states - 1 do
    class_of.(i) <- if is_accept i then 1 else 0
  done;
  let rec refine () =
    let table = Hashtbl.create n_states in
    let next_class = Array.make n_states 0 in
    let next_id = ref 0 in
    for i = 0 to n_states - 1 do
      let buf = Buffer.create 32 in
      Buffer.add_string buf (if is_accept i then "1|" else "0|");
      for k = 0 to n_inputs - 1 do
        Buffer.add_string buf (string_of_int class_of.(delta.(i).(k)));
        Buffer.add_char buf ','
      done;
      let key = Buffer.contents buf in
      match Hashtbl.find_opt table key with
      | Some id -> next_class.(i) <- id
      | None ->
          let id = !next_id in
          incr next_id;
          Hashtbl.add table key id;
          next_class.(i) <- id
    done;
    let changed = ref false in
    for i = 0 to n_states - 1 do
      if next_class.(i) <> class_of.(i) then changed := true
    done;
    Array.blit next_class 0 class_of 0 n_states;
    if !changed then refine () else ()
  in
  refine ();
  let class_count =
    Array.fold_left (fun acc x -> max acc (x + 1)) 0 class_of
  in
  let rep = Array.make class_count (-1) in
  for i = 0 to n_states - 1 do
    let c = class_of.(i) in
    if rep.(c) = -1 then rep.(c) <- i
  done;
  let new_states =
    List.init class_count (fun c -> List.nth states rep.(c))
  in
  let new_transitions = ref [] in
  for c = 0 to class_count - 1 do
    let s = rep.(c) in
    for k = 0 to n_inputs - 1 do
      let t = delta.(s).(k) in
      let c' = class_of.(t) in
      let vals = List.nth valuations k in
      new_transitions := (c, vals, c') :: !new_transitions
    done
  done;
  (new_states, List.rev !new_transitions)
