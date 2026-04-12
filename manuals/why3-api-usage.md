# API Why3 utilisée dans Kairos

Ce document recense les **structures de données** et **fonctions Why3** utilisées dans le dépôt, avec une explication courte de leur rôle.

## Périmètre

Inventaire construit à partir des usages dans :

- `lib/adapters/out/provers/why3/`
- `lib/adapters/out/external/why3/`
- `lib/adapters/out/artifacts/text_render/`

## 1) Configuration, environnement, sélection de prouveur

### `Whyconf`

Types / structures :

- `Whyconf.config` : configuration globale Why3 (drivers, prouveurs, chemins).
- `Whyconf.main` : configuration d’exécution dérivée de `config`.
- `Whyconf.prover` : identifiant d’un prouveur (nom/version/alternatif).
- `Whyconf.config_prover` : entrée de configuration d’un prouveur concret.
- `Whyconf.ProverNotFound` : exception quand aucun prouveur ne matche le filtre.

Fonctions / valeurs :

- `Whyconf.read_config : string option -> Whyconf.config` : lit un fichier de config Why3.
- `Whyconf.init_config : ?extra_config:string list -> string option -> Whyconf.config` : initialise une config par défaut.
- `Whyconf.get_main : Whyconf.config -> Whyconf.main` : extrait `main` depuis `config`.
- `Whyconf.set_main : Whyconf.config -> Whyconf.main -> Whyconf.config` : réinjecte un `main` modifié dans `config`.
- `Whyconf.loadpath : Whyconf.main -> string list` : récupère le loadpath Why3 actif.
- `Whyconf.set_loadpath : Whyconf.main -> string list -> Whyconf.main` : met à jour le loadpath.
- `Whyconf.set_datadir : Whyconf.main -> string -> Whyconf.main` : fixe le datadir Why3 dans `main`.
- `Whyconf.set_libdir : Whyconf.main -> string -> Whyconf.main` : fixe le répertoire des librairies Why3.
- `Whyconf.stdlib_path : string ref` : référence mutable du chemin stdlib utilisé.
- `Whyconf.parse_filter_prover : string -> Whyconf.filter_prover` : parse un filtre textuel de prouveur.
- `Whyconf.filter_prover_with_shortcut : Whyconf.config -> Whyconf.filter_prover -> Whyconf.filter_prover` : applique un filtre avec raccourcis.
- `Whyconf.filter_one_prover : Whyconf.config -> Whyconf.filter_prover -> Whyconf.config_prover` : sélectionne un prouveur unique.
- `Whyconf.get_complete_command : Whyconf.config_prover -> with_steps:bool -> string` : reconstruit la ligne de commande du prouveur.
- `Whyconf.memlimit : Whyconf.main -> int` : limite mémoire configurée.
- `Whyconf.prover.prover_name : string` : champ nom du record `Whyconf.prover`.

### `Env`

- `Env.env` : environnement Why3 de typage/résolution.
- `Env.create_env : Env.filename list -> Env.env` : construit l’environnement à partir du loadpath.

## 2) Typage WhyML et génération des tâches

### `Typing`

- `Typing.type_mlw_file : Env.env -> string list -> string -> Ptree.mlw_file -> Pmodule.pmodule Wstdlib.Mstr.t` : type-check un AST WhyML (`Ptree.mlw_file`) et produit des modules typés.

### `Wstdlib.Mstr`

- `Wstdlib.Mstr.fold : (Wstdlib.Mstr.key -> 'a -> 'b -> 'b) -> 'a Wstdlib.Mstr.t -> 'b -> 'b` : itère sur la map des modules typés.

### `Pmodule`

- `Pmodule.mod_theory` : théorie Why3 associée à un module typé.

### `Task`

Types / structures :

- `Task.task` : obligation élémentaire Why3.

Fonctions :

- `Task.split_theory : Theory.theory -> Decl.Spr.t option -> Task.task -> Task.task list` : découpe une théorie en tâches.
- `Task.task_goal : Task.task -> Decl.prsymbol` : récupère le but principal d’une tâche.
- `Task.task_decls : Task.task -> Decl.decl list` : récupère les déclarations d’une tâche.

### `Trans`

- `Trans.apply_transform : string -> Env.env -> Task.task -> Task.task list` : applique une transformation Why3, ici `split_vc`.

## 3) Preuve (driver + résultats)

### `Driver`

Types / structures :

- `Driver.driver` : driver Why3 pour un couple langage/prouveur.

Fonctions :

- `Driver.load_driver_for_prover : Whyconf.main -> Env.env -> Whyconf.config_prover -> Driver.driver` : charge le driver d’un prouveur configuré.
- `Driver.prepare_task : Driver.driver -> Task.task -> Task.task` : prépare une tâche pour émission vers le backend SMT.
- `Driver.print_task_prepared : ?old:in_channel -> Driver.driver -> Format.formatter -> Task.task -> Printer.printing_info` : imprime une tâche préparée (Why/SMT selon driver).
- `Driver.prove_buffer_prepared : command:string -> config:Whyconf.main -> limits:Call_provers.resource_limits -> ?input_file:string -> ?theory_name:string -> ?goal_name:string -> ?get_model:Printer.printing_info -> Driver.driver -> Buffer.t -> Call_provers.prover_call` : lance la preuve d’une tâche préparée.

### `Call_provers`

Types / structures :

- `Call_provers.prover_answer` : statut brut (`Valid`, `Invalid`, `Timeout`, etc.).
- `Call_provers.prover_result` : résultat complet (statut, temps, infos backend).
- `Call_provers.resource_limits` : limites temps/mémoire/étapes.
- `Call_provers.empty_limits` : limites par défaut.

Constructeurs/statuts utilisés :

- `Call_provers.Valid`
- `Call_provers.Invalid`
- `Call_provers.Timeout`
- `Call_provers.StepLimitExceeded`
- `Call_provers.Unknown`
- `Call_provers.OutOfMemory`
- `Call_provers.Failure`
- `Call_provers.HighFailure`

Accesseurs / fonctions :

- `Call_provers.wait_on_call : Call_provers.prover_call -> Call_provers.prover_result` : attend la fin d’un appel prouveur.
- `Call_provers.prover_result.pr_answer : Call_provers.prover_answer` : champ statut du record `Call_provers.prover_result`.

## 4) AST WhyML manipulé (module `Ptree`)

Kairos construit et traverse explicitement l’AST WhyML de Why3.

Types / champs utilisés :

- `Ptree.mlw_file` : AST racine d’un fichier WhyML.
- `Ptree.decl` : déclaration WhyML.
- `Ptree.binder` : binder de paramètres.
- `Ptree.param` : paramètre de logique/fonction.
- `Ptree.ident` / `Ptree.id_str` : identifiant textuel.
- `Ptree.qualid` : nom qualifié.
- `Ptree.pty` : type programme.
- `Ptree.field` : champ de record.
- `Ptree.spec` / `Ptree.sp_pre` : spécification d’une fonction.
- `Ptree.expr` / `Ptree.expr_desc` : expression programme.
- `Ptree.term` / `Ptree.term_desc` : terme logique.
- `Ptree.reg_branch` : branche de `match`.

Constructeurs de déclarations utilisés :

- `Ptree.Duseimport`
- `Ptree.Dtype`
- `Ptree.Dlogic`
- `Ptree.Dlet`
- `Ptree.Dprop`
- `Ptree.Modules`

Constructeurs de noms/types utilisés :

- `Ptree.Qident`
- `Ptree.Qdot`
- `Ptree.PTtyapp`

Constructeurs d’expressions WhyML utilisés :

- `Econst`, `Etrue`, `Efalse`
- `Eident`, `Eidapp`, `Eapply`
- `Einnfix`, `Enot`, `Eand`, `Eor`
- `Elet`, `Etuple`, `Esequence`
- `Eassign`, `Eif`, `Ematch`
- `Eghost`, `Eassert`

Constructeurs de termes logiques utilisés :

- `Tconst`, `Ttrue`, `Tfalse`
- `Tident`, `Tidapp`, `Tapply`
- `Tinnfix`, `Tbinnop`, `Tnot`
- `Tat`, `Ttuple`
- `Tasref`, `Tif`, `Tattr` (lecture/analyse)

Constructeurs de patterns utilisés :

- `Papp`
- `Pwild`

## 5) Déclarations / identifiants / attributs

### `Decl`

- `Decl.d_node` : forme interne d’une déclaration.
- `Decl.Dprop` : déclaration de propriété.
- `Decl.Pgoal` : genre de propriété = goal.
- `Decl.pr_name` : nom d’une propriété.

### `Ident`

- `Ident.ident.id_string : string` : champ nom du record `Ident.ident`.
- `Ident.op_infix : string -> string` : construction d’un identifiant infixe.
- `Ident.create_attribute : string -> Ident.attribute` : construit un attribut Why3.
- `Ident.Sattr` : ensemble d’attributs.
- `Ident.attribute.attr_string : string` : champ texte du record `Ident.attribute`.

### `Term`

- `Term.term.t_attrs : Ident.Sattr.t` : champ attributs du record `Term.term`.

## 6) Impression / rendu

### `Pretty`

- `Pretty.print_task : Task.task Why3.Pp.pp` : pretty-printer d’une tâche Why3.

### `Mlw_printer`

- `Mlw_printer.pp_mlw_file : ?attr:bool -> Ptree.mlw_file Why3.Pp.pp` : pretty-printer d’un AST WhyML complet.

## 7) Briques logiques et constantes

### `Dterm`

- `Dterm.dbinop` : type des connecteurs booléens binaires.
- `Dterm.DTand` : conjonction.
- `Dterm.DTor` : disjonction.
- `Dterm.DTimplies` : implication.
- `Dterm.DTforall` : quantification universelle.

### `Constant`

- `Constant.constant` : type des constantes Why3.
- `Constant.int_const : ?il_kind:Number.int_literal_kind -> BigInt.t -> Constant.constant` : construit une constante entière Why3.
- `Constant.print_def : Format.formatter -> Constant.constant -> unit` : impression d’une constante.

### `BigInt`

- `BigInt.of_int : int -> BigInt.t` : conversion `int` OCaml vers entier Why3.

## 8) Localisation / expressions internes

### `Loc`

- `Loc.position` : position source Why3.
- `Loc.dummy_position : Loc.position` : position factice utilisée lors de la génération.

### `Expr`

- `Expr.RKnone` : mode de `let` non récursif.
- `Expr.Assert` : kind d’assertion WhyML.

### `Ity`

- `Ity.MaskVisible` : visibilité de champs de type record (génération de type d’état).

## 9) Notes de lecture importantes

- Le projet manipule l’API Why3 à deux niveaux :
  - **niveau AST WhyML (`Ptree`)** pour construire le code WhyML ;
  - **niveau tâches (`Task` + `Driver` + `Call_provers`)** pour générer les VCs et lancer le solveur.
- Les passes de preuves/dumps réutilisent la même normalisation des tâches :
  `Typing.type_mlw_file` → `Task.split_theory` → `Trans.apply_transform "split_vc"`.
- Les accès à `Ptree` passent parfois par des constructeurs non préfixés (via `open Ptree`) dans le backend.
