import 'package:flutter/material.dart';
import 'package:ladder_core/ladder_core.dart';

import 'game_state.dart';

/// Shows how the active seed's board was synthesized alongside space/time
/// bounds and the honest per-rung proof status.
class ProofPanel extends StatelessWidget {
  final GameState game;

  const ProofPanel({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    Verdict v = game.verdict;
    List<Widget> bullets = [];
    for (int i = 0; i < game.log.length; i++) {
      bullets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Icon(Icons.circle, size: 7.5, color: i == 0 ? colors.primary : colors.onSurfaceVariant),
              ),
              Expanded(child: Text(game.log[i], style: const TextStyle(fontSize: 13.5))),
            ],
          ),
        ),
      );
    }

    String badge = v.completeOnGrid ? 'complete on 2D grids' : 'membership / caveat noted below';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Synthesized board (seed #${game.seed}, ${game.gridN}×${game.gridN})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            ...bullets,
            const Divider(),
            Text(
              '${v.className} · $badge',
              style: TextStyle(
                color: v.completeOnGrid ? colors.primary : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Space: ${v.spaceBound} · Time: ${v.timeBound}',
              style: TextStyle(color: colors.onSurfaceVariant, fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(v.proofStatus, style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

/// All nine rungs of the Complexity Ladder in the drawer, top (`2EXPTIME ·`)
/// to bottom (`L`). Tap any row to load its regime.
class LadderPanel extends StatelessWidget {
  final GameState game;

  const LadderPanel({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    List<Widget> rows = [];
    for (int r = rungs.length - 1; r >= 0; r--) {
      RungPreset p = rungs[r];
      bool selected = p.switches == game.switches;
      double indent = (rungs.length - 1 - r) * 3.0;
      rows.add(
        InkWell(
          onTap: () {
            game.setRung(p);
            Navigator.of(context).maybePop();
          },
          child: Container(
            margin: EdgeInsets.fromLTRB(indent, 2, indent, 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? colors.primary.withValues(alpha: 0.16) : colors.surface,
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 1.6 : 0.9,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.colLabel,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? colors.onSurface : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  selected ? '◀ active' : p.switches.code,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The nine-rung Complexity Ladder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              'Switch code: T/t thr 2/0, O/o open/closed, D/d 1/2-way, P/p 2/1p, 1/* once/free, A/a ∀, F/f folded, X/x bridge.',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ...rows,
          ],
        ),
      ),
    );
  }
}
