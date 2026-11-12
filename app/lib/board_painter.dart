import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ladder_core/ladder_core.dart';

import 'board_geometry.dart';
import 'game_state.dart';

class BoardPainter extends CustomPainter {
  static const double _kShimmerBand = 1.45;
  static const double _kArrowTipT = 0.64;

  final GameState game;
  final BoardGeometry geometry;
  final ColorScheme colors;
  final bool isDark;
  final double? winProgress;
  final double? walkProgress;

  BoardPainter({
    required this.game,
    required this.geometry,
    required this.colors,
    required this.isDark,
    required this.winProgress,
    this.walkProgress,
    required Listenable repaintListenable,
  }) : super(repaint: repaintListenable);

  Color get youCol => game.youColor(isDark);
  Color get oppCol => game.oppColor(isDark);
  Color get hintCol => isDark ? const Color(0xFFF2A93B) : const Color(0xFFC87000);
  Color get shineCol => Color.lerp(youCol, Colors.white, isDark ? 0.72 : 0.68)!;
  Color get neutralGrey => isDark ? const Color(0xFF787E87) : const Color(0xFF8E959E);
  Color get greyRingCol => isDark ? const Color(0xFFA8B0BA) : const Color(0xFF5D6570);
  Color get lineCol => colors.outlineVariant;
  Color get bgCol => colors.surface;
  Color get fgCol => colors.onSurface;
  Color get mutedCol => colors.onSurfaceVariant;

  Color ownerCol(int owner) => owner == 0 ? youCol : oppCol;

  Map<String, double> _computeWinWaveDistances(GridBoard st) {
    String? goalId;
    for (final CellNode v in st.verts.values) {
      if (v.goal == 0) {
        goalId = v.id;
        break;
      }
    }
    goalId ??= st.starMeeple(0)?.at ?? (st.verts.isNotEmpty ? st.verts.keys.first : null);
    if (goalId == null) return const {};

    Map<String, double> dist = {goalId: 0.0};
    bool changed = true;
    int guard = 0;
    while (changed && guard++ <= st.verts.length + 2) {
      changed = false;
      for (final Connector e in st.edges) {
        CellNode? vu = st.verts[e.u];
        CellNode? vv = st.verts[e.v];
        if (vu == null || vv == null) continue;
        double step = math.max(
          0.65,
          Vec2(vu.x, vu.y).distTo(Vec2(vv.x, vv.y)) / kGridPitch,
        );
        double? du = dist[e.u];
        double? dv = dist[e.v];
        if (du != null && (dv == null || du + step < dv - 1e-6)) {
          dist[e.v] = du + step;
          changed = true;
        }
        if (dv != null && (du == null || dv + step < du - 1e-6)) {
          dist[e.u] = dv + step;
          changed = true;
        }
      }
    }

    CellNode? gv = st.verts[goalId];
    if (gv != null) {
      for (final CellNode v in st.verts.values) {
        dist.putIfAbsent(
          v.id,
          () => math.max(0.5, Vec2(v.x, v.y).distTo(Vec2(gv.x, gv.y)) / kGridPitch),
        );
      }
    }
    return dist;
  }

  @override
  void paint(Canvas canvas, Size size) {
    GridBoard? st = game.board;
    if (st == null) return;
    Switches s = game.switches;
    bool yt = game.yourTurn;
    TreeAction? hint = game.hint;

    Map<String, double>? hopDist;
    double waveFront = -1.0;
    if (winProgress != null) {
      hopDist = _computeWinWaveDistances(st);
      double maxDist = 1.0;
      for (final double d in hopDist.values) {
        if (d > maxDist) maxDist = d;
      }
      double eased = math.pow(winProgress!.clamp(0.0, 1.0), 0.88).toDouble();
      waveFront = eased * (maxDist + _kShimmerBand + 0.45);
    }

    // 1. Dashed off-slots
    Paint offPaint = Paint()
      ..color = lineCol.withValues(alpha: 0.78)
      ..strokeWidth = math.max(1.6, 2.0 * geometry.scale)
      ..style = PaintingStyle.stroke;
    for (final (String u, String v) in st.off) {
      CellNode? vu = st.verts[u];
      CellNode? vv = st.verts[v];
      if (vu == null || vv == null) continue;
      Offset p1 = geometry.toScreen(vu.x, vu.y);
      Offset p2 = geometry.toScreen(vv.x, vv.y);
      double len = (p2 - p1).distance;
      if (len <= 42.0 * geometry.scale) continue;
      Offset dir = (p2 - p1) / len;
      _drawDashedLine(
        canvas,
        p1 + dir * (21.0 * geometry.scale),
        p2 - dir * (21.0 * geometry.scale),
        offPaint,
        4.8 * geometry.scale,
        6.2 * geometry.scale,
      );
    }

    // 2. Switched-on orthogonal connectors (with hover, hint & win-pulse shimmer)
    for (final Connector e in st.edges) {
      EndAnchor a = BoardGeometry.endOf(st, e, e.u);
      EndAnchor b = BoardGeometry.endOf(st, e, e.v);
      Offset p1 = geometry.toScreen(a.x, a.y);
      Offset p2 = geometry.toScreen(b.x, b.y);
      double len = (p2 - p1).distance;
      if (len <= 1.0) continue;
      Offset dir = (p2 - p1) / len;
      Offset s1 = p1 + dir * ((a.r + 2.5) * geometry.scale);
      Offset s2 = p2 - dir * ((b.r + 2.5) * geometry.scale);

      if (hopDist != null) {
        double du = hopDist[e.u] ?? 0.0;
        double dv = hopDist[e.v] ?? 0.0;
        bool uFirst = du <= dv;
        double d0 = uFirst ? du : dv;
        double d1 = uFirst ? dv : du;
        Offset nearPt = uFirst ? s1 : s2;
        Offset farPt = uFirst ? s2 : s1;

        if (waveFront > d0) {
          double span = math.max(0.45, d1 - d0);
          double cov = ((waveFront - d0) / span).clamp(0.0, 1.0);
          if (cov < 1.0) {
            Offset crestPt = Offset.lerp(nearPt, farPt, cov)!;
            // Unreached portion ahead of the wave
            canvas.drawLine(
              crestPt,
              farPt,
              Paint()
                ..color = mutedCol.withValues(alpha: 0.72)
                ..strokeWidth = math.max(2.0, 2.9 * geometry.scale)
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke,
            );
            // Soft colored aura on reached portion
            canvas.drawLine(
              nearPt,
              crestPt,
              Paint()
                ..color = youCol.withValues(alpha: 0.26)
                ..strokeWidth = 12.0 * geometry.scale
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke,
            );
            // Colored prefix behind crest
            canvas.drawLine(
              nearPt,
              crestPt,
              Paint()
                ..color = youCol
                ..strokeWidth = math.max(2.4, 3.8 * geometry.scale)
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke,
            );
            // Shimmer / shine gradient crest at wavefront
            Offset tailPt = Offset.lerp(nearPt, farPt, math.max(0.0, cov - 0.52))!;
            if ((crestPt - tailPt).distance > 1.0) {
              Paint shimmerPaint = Paint()
                ..shader = ui.Gradient.linear(tailPt, crestPt, [youCol, shineCol])
                ..strokeWidth = math.max(3.0, 5.2 * geometry.scale)
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke;
              canvas.drawLine(tailPt, crestPt, shimmerPaint);
            }
            canvas.drawCircle(
              crestPt,
              4.6 * geometry.scale,
              Paint()..color = shineCol.withValues(alpha: 0.88),
            );
            if (s.directed) {
              bool tailIsU = e.tail == 'u';
              Offset from = tailIsU ? p1 : p2;
              Offset to = tailIsU ? p2 : p1;
              Offset midTip = Offset.lerp(from, to, _kArrowTipT)!;
              double tipWaveT = (uFirst == tailIsU) ? _kArrowTipT : (1.0 - _kArrowTipT);
              _drawArrowHead(
                canvas,
                from,
                midTip,
                cov >= tipWaveT ? youCol : mutedCol.withValues(alpha: 0.78),
                11.8 * geometry.scale,
              );
            }
            continue;
          } else {
            double trail = ((waveFront - d1) / _kShimmerBand).clamp(0.0, 1.0);
            double shine = (1.0 - trail) * (1.0 - trail);
            Color edgeWinCol = Color.lerp(youCol, shineCol, 0.72 * shine)!;
            canvas.drawLine(
              s1,
              s2,
              Paint()
                ..color = edgeWinCol.withValues(alpha: 0.16 + 0.30 * shine)
                ..strokeWidth = (8.5 + 8.0 * shine) * geometry.scale
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke,
            );
            canvas.drawLine(
              s1,
              s2,
              Paint()
                ..color = edgeWinCol
                ..strokeWidth = math.max(2.4, (3.8 + 1.6 * shine) * geometry.scale)
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke,
            );
            if (s.directed) {
              bool tailIsU = e.tail == 'u';
              Offset from = tailIsU ? p1 : p2;
              Offset to = tailIsU ? p2 : p1;
              Offset midTip = Offset.lerp(from, to, _kArrowTipT)!;
              _drawArrowHead(canvas, from, midTip, edgeWinCol, 11.8 * geometry.scale);
            }
            continue;
          }
        }
      }

      List<ConnectorAction> acts = yt ? Rules.connectorActionsOf(st, s, e) : const [];
      double walkArrive = (game.usePerimeterWalk && st.isWalkRegime(s) && walkProgress != null)
          ? ((walkProgress! - 0.55) / 0.45).clamp(0.0, 1.0)
          : 1.0;
      bool slidingThisEdge = walkProgress != null &&
          ((game.usePerimeterWalk && st.isWalkRegime(s) && game.walkTransition?.edgeId == e.id) ||
              (!game.usePerimeterWalk && game.pieceSlide?.edgeId == e.id));
      bool clickable = acts.isNotEmpty && walkArrive > 0.05;
      bool hovered = clickable && game.hoveredConnectorId == e.id;
      bool hinted = hint != null && hint.edge == e.id;

      if (slidingThisEdge) {
        Paint slideGlow = Paint()
          ..color = youCol.withValues(alpha: 0.22)
          ..strokeWidth = 12.0 * geometry.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(s1, s2, slideGlow);
      } else if (hovered || hinted) {
        Paint glow = Paint()
          ..color = (hinted ? hintCol : youCol).withValues(alpha: (hovered ? 0.26 : 0.30) * walkArrive)
          ..strokeWidth = 15.0 * geometry.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(s1, s2, glow);
      } else if (clickable) {
        Paint softGlow = Paint()
          ..color = youCol.withValues(alpha: 0.12 * walkArrive)
          ..strokeWidth = 10.0 * geometry.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(s1, s2, softGlow);
      }

      Meeple? onIt = st.pieces.where((p) => p.on == e.id).firstOrNull;
      Color baseCol = slidingThisEdge
          ? youCol
          : hinted
              ? hintCol
              : hovered
                  ? youCol
                  : clickable
                      ? Color.lerp(mutedCol.withValues(alpha: 0.80), Color.lerp(fgCol, youCol, 0.58)!, walkArrive)!
                      : onIt != null
                          ? Color.lerp(ownerCol(onIt.owner), fgCol, 0.52)!
                          : mutedCol.withValues(alpha: 0.80);
      double strokeW =
          (slidingThisEdge ? 4.4 : (hovered || hinted ? 5.2 : (clickable ? (2.9 + 1.1 * walkArrive) : 2.9))) *
              geometry.scale;
      Paint core = Paint()
        ..color = baseCol
        ..strokeWidth = math.max(2.0, strokeW)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s1, s2, core);

      // Aligned directional / hover-action arrowhead (single shared anchor, zero overlap)
      bool showActionArrow =
          (hovered || hinted) && acts.isNotEmpty && acts.first.from != acts.first.to;
      if (showActionArrow) {
        EndAnchor dst = BoardGeometry.endOf(st, e, acts.first.to);
        EndAnchor src = BoardGeometry.endOf(st, e, acts.first.from);
        Offset from = geometry.toScreen(src.x, src.y);
        Offset to = geometry.toScreen(dst.x, dst.y);
        Offset tip = Offset.lerp(from, to, _kArrowTipT)!;
        _drawArrowHead(canvas, from, tip, hinted ? hintCol : youCol, 13.0 * geometry.scale);
      } else if (s.directed) {
        bool tailIsU = e.tail == 'u';
        Offset from = tailIsU ? p1 : p2;
        Offset to = tailIsU ? p2 : p1;
        Offset midTip = Offset.lerp(from, to, _kArrowTipT)!;
        _drawArrowHead(canvas, from, midTip, baseCol, 11.8 * geometry.scale);
      }
    }

    // 3. Cells and folded 2x2 tile boxes
    for (final CellNode v in st.verts.values) {
      double? dv = hopDist?[v.id];
      double? nodeShine = (dv != null && waveFront >= dv)
          ? (1.0 - ((waveFront - dv) / _kShimmerBand).clamp(0.0, 1.0))
          : null;
      if (v.isBox) {
        _drawFoldedBox(
          canvas,
          st,
          v,
          hint != null && hint.kind == 'unfold' && hint.box == v.id,
          nodeShine,
        );
      } else {
        _drawCellNode(canvas, st, s, v, nodeShine);
      }
    }

    // 4. Meeples (either coupled-perimeter walk tokens on L/NL/P or standard pieces)
    if (game.usePerimeterWalk && st.isWalkRegime(s)) {
      _drawWalkPerimeterTokens(canvas, st, s, yt, hint, hopDist, waveFront);
    } else {
      String? activeTopId = game.drag?.pieceId ??
          (walkProgress != null ? game.pieceSlide?.pieceId : null);
      Meeple? activeTopPiece;
      for (final Meeple p in st.pieces) {
        if (p.id == activeTopId) {
          activeTopPiece = p;
          continue;
        }
        double? dp = hopDist?[p.at];
        if (dp != null && p.on != null) dp += 0.22;
        double? meepleShine = (dp != null && waveFront >= dp)
            ? (1.0 - ((waveFront - dp) / _kShimmerBand).clamp(0.0, 1.0))
            : null;
        _drawMeeple(canvas, st, s, p, yt, hint, meepleShine);
      }
      if (activeTopPiece != null) {
        double? dp = hopDist?[activeTopPiece.at];
        if (dp != null && activeTopPiece.on != null) dp += 0.22;
        double? meepleShine = (dp != null && waveFront >= dp)
            ? (1.0 - ((waveFront - dp) / _kShimmerBand).clamp(0.0, 1.0))
            : null;
        _drawMeeple(canvas, st, s, activeTopPiece, yt, hint, meepleShine);
      }
    }

    // 5. Folded 2x2 tile definition legend ("A = ...")
    if (geometry.showTileLegend) {
      _drawTileLegend(canvas, st, s);
    }
  }

  void _drawFoldedBox(
    Canvas canvas,
    GridBoard st,
    CellNode v,
    bool hinted,
    double? winShine,
  ) {
    Offset c = geometry.toScreen(v.x, v.y);
    double halfW = kBoxHalf * geometry.scaleX;
    double halfH = kBoxHalf * geometry.scaleY;
    Rect rect = Rect.fromCenter(center: c, width: halfW * 2.0, height: halfH * 2.0);
    RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(14.0 * geometry.scale));

    double bloom = winShine != null ? math.sin(winShine * math.pi) : 0.0;
    Color col = winShine != null
        ? Color.lerp(youCol, shineCol, 0.65 * bloom)!
        : (hinted ? hintCol : ownerCol(v.owner));

    if (winShine != null && winShine > 0.01) {
      Rect glowRect = rect.inflate((3.5 + 8.0 * (1.0 - winShine)) * geometry.scale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(glowRect, Radius.circular(17.0 * geometry.scale)),
        Paint()
          ..color = shineCol.withValues(alpha: 0.45 * winShine * winShine)
          ..strokeWidth = 3.2 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()..color = Color.lerp(bgCol, col, winShine != null ? (0.18 + 0.20 * bloom) : 0.11)!,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = col
        ..strokeWidth = (winShine != null ? (3.2 + 1.2 * bloom) : (hinted ? 3.8 : 2.8)) * geometry.scale
        ..style = PaintingStyle.stroke,
    );

    // Subtle 2x2 grid hint inside the folded box
    for (final Vec2 lv in TileDef.baseVerts.values) {
      Vec2 gp = gadOffset(v, lv.x * 0.55, lv.y * 0.55);
      Offset sp = geometry.toScreen(gp.x, gp.y);
      canvas.drawCircle(sp, 4.0 * geometry.scale, Paint()..color = col.withValues(alpha: 0.30));
    }

    // Port dots on boundary
    TileDef gad = st.tileDef ?? TileDef.defaultTile;
    for (final String pn in gad.usedPorts) {
      TilePortDef? pt = TileDef.basePorts[pn];
      if (pt == null) continue;
      Vec2 pp = gadOffset(v, pt.dx, pt.dy);
      Offset sp = geometry.toScreen(pp.x, pp.y);
      canvas.drawCircle(sp, 4.8 * geometry.scale, Paint()..color = col);
    }

    _drawCenteredText(
      canvas,
      v.rot180 ? '${v.box}′ (${v.id})' : '${v.box} (${v.id})',
      c - Offset(0, 7.5 * geometry.scale),
      fontSize: math.max(13.0, 17.5 * geometry.scale),
      weight: FontWeight.bold,
      color: col,
    );
    _drawCenteredText(
      canvas,
      'tap to unfold 2×2',
      c + Offset(0, 13.0 * geometry.scale),
      fontSize: math.max(10.5, 13.0 * geometry.scale),
      color: winShine != null ? col.withValues(alpha: 0.88) : mutedCol,
    );
  }

  void _drawCellNode(
    Canvas canvas,
    GridBoard st,
    Switches s,
    CellNode v,
    double? winShine,
  ) {
    Offset c = geometry.toScreen(v.x, v.y);
    double r = BoardGeometry.kNodeRadius * geometry.scale;
    double bloom = winShine != null ? math.sin(winShine * math.pi) : 0.0;

    if (winShine != null && winShine > 0.01) {
      double expand = (2.4 + 8.0 * (1.0 - winShine)) * geometry.scale;
      canvas.drawCircle(
        c,
        r + expand,
        Paint()
          ..color = shineCol.withValues(alpha: 0.50 * winShine * winShine)
          ..strokeWidth = 3.0 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
    }

    if (v.goal != null) {
      Color gCol = (winShine != null && v.goal == 0)
          ? Color.lerp(youCol, shineCol, 0.65 * bloom)!
          : ownerCol(v.goal!);
      // Mask underlying connector lines without adding any fill color (hollow socket)
      canvas.drawCircle(c, r, Paint()..color = bgCol);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = gCol
          ..strokeWidth = (winShine != null ? (3.2 + 1.2 * bloom) : 2.6) * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      // Token-sized recessed circular indent outline (no fill)
      double rIndent = 12.6 * geometry.scale;
      _drawDashedCircle(
        canvas,
        c,
        rIndent,
        Paint()
          ..color = gCol.withValues(alpha: winShine != null ? 0.92 : 0.75)
          ..strokeWidth = (winShine != null ? 2.2 : 1.75) * geometry.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
        dashes: 14,
        duty: 0.58,
      );
      // Hollow outlined 5-point star inside the token indent (no fill)
      _drawStarOutline(
        canvas,
        c,
        outerR: 7.6 * geometry.scale,
        innerR: 3.4 * geometry.scale,
        paint: Paint()
          ..color = gCol
          ..strokeWidth = (winShine != null ? 2.2 : 1.8) * geometry.scale
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      return;
    }

    bool perimWalk = game.usePerimeterWalk && st.isWalkRegime(s);
    Meeple? walkStar = perimWalk ? st.starMeeple(0) : null;
    bool walkMidFlight = perimWalk && walkProgress != null && walkProgress! < 0.62;
    bool walkDragMovedAway = false;
    if (perimWalk && game.drag != null && game.drag!.lines.isNotEmpty) {
      List<Vec2> stops = game.drag!.lines.first.stops;
      if (stops.length >= 2) {
        double total = math.max(1.0, stops.first.distTo(stops.last));
        double cur = stops.first.distTo(game.drag!.curPos);
        walkDragMovedAway = (cur / total) > 0.45;
      }
    }

    bool rel0;
    bool rel1;
    if (perimWalk) {
      bool activeHere =
          walkStar != null && walkStar.at == v.id && !walkMidFlight && !walkDragMovedAway;
      bool hasExits =
          activeHere && Rules.exitsFrom(st, s, v.id, walkStar.from).isNotEmpty;
      rel0 = activeHere && st.turn == 0 && hasExits;
      rel1 = activeHere && st.turn == 1 && hasExits;
    } else {
      rel0 = Rules.canRelease(st, s, v.id, 0);
      rel1 = Rules.canRelease(st, s, v.id, 1);
    }

    bool isAlt = s.alt && v.alt;
    Color ringCol = winShine != null
        ? Color.lerp(youCol, shineCol, 0.68 * bloom)!
        : rel0
            ? youCol
            : rel1
                ? oppCol
                : isAlt
                    ? oppCol
                    : mutedCol;

    double fillBlend = winShine != null
        ? (0.20 + 0.26 * bloom)
        : (rel0 || rel1 || isAlt ? 0.12 : 0.0);
    canvas.drawCircle(
      c,
      r,
      Paint()..color = fillBlend > 0.0 ? Color.lerp(bgCol, ringCol, fillBlend)! : bgCol,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ringCol
        ..strokeWidth = (winShine != null
                ? (3.2 + 1.3 * bloom)
                : (rel0 || rel1 || isAlt ? 3.1 : 2.5)) *
            geometry.scale
        ..style = PaintingStyle.stroke,
    );

    int hv;
    int th;
    bool showCount;
    if (perimWalk) {
      List<Connector> inc = BoardGeometry.incidentConnectors(st, v.id);
      int deg = inc.length;
      bool activeHere =
          walkStar != null && walkStar.at == v.id && !walkMidFlight && !walkDragMovedAway;
      int goalEntryCount = 0;
      int restingStars = 0;
      for (final Connector e in inc) {
        if (BoardGeometry.isGoalEntryFrom(st, s, v.id, e)) {
          goalEntryCount += 1;
          bool arrivedInGoalViaE = walkStar != null &&
              st.verts[walkStar.at]?.goal == 0 &&
              walkStar.from == e.id;
          bool slidingIntoGoalViaE = walkProgress != null &&
              game.walkTransition != null &&
              game.walkTransition!.fromNode == v.id &&
              game.walkTransition!.edgeId == e.id &&
              st.verts[game.walkTransition!.toNode]?.goal == 0;
          if (!arrivedInGoalViaE && !slidingIntoGoalViaE) {
            restingStars += 1;
          }
        }
      }
      if (goalEntryCount > 0) {
        th = math.max(1, deg - 1);
        hv = activeHere ? math.max(deg, restingStars + 1) : restingStars;
      } else {
        th = math.max(0, deg - 1);
        hv = activeHere ? deg : 0;
      }
      showCount = true;
    } else {
      hv = Rules.haveAt(st, v.id);
      th = Rules.thresholdOf(st, s, v.id);
      showCount = !st.isWalkRegime(s) || th > 0;
    }

    // Crossing bridge icon when exit table is active
    if (st.activeExitTable(v.id, s) != null) {
      if (showCount) {
        // Place overpass badge at NW corner (45° clear of orthogonal connectors & NE ∀ badge)
        Offset brCenter = c + Offset(-15.5 * geometry.scale, -15.5 * geometry.scale);
        double brR = 10.0 * geometry.scale;
        Color brCol = winShine != null ? ringCol : (rel0 ? youCol : mutedCol);
        canvas.drawCircle(brCenter, brR, Paint()..color = bgCol);
        canvas.drawCircle(
          brCenter,
          brR,
          Paint()
            ..color = brCol
            ..strokeWidth = 1.9 * geometry.scale
            ..style = PaintingStyle.stroke,
        );
        Paint brStroke = Paint()
          ..color = brCol
          ..strokeWidth = 1.8 * geometry.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        double bd = 5.4 * geometry.scale;
        canvas.drawLine(brCenter - Offset(bd, 0), brCenter + Offset(bd, 0), brStroke);
        canvas.drawLine(
            brCenter - Offset(0, bd), brCenter - Offset(0, 2.3 * geometry.scale), brStroke);
        canvas.drawLine(
            brCenter + Offset(0, 2.3 * geometry.scale), brCenter + Offset(0, bd), brStroke);
      } else {
        Paint br = Paint()
          ..color = ringCol.withValues(alpha: winShine != null ? 0.90 : 0.78)
          ..strokeWidth = 2.1 * geometry.scale
          ..style = PaintingStyle.stroke;
        double d = 10.0 * geometry.scale;
        canvas.drawLine(c - Offset(d, 0), c + Offset(d, 0), br);
        canvas.drawLine(c - Offset(0, d), c - Offset(0, 3.6 * geometry.scale), br);
        canvas.drawLine(c + Offset(0, 3.6 * geometry.scale), c + Offset(0, d), br);
      }
    }

    // Show have/threshold badge inside cell when applicable
    if (showCount) {
      bool overageReady = perimWalk ? (hv > th || (th == 0 && hv > 0)) : (hv >= th && hv > 0);
      _drawCenteredText(
        canvas,
        '$hv/$th',
        c,
        fontSize: math.max(11.5, 13.8 * geometry.scale),
        weight: (winShine != null || overageReady) ? FontWeight.w700 : FontWeight.w600,
        color: winShine != null ? Color.lerp(youCol, fgCol, 0.35)! : fgCol,
      );
    }

    if (isAlt) {
      Color badgeCol = winShine != null ? ringCol : oppCol;
      Offset badge = c + Offset(15.5 * geometry.scale, -15.5 * geometry.scale);
      canvas.drawCircle(badge, 10.0 * geometry.scale, Paint()..color = bgCol);
      canvas.drawCircle(
        badge,
        10.0 * geometry.scale,
        Paint()
          ..color = badgeCol
          ..strokeWidth = 2.0 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        '∀',
        badge,
        fontSize: math.max(10.5, 12.5 * geometry.scale),
        weight: FontWeight.bold,
        color: badgeCol,
      );
    }
  }

  void _drawMeeple(
    Canvas canvas,
    GridBoard st,
    Switches s,
    Meeple p,
    bool yt,
    TreeAction? hint,
    double? winShine,
  ) {
    bool isSliding = walkProgress != null && game.pieceSlide?.pieceId == p.id;
    Vec2 worldPos;
    if (game.drag != null && game.drag!.pieceId == p.id) {
      worldPos = game.drag!.curPos;
    } else if (isSliding) {
      PieceSlideTransition slide = game.pieceSlide!;
      Vec2 endPt = BoardGeometry.seatOf(st, p);
      Vec2 startPt;
      if (slide.startPosOverride != null) {
        startPt = slide.startPosOverride!;
      } else if (slide.fromEdgeId != null && st.edgeOf(slide.fromEdgeId) != null) {
        startPt = BoardGeometry.perimPos(st, slide.fromNode, st.edgeOf(slide.fromEdgeId)!);
      } else if (st.verts[slide.fromNode] != null) {
        CellNode fn = st.verts[slide.fromNode]!;
        startPt = Vec2(fn.x, fn.y);
      } else {
        startPt = endPt;
      }
      double t = Curves.easeOutCubic.transform(walkProgress!.clamp(0.0, 1.0));
      worldPos = Vec2(
        startPt.x + (endPt.x - startPt.x) * t,
        startPt.y + (endPt.y - startPt.y) * t,
      );
    } else {
      worldPos = BoardGeometry.seatOf(st, p);
    }
    Offset c = geometry.toScreen(worldPos.x, worldPos.y);
    bool atOwnGoal = p.star != null && st.verts[p.at]?.goal == p.star;
    double baseR = p.on == null ? 12.6 : (p.w >= 2 ? 14.2 : 12.0);
    double targetR = atOwnGoal ? 12.4 : baseR;
    double unitR = isSliding
        ? (baseR + (targetR - baseR) * Curves.easeOutCubic.transform(walkProgress!.clamp(0.0, 1.0)))
        : targetR;
    double r = unitR * geometry.scale;
    Color col = ownerCol(p.owner);
    List<StepMove> mvs = Rules.movesOf(st, s, p);
    bool midFlightPlayer = isSliding && p.owner == 0 && walkProgress! < 0.88;
    bool inPlayerGoal = atOwnGoal && p.owner == 0;
    bool movable = (yt && p.owner == 0 && mvs.isNotEmpty) || midFlightPlayer || inPlayerGoal;
    bool hinted = hint != null && hint.pieceId == p.id;
    bool lockedOnce = s.once && p.moved && !midFlightPlayer && !inPlayerGoal;
    String glyph = p.star != null ? '★' : '${p.w}';
    double glyphFontSize = math.max(11.0, (p.star != null ? 15.2 : 13.8) * geometry.scale);

    // Victory wave sweep over player tokens
    if (winShine != null && p.owner == 0) {
      double bloom = math.sin(winShine * math.pi);
      Color winTokenCol = Color.lerp(youCol, shineCol, 0.58 * bloom)!;
      if (winShine > 0.01) {
        canvas.drawCircle(
          c,
          r + (3.6 + 5.0 * bloom) * geometry.scale,
          Paint()
            ..color = shineCol.withValues(alpha: 0.55 * winShine)
            ..strokeWidth = 2.8 * geometry.scale
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.drawCircle(c, r, Paint()..color = winTokenCol);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Color.lerp(youCol, shineCol, 0.75 * bloom)!
          ..strokeWidth = 2.6 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        glyph,
        c,
        fontSize: glyphFontSize,
        weight: FontWeight.bold,
        color: Colors.white,
      );
      return;
    }

    // Movable (or hinted) player meeple: vibrant player color + bright outer halo
    if (movable || hinted) {
      canvas.drawCircle(
        c,
        r + 4.4 * geometry.scale,
        Paint()
          ..color = (hinted ? hintCol : col).withValues(alpha: 0.42)
          ..strokeWidth = 2.8 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(c, r, Paint()..color = col);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = hinted ? hintCol : Color.lerp(col, isDark ? Colors.white : Colors.black, 0.16)!
          ..strokeWidth = 2.6 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        glyph,
        c,
        fontSize: glyphFontSize,
        weight: FontWeight.bold,
        color: Colors.white,
      );
      return;
    }

    // Non-movable meeple: slight grey-ness blended into green/purple + crisp grey ring
    bool oppCanMove = p.owner == 1 && Rules.realMoves(st, s, p).isNotEmpty;
    if (oppCanMove) {
      canvas.drawCircle(c, r, Paint()..color = col);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = col
          ..strokeWidth = 2.4 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        glyph,
        c,
        fontSize: glyphFontSize,
        weight: FontWeight.bold,
        color: Colors.white,
      );
      return;
    }

    Color mutedFill = Color.lerp(col, neutralGrey, 0.50)!;
    Color bodyFill = lockedOnce ? Color.lerp(bgCol, mutedFill, 0.34)! : mutedFill;

    canvas.drawCircle(c, r + 1.1 * geometry.scale, Paint()..color = bgCol);
    canvas.drawCircle(
      c,
      math.max(3.0, r - 1.1 * geometry.scale),
      Paint()..color = bodyFill,
    );
    canvas.drawCircle(
      c,
      r + 0.8 * geometry.scale,
      Paint()
        ..color = greyRingCol
        ..strokeWidth = 2.9 * geometry.scale
        ..style = PaintingStyle.stroke,
    );

    _drawCenteredText(
      canvas,
      glyph,
      c,
      fontSize: glyphFontSize,
      weight: FontWeight.bold,
      color: lockedOnce ? mutedFill : Colors.white.withValues(alpha: 0.92),
    );
  }

  void _drawWalkPerimeterTokens(
    Canvas canvas,
    GridBoard st,
    Switches s,
    bool yt,
    TreeAction? hint,
    Map<String, double>? hopDist,
    double waveFront,
  ) {
    Meeple? star = st.starMeeple(0);
    if (star == null) return;
    if (st.isBox(star.at)) {
      _drawMeeple(canvas, st, s, star, yt, hint, null);
      return;
    }

    double? shineForCell(String cid) {
      if (hopDist == null) return null;
      double? d = hopDist[cid];
      if (d == null) return null;
      double dp = d + 0.22;
      return waveFront >= dp ? (1.0 - ((waveFront - dp) / _kShimmerBand).clamp(0.0, 1.0)) : null;
    }

    WalkTransition? trans = game.walkTransition;
    bool inTransition = trans != null && walkProgress != null && st.edgeOf(trans.edgeId) != null;

    // Resting greyed-out ★ tokens at all unvisited 1-hop-from-goal nodes
    for (final CellNode uNode in st.verts.values) {
      if (uNode.isBox || uNode.goal != null) continue;
      if (inTransition && (uNode.id == trans.fromNode || uNode.id == trans.toNode)) continue;
      if (!inTransition && uNode.id == star.at) continue;
      for (final Connector e in BoardGeometry.incidentConnectors(st, uNode.id)) {
        if (!BoardGeometry.isGoalEntryFrom(st, s, uNode.id, e)) continue;
        if (st.verts[star.at]?.goal == 0 && star.from == e.id) continue;
        Vec2 pos = BoardGeometry.perimPos(st, uNode.id, e);
        _drawCoupledUnitToken(
          canvas,
          pos,
          glyph: '★',
          movable: false,
          hinted: hint != null && hint.edge == e.id,
          winShine: shineForCell(uNode.id),
          opacity: 1.0,
          scaleFactor: 1.0,
        );
      }
    }

    // 1. Animated slide transition between two nodes
    if (inTransition) {
      Connector edge = st.edgeOf(trans.edgeId)!;
      double p = walkProgress!.clamp(0.0, 1.0);
      // Departing sibling tokens vanish (while resting ★ stays locked if walking away from pre-goal!)
      for (final Connector e in BoardGeometry.incidentConnectors(st, trans.fromNode)) {
        if (e.id == trans.edgeId) continue;
        if (BoardGeometry.isGoalEntryFrom(st, s, trans.fromNode, e)) {
          Vec2 pos = BoardGeometry.perimPos(st, trans.fromNode, e);
          _drawCoupledUnitToken(
            canvas,
            pos,
            glyph: '★',
            movable: false,
            hinted: false,
            winShine: shineForCell(trans.fromNode),
            opacity: 1.0,
            scaleFactor: 1.0,
          );
          continue;
        }
        if (trans.startPosOverride == null && p < 0.45) {
          double vanish = (1.0 - p / 0.45).clamp(0.0, 1.0);
          Vec2 pos = BoardGeometry.perimPos(st, trans.fromNode, e);
          _drawCoupledUnitToken(
            canvas,
            pos,
            movable: false,
            hinted: false,
            winShine: null,
            opacity: vanish,
            scaleFactor: 0.58 + 0.42 * vanish,
          );
        }
      }

      // Arriving node's other perimeter tokens appear (unless arriving into the Goal socket itself!)
      CellNode? toCell = st.verts[trans.toNode];
      Set<String> destLegal = {
        for (final Connector e in Rules.exitsFrom(st, s, trans.toNode, trans.edgeId)) e.id,
      };
      if (toCell != null && toCell.goal == null) {
        for (final Connector e in BoardGeometry.incidentConnectors(st, trans.toNode)) {
          if (e.id == trans.edgeId) continue;
          if (BoardGeometry.isGoalEntryFrom(st, s, trans.toNode, e)) {
            Vec2 pos = BoardGeometry.perimPos(st, trans.toNode, e);
            bool unlockedNow = p > 0.56 && yt && destLegal.contains(e.id);
            double wakeBoost = p > 0.56
                ? 1.0 + 0.08 * math.sin(((p - 0.56) / 0.44).clamp(0.0, 1.0) * math.pi)
                : 1.0;
            _drawCoupledUnitToken(
              canvas,
              pos,
              glyph: '★',
              movable: unlockedNow,
              hinted: false,
              winShine: shineForCell(trans.toNode),
              opacity: 1.0,
              scaleFactor: wakeBoost,
            );
            continue;
          }
          if (p > 0.56) {
            double appear = ((p - 0.56) / 0.44).clamp(0.0, 1.0);
            double popScale = 0.62 + 0.38 * Curves.easeOutBack.transform(appear).clamp(0.0, 1.12);
            Vec2 pos = BoardGeometry.perimPos(st, trans.toNode, e);
            _drawCoupledUnitToken(
              canvas,
              pos,
              movable: yt && destLegal.contains(e.id),
              hinted: false,
              winShine: shineForCell(trans.toNode),
              opacity: appear,
              scaleFactor: popScale,
            );
          }
        }
      }

      // The selected perimeter token itself sliding along the connector (or into the Goal socket!)
      Vec2 startPt = trans.startPosOverride ?? BoardGeometry.perimPos(st, trans.fromNode, edge);
      Vec2 endPt = (toCell != null && toCell.goal != null)
          ? Vec2(toCell.x, toCell.y)
          : BoardGeometry.perimPos(st, trans.toNode, edge);
      double slideT = Curves.easeInOutCubic.transform(p);
      Vec2 curPt = Vec2(
        startPt.x + (endPt.x - startPt.x) * slideT,
        startPt.y + (endPt.y - startPt.y) * slideT,
      );
      bool slidingToGoal = toCell != null && toCell.goal == 0;
      bool movableAtEnd = p < 0.88 || slidingToGoal || (yt && destLegal.contains(trans.edgeId));
      _drawCoupledUnitToken(
        canvas,
        curPt,
        glyph: slidingToGoal ? '★' : '1',
        movable: movableAtEnd,
        hinted: false,
        winShine: p >= 0.82 ? shineForCell(trans.toNode) : null,
        opacity: 1.0,
        scaleFactor: 1.0,
      );
      return;
    }

    // 2. Live finger/mouse drag along a chosen connector
    MeepleDragState? d = game.drag;
    if (d != null && d.lines.isNotEmpty && d.lines.first.edgeId != null) {
      DragLine line = d.lines.first;
      String dragEdgeId = line.edgeId!;
      double total = line.stops.length >= 2 ? math.max(1.0, line.stops.first.distTo(line.stops.last)) : 1.0;
      double uDrag = (line.stops.first.distTo(d.curPos) / total).clamp(0.0, 1.0);
      double sibAlpha = (1.0 - uDrag * 2.1).clamp(0.0, 1.0);
      Set<String> legalIds = {
        for (final Connector e in Rules.exitsFrom(st, s, star.at, star.from)) e.id,
      };
      for (final Connector e in BoardGeometry.incidentConnectors(st, star.at)) {
        if (e.id == dragEdgeId) continue;
        if (BoardGeometry.isGoalEntryFrom(st, s, star.at, e)) {
          Vec2 pos = BoardGeometry.perimPos(st, star.at, e);
          _drawCoupledUnitToken(
            canvas,
            pos,
            glyph: '★',
            movable: uDrag < 0.45 && yt && legalIds.contains(e.id),
            hinted: false,
            winShine: null,
            opacity: 1.0,
            scaleFactor: 1.0,
          );
          continue;
        }
        if (sibAlpha > 0.02) {
          Vec2 pos = BoardGeometry.perimPos(st, star.at, e);
          _drawCoupledUnitToken(
            canvas,
            pos,
            movable: yt && legalIds.contains(e.id),
            hinted: false,
            winShine: null,
            opacity: sibAlpha,
            scaleFactor: 0.62 + 0.38 * sibAlpha,
          );
        }
      }
      // Subtle preview of next node's perimeter tokens when dragged near arrival
      Connector? dragConn = st.edgeOf(dragEdgeId);
      if (dragConn != null && uDrag > 0.65) {
        String destNode = dragConn.farOf(star.at);
        CellNode? destCell = st.verts[destNode];
        if (destCell != null && destCell.goal == null) {
          double preAlpha = ((uDrag - 0.65) / 0.35) * 0.55;
          Set<String> destLegal = {
            for (final Connector e in Rules.exitsFrom(st, s, destNode, dragEdgeId)) e.id,
          };
          for (final Connector e in BoardGeometry.incidentConnectors(st, destNode)) {
            if (e.id == dragEdgeId) continue;
            if (BoardGeometry.isGoalEntryFrom(st, s, destNode, e)) continue;
            Vec2 pos = BoardGeometry.perimPos(st, destNode, e);
            _drawCoupledUnitToken(
              canvas,
              pos,
              movable: destLegal.contains(e.id),
              hinted: false,
              winShine: null,
              opacity: preAlpha,
              scaleFactor: 0.72 + 0.25 * ((uDrag - 0.65) / 0.35),
            );
          }
        }
      }
      bool dragIntoGoal =
          dragConn != null && BoardGeometry.isGoalEntryFrom(st, s, star.at, dragConn);
      _drawCoupledUnitToken(
        canvas,
        d.curPos,
        glyph: dragIntoGoal ? '★' : '1',
        movable: true,
        hinted: hint != null && hint.edge == dragEdgeId,
        winShine: null,
        opacity: 1.0,
        scaleFactor: 1.04,
      );
      return;
    }

    // 3. Resting state: if solved at Goal cell, draw winning ★ nestled in Goal indent!
    CellNode? curCell = st.verts[star.at];
    if (curCell != null && curCell.goal != null) {
      _drawCoupledUnitToken(
        canvas,
        Vec2(curCell.x, curCell.y),
        glyph: '★',
        movable: true,
        hinted: false,
        winShine: shineForCell(star.at),
        opacity: 1.0,
        scaleFactor: 1.03,
      );
      return;
    }

    // Otherwise draw coupled perimeter tokens on all incident edges of the active node
    List<Connector> inc = BoardGeometry.incidentConnectors(st, star.at);
    Set<String> legalIds = {
      for (final Connector e in Rules.exitsFrom(st, s, star.at, star.from)) e.id,
    };
    double? winShine = shineForCell(star.at);
    for (final Connector e in inc) {
      Vec2 pos = BoardGeometry.perimPos(st, star.at, e);
      bool isGoalEntry = BoardGeometry.isGoalEntryFrom(st, s, star.at, e);
      bool movable = yt && legalIds.contains(e.id);
      bool hinted = hint != null && hint.edge == e.id;
      _drawCoupledUnitToken(
        canvas,
        pos,
        glyph: isGoalEntry ? '★' : '1',
        movable: movable,
        hinted: hinted,
        winShine: winShine,
        opacity: 1.0,
        scaleFactor: 1.0,
      );
    }
  }

  void _drawCoupledUnitToken(
    Canvas canvas,
    Vec2 worldPos, {
    String glyph = '1',
    required bool movable,
    required bool hinted,
    required double? winShine,
    required double opacity,
    required double scaleFactor,
  }) {
    double a = opacity.clamp(0.0, 1.0);
    if (a <= 0.01) return;
    Offset c = geometry.toScreen(worldPos.x, worldPos.y);
    double r = 12.0 * geometry.scale * scaleFactor;
    Color col = youCol;
    double baseFont = glyph == '★' ? 15.2 : 13.8;
    double glyphFontSize = math.max(10.0, baseFont * geometry.scale * scaleFactor);

    if (winShine != null) {
      double bloom = math.sin(winShine * math.pi);
      Color winTokenCol = Color.lerp(youCol, shineCol, 0.58 * bloom)!.withValues(alpha: a);
      if (winShine > 0.01) {
        canvas.drawCircle(
          c,
          r + (3.6 + 5.0 * bloom) * geometry.scale,
          Paint()
            ..color = shineCol.withValues(alpha: 0.55 * winShine * a)
            ..strokeWidth = 2.8 * geometry.scale
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.drawCircle(c, r, Paint()..color = winTokenCol);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Color.lerp(youCol, shineCol, 0.75 * bloom)!.withValues(alpha: a)
          ..strokeWidth = 2.6 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        glyph,
        c,
        fontSize: glyphFontSize,
        weight: FontWeight.bold,
        color: Colors.white.withValues(alpha: a),
      );
      return;
    }

    if (movable || hinted) {
      canvas.drawCircle(
        c,
        r + 4.4 * geometry.scale * scaleFactor,
        Paint()
          ..color = (hinted ? hintCol : col).withValues(alpha: 0.42 * a)
          ..strokeWidth = 2.8 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(c, r, Paint()..color = col.withValues(alpha: a));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = (hinted ? hintCol : Color.lerp(col, isDark ? Colors.white : Colors.black, 0.16)!)
              .withValues(alpha: a)
          ..strokeWidth = 2.6 * geometry.scale
          ..style = PaintingStyle.stroke,
      );
      _drawCenteredText(
        canvas,
        glyph,
        c,
        fontSize: glyphFontSize,
        weight: FontWeight.bold,
        color: Colors.white.withValues(alpha: a),
      );
      return;
    }

    Color mutedFill = Color.lerp(col, neutralGrey, 0.50)!;
    canvas.drawCircle(
      c,
      r + 1.1 * geometry.scale * scaleFactor,
      Paint()..color = bgCol.withValues(alpha: a),
    );
    canvas.drawCircle(
      c,
      math.max(3.0, r - 1.1 * geometry.scale * scaleFactor),
      Paint()..color = mutedFill.withValues(alpha: a),
    );
    canvas.drawCircle(
      c,
      r + 0.8 * geometry.scale * scaleFactor,
      Paint()
        ..color = greyRingCol.withValues(alpha: a)
        ..strokeWidth = 2.9 * geometry.scale
        ..style = PaintingStyle.stroke,
    );
    _drawCenteredText(
      canvas,
      glyph,
      c,
      fontSize: glyphFontSize,
      weight: FontWeight.bold,
      color: Colors.white.withValues(alpha: 0.92 * a),
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    int dashes = 14,
    double duty = 0.58,
  }) {
    if (radius <= 1.0) return;
    Rect rect = Rect.fromCircle(center: center, radius: radius);
    double step = (2.0 * math.pi) / dashes;
    double sweep = step * duty;
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(rect, -math.pi / 2.0 + i * step, sweep, false, paint);
    }
  }

  void _drawStarOutline(
    Canvas canvas,
    Offset center, {
    required double outerR,
    required double innerR,
    required Paint paint,
  }) {
    Path path = Path();
    for (int i = 0; i < 10; i++) {
      double ang = -math.pi / 2.0 + i * (math.pi / 5.0);
      double rad = i.isEven ? outerR : innerR;
      Offset pt = center + Offset(math.cos(ang) * rad, math.sin(ang) * rad);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawTileLegend(Canvas canvas, GridBoard st, Switches s) {
    TileDef gad = st.tileDef ?? TileDef.defaultTile;
    double top = geometry.legendTop;
    double h = math.max(42.0, geometry.canvasHeight - top - 4.0);
    Rect bar = Rect.fromLTWH(8.0, top, geometry.canvasWidth - 16.0, h);
    RRect rr = RRect.fromRectAndRadius(bar, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..color = colors.surfaceContainerHighest.withValues(alpha: 0.50));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = lineCol
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke,
    );

    int openCells = st.openCellCount;
    int boxes = st.foldedBoxCount;
    int totalCells = openCells + boxes * 4;
    String summary = boxes > 0
        ? 'Tile A (2×2): $openCells cells + $boxes folded box${boxes == 1 ? '' : 'es'} ($totalCells unfolded)'
        : 'Tile A (2×2): all $totalCells cells unfolded (${gad.pairs.length} connectors/tile)';

    _drawCenteredText(
      canvas,
      summary,
      bar.center,
      fontSize: 13.0,
      color: mutedCol,
    );
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset tip, Color col, double size) {
    double len = (tip - from).distance;
    if (len < 0.5) return;
    Offset u = (tip - from) / len;
    Offset n = Offset(-u.dy, u.dx);
    Path path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - u.dx * size - n.dx * (size * 0.46), tip.dy - u.dy * size - n.dy * (size * 0.46))
      ..lineTo(tip.dx - u.dx * size + n.dx * (size * 0.46), tip.dy - u.dy * size + n.dy * (size * 0.46))
      ..close();
    canvas.drawPath(path, Paint()..color = col);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dash, double gap) {
    double dist = (p2 - p1).distance;
    if (dist <= 0.5) return;
    Offset dir = (p2 - p1) / dist;
    double step = math.max(2.0, dash + gap);
    for (double t = 0.0; t < dist; t += step) {
      double end = math.min(dist, t + math.max(1.0, dash));
      canvas.drawLine(p1 + dir * t, p1 + dir * end, paint);
    }
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
    FontWeight weight = FontWeight.normal,
    required Color color,
  }) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color, height: 1.0),
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2.0, tp.height / 2.0));
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
