import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ladder_core/ladder_core.dart';

import 'game_state.dart';

/// Interactive Combinatorial Move Tree T_C panel with `Fan`, `Tree`, `Rows`,
/// and `Ring` layouts, zoom toggle, trimming badges (`×`, `↺`, `∀×`), and
/// tap-to-jump onto any non-cycle node.
class TreeWidget extends StatelessWidget {
  final GameState game;

  const TreeWidget({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    MoveTree? tree = game.moveTree;
    ColorScheme colors = Theme.of(context).colorScheme;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (tree == null || tree.nodes.isEmpty) {
      return const Center(child: Text('Building T_C…'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Move Tree T_C',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.onSurface),
                  ),
                  const SizedBox(width: 4),
                  _viewTab(context, 'fan', 'Fan'),
                  _viewTab(context, 'window', 'Tree'),
                  _viewTab(context, 'rows', 'Rows'),
                  _viewTab(context, 'ring', 'Ring'),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: game.toggleTreeZoom,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  child: Text(
                    game.treeZoom ? '[zoom: on]' : '[zoom: all]',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: colors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              Size sz = Size(constraints.maxWidth, constraints.maxHeight);
              Map<int, Offset> coords = _computeNodePositions(
                tree: tree,
                mode: game.treeViewMode,
                zoom: game.treeZoom,
                size: sz,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) {
                  int? hitId = _hitTreeNode(coords, d.localPosition);
                  if (hitId != null) game.jumpToTreeNode(hitId);
                },
                child: CustomPaint(
                  size: sz,
                  painter: _MoveTreePainter(
                    game: game,
                    tree: tree,
                    coords: coords,
                    colors: colors,
                    isDark: isDark,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _viewTab(BuildContext context, String mode, String label) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool on = game.treeViewMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => game.setTreeViewMode(mode),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: on ? colors.primary.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: on ? colors.primary : colors.outlineVariant, width: on ? 1.4 : 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.bold : FontWeight.w500,
            color: on ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static int? _hitTreeNode(Map<int, Offset> coords, Offset p) {
    int? best;
    double bestD = 26.0;
    for (final entry in coords.entries) {
      double d = (entry.value - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = entry.key;
      }
    }
    return best;
  }

  static Map<int, Offset> _computeNodePositions({
    required MoveTree tree,
    required String mode,
    required bool zoom,
    required Size size,
  }) {
    double w = math.max(120.0, size.width);
    double h = math.max(110.0, size.height);
    int activeD = tree.nodes[tree.activeNodeId].depth;
    int minD = zoom ? math.max(0, activeD - 1) : 0;
    int maxD = zoom ? math.min(tree.maxDepth, minD + 4) : math.max(1, tree.maxDepth);
    if (maxD <= minD) maxD = minD + 1;

    List<TreeNode> vis = tree.nodes.where((n) => n.depth >= minD && n.depth <= maxD).toList();
    if (vis.isEmpty) vis = tree.nodes;

    Map<int, List<TreeNode>> byDepth = {};
    for (final TreeNode n in vis) {
      (byDepth[n.depth] ??= []).add(n);
    }
    List<int> depths = byDepth.keys.toList()..sort();

    Map<int, Offset> out = {};
    if (mode == 'ring') {
      Offset center = Offset(w / 2.0, h / 2.0);
      double maxR = math.min(w, h) * 0.43;
      int span = math.max(1, depths.last - depths.first);
      for (final int d in depths) {
        List<TreeNode> row = byDepth[d]!;
        if (d == depths.first && row.length == 1) {
          out[row.first.id] = center;
          continue;
        }
        double r = maxR * ((d - depths.first + 0.65) / (span + 0.65));
        for (int i = 0; i < row.length; i++) {
          double ang = -math.pi / 2.0 + (2.0 * math.pi * i) / row.length;
          out[row[i].id] = center + Offset(math.cos(ang) * r, math.sin(ang) * r);
        }
      }
      return out;
    }

    if (mode == 'fan') {
      Offset apex = Offset(w * 0.14, h * 0.50);
      double maxR = math.max(60.0, w * 0.80);
      int span = math.max(1, depths.last - depths.first);
      for (final int d in depths) {
        List<TreeNode> row = byDepth[d]!;
        if (d == depths.first && row.length == 1) {
          out[row.first.id] = apex;
          continue;
        }
        double rx = maxR * ((d - depths.first) / span);
        double spread = math.min(h * 0.44, 24.0 + row.length * 16.0);
        for (int i = 0; i < row.length; i++) {
          double frac = row.length == 1 ? 0.0 : (i / (row.length - 1)) * 2.0 - 1.0;
          out[row[i].id] = Offset(apex.dx + rx, apex.dy + frac * spread);
        }
      }
      return out;
    }

    if (mode == 'rows') {
      // Horizontal left-to-right depth columns
      int cols = math.max(1, depths.length - 1);
      for (int ci = 0; ci < depths.length; ci++) {
        List<TreeNode> col = byDepth[depths[ci]]!;
        double x = depths.length == 1 ? w / 2.0 : 28.0 + (w - 56.0) * (ci / cols);
        for (int ri = 0; ri < col.length; ri++) {
          double y = (h / (col.length + 1)) * (ri + 1);
          out[col[ri].id] = Offset(x, y);
        }
      }
      return out;
    }

    // Default 'window' ('Tree'): top-down layered tree
    int rows = math.max(1, depths.length - 1);
    for (int ri = 0; ri < depths.length; ri++) {
      List<TreeNode> row = byDepth[depths[ri]]!;
      double y = depths.length == 1 ? h / 2.0 : 22.0 + (h - 44.0) * (ri / rows);
      for (int ci = 0; ci < row.length; ci++) {
        double x = (w / (row.length + 1)) * (ci + 1);
        out[row[ci].id] = Offset(x, y);
      }
    }
    return out;
  }
}

class _MoveTreePainter extends CustomPainter {
  final GameState game;
  final MoveTree tree;
  final Map<int, Offset> coords;
  final ColorScheme colors;
  final bool isDark;

  _MoveTreePainter({
    required this.game,
    required this.tree,
    required this.coords,
    required this.colors,
    required this.isDark,
  }) : super(repaint: game);

  Color get youCol => game.youColor(isDark);
  Color get oppCol => game.oppColor(isDark);
  Color get trimCol => isDark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Edges between superId -> id
    for (final TreeNode n in tree.nodes) {
      int? sup = n.superId;
      if (sup == null) continue;
      Offset? p1 = coords[sup];
      Offset? p2 = coords[n.id];
      if (p1 == null || p2 == null) continue;
      bool onTrail = tree.activeChainIds.contains(sup) && tree.activeChainIds.contains(n.id);
      bool onWin = n.onWinPath && tree.nodes[sup].onWinPath;
      bool trimmed = n.trimmedKind != null;

      Paint ep = Paint()
        ..color = onTrail
            ? youCol
            : trimmed
                ? trimCol.withValues(alpha: 0.48)
                : onWin
                    ? youCol.withValues(alpha: 0.65)
                    : colors.outlineVariant
        ..strokeWidth = onTrail ? 3.5 : (onWin ? 2.5 : 1.8)
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p1, p2, ep);
    }

    // 2. Nodes
    for (final entry in coords.entries) {
      TreeNode n = tree.nodes[entry.key];
      Offset c = entry.value;
      bool isActive = n.id == tree.activeNodeId;
      bool visitedBySolver = false;
      if (game.solverMode == 'trim' && n.trimOrder >= 0 && n.trimOrder <= game.stepIdx) {
        visitedBySolver = true;
      } else if (game.solverMode == 'brute' && n.bruteOrder >= 0 && n.bruteOrder <= game.stepIdx) {
        visitedBySolver = true;
      }

      double r = isActive ? 14.5 : (n.isGoal ? 13.0 : 10.5);
      Color fill = n.isGoal
          ? youCol
          : n.trimmedKind != null
              ? Color.lerp(colors.surface, trimCol, 0.18)!
              : visitedBySolver
                  ? Color.lerp(colors.surface, youCol, 0.28)!
                  : colors.surface;
      Color ring = isActive
          ? colors.primary
          : n.isGoal
              ? youCol
              : n.trimmedKind != null
                  ? trimCol
                  : n.action?.by == 1
                      ? oppCol
                      : n.onWinPath
                          ? youCol
                          : colors.outline;

      if (isActive) {
        canvas.drawCircle(
          c,
          r + 5.5,
          Paint()
            ..color = colors.primary.withValues(alpha: 0.26)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawCircle(c, r, Paint()..color = fill);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = ring
          ..strokeWidth = isActive ? 3.0 : 2.1
          ..style = PaintingStyle.stroke,
      );

      String badge = n.isGoal
          ? '★'
          : n.trimmedKind == 'cycle'
              ? '↺'
              : n.trimmedKind == 'forall'
                  ? '∀×'
                  : n.trimmedKind == 'dead'
                      ? '×'
                      : (n.id == 0 ? 's₀' : '');
      if (badge.isNotEmpty) {
        _drawLabel(
          canvas,
          badge,
          c,
          fontSize: badge.length > 1 ? 10.5 : 12.5,
          color: n.isGoal ? Colors.white : ring,
          bold: true,
        );
      }

      if (isActive || n.isGoal || coords.length <= 18) {
        _drawLabel(
          canvas,
          n.shortLabel,
          c + Offset(0, r + 10.5),
          fontSize: 11.5,
          color: isActive ? colors.onSurface : colors.onSurfaceVariant,
          bold: isActive,
        );
      }
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
    required Color color,
    bool bold = false,
  }) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2.0, tp.height / 2.0));
  }

  @override
  bool shouldRepaint(covariant _MoveTreePainter oldDelegate) => true;
}
