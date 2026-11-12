# Complexity Ladder: unified grid physics

One orthogonal $n \times n$ grid board, eight physics switches, and one move
gesture across nine complexity classes (`L` through `2EXPTIME`). Cells sit at
grid coordinates `(r, c)`, horizontal and vertical connectors join orthogonally
adjacent cells with weights `1` (single bar) or `2` (double bar), and player and
opponent meeples slide along connectors so the player's `★` token reaches the
recessed Goal socket `★`.

Someone who plays the top rungs already knows how to play every lower rung: the
board geometry, perimeter token anatomy, hover-highlighted connector tap, and
meeple drag stay continuous from `L` to `2EXPTIME`. Lower rungs only restrict or
open switches on the same grid physics.

## Interaction & visual continuity across `P → NP`

Every legal step on the grid can be made in two equivalent ways:

1. **Tap a connector:** each connector between two neighbouring cells carries
   at most one legal action at a time under the active switches. Playable
   connectors highlight on pointer hover (with a single aligned directional
   arrowhead preview) and fire on tap.
2. **Drag a meeple:** press and drag one of your unlocked meeples along a
   connector, releasing past the midpoint.

To keep puzzle intuition continuous across the open-centre walk rungs (`L`,
`NL`, `P`) and the closed-centre constraint-logic rungs (`NP` through
`2EXPTIME`):

- **Coupled perimeter `1`-tokens on `L`, `NL`, `P` (default view):** instead of
  jumping abruptly from a single centre token on `P` to perimeter tokens on
  `NP`, the active walk cell displays coupled value-`1` meeple-tokens on each
  outgoing connector around its perimeter with cell threshold `E−1` (`1` unit of
  overage, releasing `1` token). Selecting an outgoing connector slides its
  token to the next cell's perimeter while its sibling projections vanish and
  fresh perimeter tokens appear at the arrival cell. (A drawer toggle also lets
  you view the classic single-centre-token presentation.)
- **Locked goal-connector `★` token:** on walk rungs, cells one connector away
  from the Goal display a greyed-out locked `★` token (`threshold 1`) on the
  goal connector; arriving at that cell unlocks `★` for the final slide.
- **Recessed Goal socket & universal `★` arrival:** the Goal cell renders a
  concave outlined token indent (no fill) until solved. On **every** rung —
  including `NP`, `PSPACE`, `EXPTIME`, and folded rungs — the winning slide
  carries `★` all the way into the Goal socket's centre and triggers a shimmer
  pulse.
- **Folded `2×2` boxes (`NEXPTIME ·`, `EXPSPACE ·`, `2EXPTIME ·`):** tapping a
  dashed `2×2` box of tile `A` (`2` boxes on `4×4`, `3` on `5×5`, `4` on `6×6`)
  unfolds its hidden internal sub-grid in place with zero coordinate jump.

## The eight switches

| switch | low / off | high / on | effect on the grid |
| --- | --- | --- | --- |
| `thr` | `0` | `2` | inflow weight that must remain at a cell when a meeple slides away (`0` enables walk dynamics; `2` enforces constraint-logic inflow conservation) |
| `open` | `true` (open) | `false` (closed) | open cell centres implement graph-walk reachability; closed centres hold independent meeples on connector endpoints around cell perimeters |
| `directed` | `false` (`2-way`) | `true` (`1-way`) | connectors allow symmetric travel or carry unified directional arrowheads |
| `alt` | `false` (`∀` off) | `true` (`∀` on) | on open-centre walks, the opponent chooses the outgoing exit whenever `★` enters a `∀` cell |
| `once` | `true` (each once) | `false` (free slides) | each blocker slides at most once (locking with a tick `✓`) or slides any number of times |
| `two` | `false` (`1` player) | `true` (`2` players) | solo play, or alternating turns while the opponent races its own `★` toward its own goal socket |
| `coded` | `false` (drawn) | `true` (`2×2` folded) | `2×2` regions start folded as boxes of tile `A`; unfolding expands their internal wires and meeples |
| `cross` | `false` (ordinary) | `true` (bridge) | crossing cells `+` pair `N↔S` and `W↔E` exits as orthogonal bridges so non-planar graphs embed cleanly on the `2D` grid |

## The nine rungs and their proof status

| rung | `thr` | `open` | `directed` | `alt` | `once` | `two` | `coded` | `cross` | class readout | proof status on this `2D` grid |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `L` | `0` | open | `2-way` | off | – | `1P` | drawn | bridge | `L` | **Membership proven:** symmetric grouped exit tables define an undirected graph walk in `L` (Reingold 2005). `L`-hardness under logspace reductions is not claimed. |
| `NL` | `0` | open | `1-way` | off | – | `1P` | drawn | bridge | `NL-complete` | **Complete on `2D` grids with crossing bridges:** directed `s`–`t` reachability (Jones 1975); crossing cells route arbitrary digraph edges in the plane. |
| `P` | `0` | open | `1-way` | `∀` on | – | `1P` | drawn | bridge | `P-complete` | **Complete on `2D` grids with crossing bridges:** alternating graph reachability (Immerman 1981; Chandra, Kozen & Stockmeyer 1981). |
| `NP` | `2` | closed | `2-way` | off | once | `1P` | drawn | bridge | `NP-complete` | **Complete on planar `2D` grids:** bounded `1`-player Nondeterministic Constraint Logic with connector weights `{1, 2}` and cell threshold `2` (Hearn & Demaine 2009). |
| `PSPACE` | `2` | closed | `2-way` | off | free | `1P` | drawn | bridge | `PSPACE-complete` | **Complete on planar `2D` grids:** unbounded `1`-player Nondeterministic Constraint Logic (`AND` = weight `1+1 → 2`, `OR` = weight `2 → 2`; Hearn & Demaine 2005, 2009). |
| `EXPTIME` | `2` | closed | `2-way` | off | free | `2P` | drawn | bridge | `EXPTIME-complete` | **Membership proven; planar `2`-player NCL is `EXPTIME`-complete** (Hearn & Demaine 2009). On the strict unit orthogonal grid, degree-`2` wire-turn cells introduce extra single-player tempos whose gadget neutralisation is not written down. |
| `NEXPTIME` | `2` | closed | `2-way` | off | once | `1P` | `2×2` folded | bridge | `NEXPTIME ·` | **Membership proven.** Marked `·`: lifting `NP` one exponential up requires verifying the succinct-projection condition on the NCL reduction (Papadimitriou & Yannakakis 1986; Lengauer & Wagner 1992) and generalising single-wire `2×2` tile ports to multi-wire ports. |
| `EXPSPACE` | `2` | closed | `2-way` | off | free | `1P` | `2×2` folded | bridge | `EXPSPACE ·` | **Membership proven.** Marked `·`: same succinct NCL projection check and multi-wire `2×2` tile port generalisation remain open. |
| `2EXPTIME` | `2` | closed | `2-way` | off | free | `2P` | `2×2` folded | bridge | `2EXPTIME ·` | **Membership proven** (alternating exponential space). Marked `·`: succinct `2`-player NCL lift, wire-turn tempo check, and multi-wire tile ports remain open. |

An unbounded tenth regime (`Undecidable`, $\Sigma_1^0$-complete) arises when
folded boxes nest without a depth cap so the board unfolds indefinitely during
play; the finite interactive presets stop at `2EXPTIME ·` so every synthesized
board has an exact solver verdict.

## Lattice structure

The nine presets form a lattice rather than a single total order:

- **Open-centre walk chain (`thr = 0, open = true`):** `L → NL → P` (adding
  directionality, then adversarial `∀` branching).
- **Closed-centre constraint-logic cube (`thr = 2, open = false`):** three
  orthogonal switches compose above `NP`:
  - `once: true → false` (`NP → PSPACE`: bounded witnesses to reversible
    reconfiguration),
  - `two: false → true` (`PSPACE → EXPTIME`: single-agent planning to
    two-player alternation),
  - `coded: false → true` (`{NP, PSPACE, EXPTIME} → {NEXPTIME ·, EXPSPACE ·, 2EXPTIME ·}`:
    explicit grid to succinct `2×2` tile hierarchy).

## Package architecture

- `ladder_core/` — pure Dart, zero Flutter dependencies:
  - `src/random32.dart`: exact `32`-bit `Mulberry32` PRNG for reproducible
    cross-platform board seeds.
  - `src/switches.dart`: `Switches`, `Verdict`, `RungPreset`, the nine ladder
    rungs, and custom lattice classification (`verdictOf`).
  - `src/board.dart`: `GridBoard`, `CellNode`, `Connector`, `Meeple`,
    `TileDef`, in-place `2×2` tile unfolding, state hashing (`boardKey`), and
    topology signatures (`topologySig`).
  - `src/rules.dart`: unified grid step legality (`Rules.movesOf`),
    single-action connector hit resolution (`Rules.connectorActionsOf`), and
    combinatorial action enumeration (`Rules.enumerateLegalActions`).
  - `src/solver.dart`: exact per-regime solver (`Solver.solve` across `L`/`NL`
    BFS, `P` `∃/∀` fixed-point backward induction, `NP`/`PSPACE` state-space
    BFS, and `EXPTIME` retrograde two-player minimax) plus move-tree extraction
    (`Solver.buildMoveTree`).
  - `src/synthesis.dart`: full-grid procedural board generator across `4×4`
    (`~15–18` connectors, `2` folded boxes), `5×5` (`~25–30` connectors, `3`
    folded boxes), and `6×6` (`~37–44` connectors, `4` folded boxes), producing
    solver-verified non-isomorphic puzzles with crossing-bridge separation,
    controlled initial inflow, and randomly placed reversible shuttle gates.
- `app/` — Flutter Material 3 application (`org.modelmodel.complexity_ladder`):
  - Manual-solver Grid-only layout: portrait screens show the interactive grid
    board above the nine-rung scroll wheel and play bar (`undo`, `redo`,
    `reset`, 2-tap `hint`, `new`); wide desktop/tablet screens (`>= 840 px`)
    show the Grid Board alongside the nine-rung `Complexity Class Ladder`.
  - Top bar includes a `Green` / `Purple` player-color toggle; the navigation
    drawer exposes the `L/NL/P` perimeter-vs-centre view toggle, all eight live
    physics switches, grid size (`4×4`, `5×5`, `6×6`) and seed controls,
    proof-status card, and lattice readout.
