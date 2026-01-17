## Toggle 

### Code 

node toggle01() returns (y: int)
guarantee {y} = {0};
guarantee G( {y} = {0} => X( {y} = {1} ) );
guarantee G( {y} = {1} => X( X( {y} = {1} ) ) );
  Init -> Run {
    prev := 1;
    y := 0;
  }
  Run -> Run {
    prev := y;
    y := 1 - prev;
  }
end

### Construction du moniteur 

Formule LTL : G (y = 0 -> X (y = 1))

#### Calcul des résiduels

G phi   phi = P -> X Q    P = y = 0 et Q = y = 1

R = empty
Worklist = G phi 

progr(G phi, sigma) 
    = progr(P -> X Q, sigma) and G phi
    = progr(~ P or X Q, sigma) ang G phi 
    = (progr(~ P, sigma) or progr (X Q, sigma)) and G phi 
    = (progr(~P, sigma) or Q) and G phi
    = 
        - si sigma |- P alors Q and G phi 
        - si sigma |- ~ P alors G phi 

R = G phi, Q and G phi
Worklist = Q and G phi 

progr (Q and G phi, sigma) 
    = progr(Q, sigma) and progr(G phi, sigma)
    = progr(Q, sigma) and (progr(~P, sigma) or Q) and G phi
    =   - si sigma |- ~ Q alors False
        - si sigma |- Q, P alors Q and G phi 
        - si sigma |- Q, ~P alors G phi 

R = G phi, Q and G phi  

#### Calcul des transitions (déterministe)

R = G phi, Q and G phi

- progr(G phi, sigma) 
    =   - si sigma |- P alors Q and G phi 
        - si sigma |- ~ P alors G phi
- progr(Q and G phi) 
    =   - si sigma |- ~ Q alors False
        - si sigma |- Q, P alors Q and G phi 
        - si sigma |- Q, ~P alors G phi

Monitor = ({G phi, Q and G phi}, G Phi, T, False)

G phi -- P --> Q and G phi
G phi -- ~ P --> G phi 
Q and G Phi -- ~Q --> False 
Q and G phi -- Q and P --> Q and G phi
Q and G phi -- Q and ~ P --> G phi

P = {y = 0}   Q = {y = 1}

#### Essai 

garantir 
    (1) une des conditions est vérifiée 
    (2) la transision fausse est impossible

Etat du moniteur = {0, 1, 2}

node toggle01() returns (y: int)
guarantee G({y} = {0} => X( {y} = {1} ));
if mode = init then 
    prev := 1;
    y := 0;
    mode := run
else if mode = run then 
    prev := y;
    y := 1 - prev;
    mode := run
else ()
end
st = 0 -> P -> Q
st = 0 -> ~ P -> ??? 
st = 1 

st = init
    first_step -> st = 0 

    old st = 0 -> y <> 0 -> st = 0    
    old st = 0 -> y = 0 -> st = 1 
    old st = 1 -> y = 1 -> False    (st != 2)
    old st = 1 -> y = 0 -> y = 1 -> st = 1 
    old st = 1 -> y <> 0 -> y = 1 -> st = 0 
st = run 
    old st = 0 -> y <> 0 -> st = 0
    old st = 0 -> y = 0 -> st = 1     
    old st = 1 -> y = 1 -> False    (st != 2)
    old st = 1 -> y = 0 -> y = 1 -> st = 1 
    old st = 1 -> y <> 0 -> y = 1 -> st = 0 