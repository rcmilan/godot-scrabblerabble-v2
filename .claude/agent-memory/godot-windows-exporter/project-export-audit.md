---
name: project-export-audit
description: Full Windows export audit findings for ScrabbleRabble 95 — blocking issues, template status, asset status, preset status
metadata:
  type: project
---

## Audit performed: 2026-06-06

### Export Preset
`export_presets.cfg` does NOT exist. This is the primary blocker — no Windows Desktop preset has been created yet.

**Why:** The project has never been exported. The file must be created via the Godot editor (Project → Export → Add preset → Windows Desktop) before any CLI export is possible.

**How to apply:** Always check for `export_presets.cfg` first. If absent, the very first step is to create it in the editor before any CLI commands will work.

### Export Templates
- Installed at: `C:\Users\suporte\AppData\Roaming\Godot\export_templates\4.6.1.stable.mono`
- Template version: `4.6.1.stable.mono`
- All Windows architectures present: x86_32, x86_64, arm64 (debug + release, with and without console)
- **Critical note:** Templates are the `.mono` (C#/.NET) variant. The project contains NO `.csproj` or `.sln` files — it is pure GDScript. The project.godot has `[dotnet]` section with `project/assembly_name="scrabblerabble"` which caused the mono editor to be used.
- **Implication:** The user is running the Godot 4.6.1 Mono editor. Mono templates ARE compatible for GDScript-only export — Godot Mono editor can export GDScript projects. The templates will match as long as the editor version is also 4.6.1 Mono.

### Project Settings (project.godot)
- Main scene: `uid://cao1bxd4y4usx` (UID-based reference — verify scenes/main.tscn resolves)
- Autoloads: `GameData` (`uid://b1i3utwvda46o` → `scripts/game_data.gd`, confirmed UID match), `RunState` (`res://scripts/run_state.gd`)
- Theme: `res://themes/win95.tres` (set as custom theme)
- Icon: `res://icon.svg`
- Config features: `4.6`, `Forward Plus`
- Has `[dotnet]` section → user is using Godot Mono edition

### Critical Runtime Assets — All Present
- `data/words.txt` — PRESENT
- `themes/win95.tres` — PRESENT
- `fonts/w95fa.otf` — PRESENT
- `shaders/holographic.gdshader` — PRESENT
- `shaders/scanlines.gdshader` — PRESENT
- `scenes/main.tscn` — PRESENT
- `scripts/run_state.gd` — PRESENT
- `icon.svg` — PRESENT

### Output Directory
- `build/` — DOES NOT EXIST (must be created, or export path in preset must point elsewhere)

### Godot Executable
- Not found in PATH or standard Program Files locations
- User must locate their Godot executable manually (likely in Downloads or a custom directory since it's a portable install)
- Expected exe name pattern: `Godot_v4.6.1-stable_mono_win64.exe` (Mono edition)

### Blocking Issues (in priority order)
1. `export_presets.cfg` does not exist — must create preset in Godot editor
2. Godot executable not found in PATH — CLI export requires knowing the exe path
3. `build/` output directory does not exist — create before or set in preset

### Recommended Export Command (once preset is created)
```
"<path-to-godot.exe>" --headless --export-release "Windows Desktop" build\game.exe
```

### Sim Exclusion
`sim_results/` is gitignored. Confirm `exclude_filter` in the preset excludes `sim_results/*` when creating the preset.
