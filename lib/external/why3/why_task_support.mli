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

(** Shared Why3 task preparation helpers used by proof and artifact layers.

    A {{!Why3.Task.task}task} is one elementary Why3 proof obligation.
    The helpers of this module build {e normalized tasks}: VC obligations after
    Why3 normalization/splitting, in a deterministic order suitable for proof
    runs, dumps, and provenance tracking. *)

(** Initialize Why3 configuration and typing environment.

    @return
      [(config, main, env, datadir_opt)] where [datadir_opt] is the detected
      Why3 data directory, when available. *)
val setup_env : unit -> Why3.Whyconf.config * Why3.Whyconf.main * Why3.Env.env * string option

(** Normalize parse-tree obligations into split Why3 tasks.

    @param env
      Why3 environment used for typing and transforms.
    @param ptree
      WhyML parse tree to normalize.
    @return
      Normalized task list in deterministic order. *)
val normalize_tasks_of_ptree :
  env:Why3.Env.env -> ptree:Why3.Ptree.mlw_file -> Why3.Task.task list

(** Collect provenance ids ([wid:*]/[rid:*]) from one task.

    @param task
      Why3 task to inspect.
    @return
      Distinct provenance ids found in goal and hypotheses. *)
val task_wids_deep : Why3.Task.task -> int list

(** Normalize tasks and associate each one with provenance ids.

    @param env
      Why3 environment used for typing and transforms.
    @param ptree
      WhyML parse tree to normalize.
    @return
      List of pairs [(task, wids)] where [wids] tracks provenance for each
      normalized task. *)
val normalize_tasks_with_wids_of_ptree :
  env:Why3.Env.env ->
  ptree:Why3.Ptree.mlw_file ->
  (Why3.Task.task * int list) list

(** Select the Z3 prover configuration from Why3 config with fallback logic.

    @param config
      Loaded Why3 configuration.
    @param datadir_opt
      Optional Why3 datadir used to resolve fallback driver paths.
    @return
      A usable Why3 prover configuration targeting Z3. *)
val select_z3_prover_cfg :
  config:Why3.Whyconf.config ->
  datadir_opt:string option ->
  Why3.Whyconf.config_prover
