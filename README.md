# scrabblerabble

A Godot 4.6 word game in the spirit of Scrabble, dressed in a Windows 95 skin.
Place tiles, form words, and beat an escalating target before you run out of
turns.

This README focuses on **running the simulator** — both headless (for batch
strategy evaluation) and visual (watching a strategy play the real game UI).

For agent-facing project conventions, see [`CLAUDE.md`](./CLAUDE.md).
For sim internals and the duplication notice, see
[`scripts/sim/README.md`](./scripts/sim/README.md).

## Prerequisites

- Godot 4.6+ (this project was developed against `Godot_v4.6.1-stable_mono`).
- No external dependencies — everything ships in-repo.

Replace `<godot>` below with the path to your Godot binary. On Windows, the
console build is preferred (`Godot_v4.6.1-stable_mono_win64_console.exe`)
because `print(...)` output lands in your terminal.

## Headless simulation (batch)

Runs N games per strategy with no window, writes CSV + JSONL to
`./sim_results/` (gitignored).

```
<godot> --headless --path . --script res://scripts/sim/sim_runner.gd -- \
    --runs 100 \
    --strategies random,greedy,word_search \
    --seed 42
```

Flags (all optional):

| Flag           | Default        | Description                                          |
| -------------- | -------------- | ---------------------------------------------------- |
| `--runs`       | `100`          | Games to run **per strategy**.                       |
| `--strategies` | `random`       | Comma-separated. `random`, `greedy`, `word_search`, `diagonal_cluster`. |
| `--seed`       | `42`           | Base RNG seed. Same seed → reproducible run.         |
| `--out`        | `user://sim/`  | Output dir. Use a relative path (e.g. `./sim_results/`) — `user://` is unreliable in headless mode. |

Both `--key=value` and `--key value` forms work. Output filenames are
timestamped; see `scripts/sim/results_writer.gd`.

### Running the sim test suite

Parity, scoring, progression, and strategy tests live under
`scripts/sim/tests/`:

```
<godot> --headless --path . --script res://scripts/sim/tests/run_tests.gd
```

A 3-game smoke test (faster, useful as a pre-push check):

```
<godot> --headless --path . --script res://scripts/sim/tests/smoke.gd
```

## Visual autoplay (watch a strategy play)

Launches the real game UI and hands control to a strategy. Tiles get placed,
glitter spawns, the HUD updates — same as a human run, just driven by the
strategy. ~200 ms between tile placements.

```
<godot> --path . -- --autoplay=word_search
```

Accepted values: `word_search` (default if you pass bare `--autoplay`),
`greedy`, `random`, `diagonal_cluster`. The loop stops when the run ends;
the game-over dialog takes over from there. Logs are prefixed `[Autoplay]`.

## Adding a new strategy

1. Create `scripts/sim/strategies/<name>_strategy.gd` extending
   `res://scripts/sim/strategy.gd`. Implement `pick_moves(core) -> Array`
   returning `[{"letter": "X", "pos": Vector2i(x, y)}, ...]`. Respect a
   ~50 ms time budget per turn (see `word_search_strategy.gd` for the
   pattern).
2. Wire it into the dispatcher in `scripts/sim/sim_runner.gd::_build_strategies`.
3. Wire it into the visual dispatcher in `scripts/main.gd::_build_strategy`
   if you want to watch it play.
4. Add tests under `scripts/sim/tests/test_strategies.gd`.

The strategy interface (what `core` exposes) is documented by
`scripts/sim/game_core.gd`: `BOARD_SIZE`, `board[x][y]`, `rack`,
`tiles_per_turn`, `rng`, `is_cell_empty(pos)`. The visual autoplay path
uses a small adapter in `main.gd::_AutoplayAdapter` to expose the same
shape over the live `Board`/`Rack` nodes.

## Troubleshooting

- **No output / window doesn't open**: make sure you're using the
  `*_console.exe` build on Windows so `print(...)` is visible.
- **`OS.get_cmdline_args()` returns engine flags**: use
  `OS.get_cmdline_user_args()` to read args after `--` (Godot 4.6).
- **`user://` paths empty in headless mode**: use a relative output path
  like `./sim_results/`. Directories are created with
  `DirAccess.make_dir_absolute()`.
- **Sim results disagree with the real game**: scoring/progression logic
  is duplicated in `scripts/sim/game_core.gd`. Drift between it and
  `main.gd`/`run_state.gd` is the most common cause. Re-run the parity
  tests (TC1–TC8).
