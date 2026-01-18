


### Requires 

(* contract requires (node) *)

step >= 1 -> Mon0 -> y = in_prev_x
Mon1 -> y = in_prev_x
Mon2 -> False

(* contrats utilisateur *)
Run -> y = pre_in_x x (x (t-1)) 

(* atomes * )
y_pre_old = y = pre_old_x (x(t-2))

(* compatibility (possitble automaton state) *)

Init -> Mon0
Run -> Mon1 \/ Mon2

(* initialisation first/step *)

first_step -> Init 

### Ensures 

