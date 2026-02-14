# Toolbar Icon Proposals

Objectif: rendre explicites `Build`, `Prove`, `Instrumentation`, `Eval`.

## File actions

### Set A

| Action | Icon |
|---|---|
| New file | ![new-a](../bin/ide/assets/icons/proposals/set_a/new.svg) |
| Open file | ![open-a](../bin/ide/assets/icons/proposals/set_a/open.svg) |
| Save file | ![save-a](../bin/ide/assets/icons/proposals/set_a/save.svg) |

### Set B

| Action | Icon |
|---|---|
| New file | ![new-b](../bin/ide/assets/icons/proposals/set_b/new.svg) |
| Open file | ![open-b](../bin/ide/assets/icons/proposals/set_b/open.svg) |
| Save file | ![save-b](../bin/ide/assets/icons/proposals/set_b/save.svg) |

### Save alternatives (modern)

| Variant | Set A | Set B |
|---|---|---|
| Document + check | ![save-doc-check-a](../bin/ide/assets/icons/proposals/set_a/save_doc_check.svg) | ![save-doc-check-b](../bin/ide/assets/icons/proposals/set_b/save_doc_check.svg) |
| Download to document | ![save-download-a](../bin/ide/assets/icons/proposals/set_a/save_download_doc.svg) | ![save-download-b](../bin/ide/assets/icons/proposals/set_b/save_download_doc.svg) |
| Cloud + check | ![save-cloud-a](../bin/ide/assets/icons/proposals/set_a/save_cloud_check.svg) | ![save-cloud-b](../bin/ide/assets/icons/proposals/set_b/save_cloud_check.svg) |

## Set A (plus "engineering")

| Action | Icon |
|---|---|
| Build | ![build-a](../bin/ide/assets/icons/proposals/set_a/build.svg) |
| Prove | ![prove-a](../bin/ide/assets/icons/proposals/set_a/prove.svg) |
| Instrumentation | ![instr-a](../bin/ide/assets/icons/proposals/set_a/instrumentation.svg) |
| Eval | ![eval-a](../bin/ide/assets/icons/proposals/set_a/eval.svg) |

## Set B (plus "clean/minimal")

| Action | Icon |
|---|---|
| Build | ![build-b](../bin/ide/assets/icons/proposals/set_b/build.svg) |
| Prove | ![prove-b](../bin/ide/assets/icons/proposals/set_b/prove.svg) |
| Instrumentation | ![instr-b](../bin/ide/assets/icons/proposals/set_b/instrumentation.svg) |
| Eval | ![eval-b](../bin/ide/assets/icons/proposals/set_b/eval.svg) |

## Recommendation

- `New file`: Set A
- `Open file`: Set A
- `Save file`: Document + check (Set B)
- `Build`: Set A
- `Prove`: Set A
- `Instrumentation`: Set B
- `Eval`: Set A

## Notes

- Les SVG sont ici:
  - `bin/ide/assets/icons/proposals/set_a/`
  - `bin/ide/assets/icons/proposals/set_b/`
- Si tu valides un set (ou un mix), je peux:
  - remplacer les icones actives dans `bin/ide/assets/icons/light/` et `bin/ide/assets/icons/dark/`,
  - créer explicitement `instrumentation.svg` (il est reference dans le code),
  - changer l'infobulle du bouton instrumentation en `Build`.
