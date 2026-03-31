# IR Pretty Dump — Format canonique

Ce document fixe un format texte **lisible** mais aussi **fidèle à l'IR**.
Objectif: avoir un dump unique, stable, diff-friendly, sans perte d'information métier.

## 1. Principes

- Représenter les champs IR existants uniquement (pas de reconstruction implicite).
- Afficher explicitement les valeurs vides: `[]`, `None`, `Some(...)`.
- Garder un ordre de sections fixe.
- Garder un ordre déterministe des listes (ordre IR).
- Pour chaque `contract_formula`, afficher:
  - `logic`
  - `meta.origin`
  - `meta.oid`
  - `meta.loc`

## 2. Structure canonique

Pour chaque `node`:

```text
node <name>

signature
source_info
transitions
canonical (product_transitions)
coherency_goals
proof_views
```

### 2.1 `signature`

Correspond à `node.semantics` (et la structure IR associée):

```text
signature
  inputs=[...]
  outputs=[...]
  locals=[...]
  states=[...]
  init=<...>
  instances=[...]
```

### 2.2 `source_info`

```text
source_info
  assumes=[<ltl>...]
  guarantees=[<ltl>...]
  user_invariants=[...]
  state_invariants=[...]
```

### 2.3 `transitions`

Index stable `t0, t1, ...` dans l'ordre de `node.trans`:

```text
t<i>: <src> -> <dst> when <guard|true>
  requires=[contract_formula...]
  ensures =[contract_formula...]
  body=[stmt...]
  warnings=[...]
```

### 2.4 `canonical (product_transitions)`

Index stable `C1, C2, ...` dans l'ordre de `node.product_transitions`.
Style lisible imposé:

```text
Ck @ (<Psrc>,A<a>,G<g>) via t<i>
  identity:
    program_transition_index=<i>
    product_src=(...)
    assume_guard=<fo>
  common:
    requires=[contract_formula...]
    ensures =[contract_formula...]
  safe_summary:
    safe_product_dst=<None|Some(...)>
    safe_guarantee_guard=<None|Some(fo)>
    safe_propagates=[contract_formula...]
    safe_ensures=[contract_formula...]
  cases:
    case[0]:
      step_class=<Safe|Bad_assumption|Bad_guarantee>
      product_dst=(...)
      guarantee_guard=<fo>
      propagates=[contract_formula...]
      ensures=[contract_formula...]
      forbidden=[contract_formula...]
    ...
```

`via t<i>` est une redondance de lecture (déjà présent dans `identity.program_transition_index`) et est conservé pour lisibilité.

### 2.5 `coherency_goals`

```text
coherency_goals=[contract_formula...]
```

### 2.6 `proof_views`

```text
proof_views
  raw=<None|Some(raw_node)>
  annotated=<None|Some(annotated_node)>
  verified=<None|Some(verified_node)>
```

#### `raw_node`

```text
raw:
  core { node_name, inputs, outputs, locals, control_states, init_state, instances }
  pre_k_map=[(hexpr -> pre_k_info)...]
  transitions=[ raw_transition{core, guard} ... ]
  assumes=[ltl...]
  guarantees=[ltl...]
```

#### `annotated_node`

```text
annotated:
  raw=<reference ou inline complet>
  transitions=[ annotated_transition{raw, contracts{requires,ensures}} ... ]
  coherency_goals=[contract_formula...]
  user_invariants=[...]
```

#### `verified_node`

```text
verified:
  core { ... }   // inclut locals étendus (__pre_k*)
  transitions=[ verified_transition{core, guard, pre_k_updates, contracts} ... ]
  product_transitions=[...]
  assumes=[ltl...]
  guarantees=[ltl...]
  coherency_goals=[contract_formula...]
  user_invariants=[...]
```

## 3. Représentation des `contract_formula`

Format obligatoire (sans perte):

```text
{ logic=<ltl>; meta={ origin=<...>; oid=<int>; loc=<...> } }
```

Si un mode "compact" est ajouté plus tard, il doit rester optionnel.

## 4. Convention de nommage

- `t<i>`: index dans `node.trans`.
- `Ck`: index 1-based dans `node.product_transitions`.
- `case[j]`: index 0-based dans `Ck.cases`.

## 5. Exemple minimal de style (extrait)

```text
C3 @ (Run,A0,G1) via t3
  identity:
    program_transition_index=3
    product_src=(Run,A0,G1)
    assume_guard=...
  common:
    requires=[...]
    ensures =[...]
  safe_summary:
    safe_product_dst=Some((Run,A0,G1))
    safe_guarantee_guard=Some(...)
    safe_propagates=[...]
    safe_ensures=[...]
  cases:
    case[0]:
      step_class=Safe
      product_dst=(Run,A0,G1)
      guarantee_guard=...
      propagates=[...]
      ensures=[...]
      forbidden=[]
    case[1]:
      step_class=Bad_guarantee
      product_dst=(Run,A0,G2)
      guarantee_guard=...
      propagates=[]
      ensures=[...]
      forbidden=[...]
```

