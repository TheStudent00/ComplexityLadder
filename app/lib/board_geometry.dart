import 'dart:math' as math;
import 'dart:ui';

import 'package:ladder_core/ladder_core.dart';

import 'game_state.dart';

class EndAnchor {
  final double x;
  final double y;
  final double r;

  const EndAnchor(this.x, this.y, this.r);
}

/// Maps logical n x n grid coordinates (`kGridPitch = 110`) to a responsive
/// Flutter canvas and provides exact hit-testing for connectors, boxes, and meeples.
class BoardGeometry {
  static const double kWorldMargin = 28.0;
  static const double kNodeRadius = 18.5;

  final double canvasWidth;
  final double canvasHeight;
  final int gridN;
  final bool showTileLegend;
  late final double scaleX;
  late final double scaleY;
  late final double scale;
  late final double tx;
  late final double ty;
  late final double legendTop;

  BoardGeometry({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.gridN,
    required this.showTileLegend,
  }) {
    double worldSpan = (gridN - 1) * kGridPitch + kWorldMargin * 2.0;
    double legendReserve = showTileLegend ? math.min(64.0, canvasHeight * 0.17) : 4.0;
    double availH = math.max(80.0, canvasHeight - legendReserve);
    double availW = math.max(80.0, canvasWidth - 4.0);
    double rawScaleX = availW / worldSpan;
    double rawScaleY = availH / worldSpan;
    if (rawScaleY >= rawScaleX) {
      scaleX = rawScaleX;
      scaleY = math.min(rawScaleY, scaleX * 1.28);
    } else {
      scaleY = rawScaleY;
      scaleX = math.min(rawScaleX, scaleY * 1.20);
    }
    scale = math.min(scaleX, scaleY);
    double usedW = worldSpan * scaleX;
    double usedH = worldSpan * scaleY;
    tx = (canvasWidth - usedW) / 2.0 + kWorldMargin * scaleX;
    ty = (availH - usedH) / 2.0 + kWorldMargin * scaleY;
    legendTop = availH + 2.0;
  }

  Size get canvasSize => Size(canvasWidth, canvasHeight);

  Offset toScreen(double bx, double by) => Offset(tx + bx * scaleX, ty + by * scaleY);

  Vec2 toBoard(Offset local) => Vec2((local.dx - tx) / scaleX, (local.dy - ty) / scaleY);

  static EndAnchor endOf(GridBoard st, Connector e, String vid) {
    CellNode? v = st.verts[vid];
    if (v == null) return const EndAnchor(0, 0, kNodeRadius);
    if (v.isBox) {
      String pName = (e.u == vid ? e.uport : e.vport) ?? 'p1';
      TilePortDef pt = TileDef.basePorts[pName] ?? TileDef.basePorts['p1']!;
      Vec2 p = gadOffset(v, pt.dx, pt.dy);
      return EndAnchor(p.x, p.y, 4.0);
    }
    return EndAnchor(v.x, v.y, kNodeRadius);
  }

  static Vec2 perimPos(GridBoard st, String vid, Connector e) {
    EndAnchor a = endOf(st, e, vid);
    EndAnchor b = endOf(st, e, e.farOf(vid));
    double dx = b.x - a.x;
    double dy = b.y - a.y;
    double len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) len = 1.0;
    double d = (len * 0.34).clamp(a.r + 16.5, a.r + 22.0);
    return Vec2(a.x + dx / len * d, a.y + dy / len * d);
  }

  static Vec2 posOf(GridBoard st, Meeple p) {
    CellNode? v = st.verts[p.at];
    if (v == null) return const Vec2(0, 0);
    if (p.on == null || (p.star != null && v.goal == p.star)) {
      if (v.isBox) {
        return gadOffset(v, -34.0, -34.0);
      }
      return Vec2(v.x, v.y);
    }
    Connector? e = st.edgeOf(p.on);
    if (e == null) return Vec2(v.x, v.y);
    Vec2 q = perimPos(st, p.at, e);
    List<Meeple> coPeers = st.pieces.where((x) => x.at == p.at && x.on == p.on).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (coPeers.length < 2) return q;
    EndAnchor a = endOf(st, e, p.at);
    EndAnchor b = endOf(st, e, e.farOf(p.at));
    double len = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    if (len == 0) len = 1.0;
    double nx = -(b.y - a.y) / len;
    double ny = (b.x - a.x) / len;
    int idx = coPeers.indexWhere((x) => x.id == p.id);
    double k = idx - (coPeers.length - 1) / 2.0;
    return Vec2(q.x + nx * 16.5 * k, q.y + ny * 16.5 * k);
  }

  static Vec2 seatOf(GridBoard st, Meeple p) {
    return posOf(st, p);
  }

  static double alongT(GridBoard st, String vid, Connector e, Vec2 q) {
    EndAnchor a = endOf(st, e, vid);
    EndAnchor b = endOf(st, e, e.farOf(vid));
    double dx = b.x - a.x;
    double dy = b.y - a.y;
    double l2 = dx * dx + dy * dy;
    if (l2 == 0) l2 = 1.0;
    return ((q.x - a.x) * dx + (q.y - a.y) * dy) / l2;
  }

  static List<DragLine> buildDragLines(GridBoard st, Switches s, Meeple p) {
    List<StepMove> mvs = Rules.movesOf(st, s, p);
    List<DragLine> lines = [];
    for (final StepMove first in mvs) {
      if (first.kind == 'unfold') continue;
      GridBoard c = st.clone();
      Meeple cp = c.pieceOf(p.id)!;
      List<Vec2> stops = [seatOf(st, p)];
      List<StepMove> seq = [];
      String? edgeId = first.kind == 'in' ? p.on : first.edge;
      StepMove? mv = first;
      while (mv != null) {
        Rules.applyStep(cp, mv);
        seq.add(mv);
        stops.add(seatOf(c, cp));
        String? nextKind = mv.kind == 'out' ? 'slide' : (mv.kind == 'slide' ? 'in' : null);
        mv = nextKind == null
            ? null
            : Rules.movesOf(c, s, cp).where((m) => m.kind == nextKind).firstOrNull;
      }
      lines.add(DragLine(
        stops: stops,
        seq: seq,
        edgeId: edgeId,
        crosses: seq.any((m) => m.kind == 'slide'),
      ));
    }
    return lines;
  }

  static List<Connector> incidentConnectors(GridBoard st, String vid) {
    CellNode? v = st.verts[vid];
    if (v == null || v.isBox) return const [];
    return [
      for (final Connector e in st.edges)
        if (e.touches(vid)) e,
    ];
  }

  /// True when connector `e` at non-goal cell `u` leads directly into player Goal (`goal == 0`).
  static bool isGoalEntryFrom(GridBoard st, Switches s, String u, Connector e) {
    if (!e.touches(u)) return false;
    CellNode? uNode = st.verts[u];
    if (uNode == null || uNode.isBox || uNode.goal != null) return false;
    CellNode? farNode = st.verts[e.farOf(u)];
    if (farNode == null || farNode.goal != 0) return false;
    if (s.directed && !e.arrowFrom(u)) return false;
    return true;
  }

  static DragLine buildWalkPerimeterDragLine(GridBoard st, Meeple star, Connector e) {
    String far = e.farOf(star.at);
    CellNode? farNode = st.verts[far];
    Vec2 endStop = (farNode != null && farNode.goal != null)
        ? Vec2(farNode.x, farNode.y)
        : perimPos(st, far, e);
    return DragLine(
      stops: [perimPos(st, star.at, e), endStop],
      seq: [StepMove.out(e.id), StepMove.slide(e.id, far), const StepMove.enter()],
      edgeId: e.id,
      crosses: true,
    );
  }

  /// Find a movable coupled-perimeter walk token hit at `boardPt` (for `L`, `NL`, `P`).
  Connector? hitWalkPerimeterToken(
    GridBoard st,
    Switches s,
    Vec2 boardPt, {
    bool forDrag = false,
  }) {
    Meeple? star = st.starMeeple(0);
    if (star == null || st.isBox(star.at)) return null;
    List<Connector> legal = Rules.exitsFrom(st, s, star.at, star.from);
    if (legal.isEmpty) return null;
    double hitR = forDrag
        ? math.max(15.5, 14.5 / math.max(0.65, scale))
        : math.max(24.0, 22.0 / math.max(0.45, scale));
    Connector? best;
    double bestD = hitR;
    for (final Connector e in legal) {
      if (st.isBox(e.farOf(star.at))) continue;
      Vec2 seat = perimPos(st, star.at, e);
      double d = seat.distTo(boardPt);
      if (d <= bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  /// Find a player meeple hit at `boardPt`, if movable.
  Meeple? hitMovableMeeple(
    GridBoard st,
    Switches s,
    Vec2 boardPt, {
    bool forDrag = false,
  }) {
    double hitR = forDrag
        ? math.max(15.5, 14.5 / math.max(0.65, scale))
        : math.max(24.0, 22.0 / math.max(0.45, scale));
    Meeple? best;
    double bestD = hitR;
    for (final Meeple p in st.pieces) {
      if (p.owner != 0) continue;
      if (Rules.movesOf(st, s, p).isEmpty) continue;
      Vec2 seat = seatOf(st, p);
      double d = seat.distTo(boardPt);
      if (d <= bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  /// Find a folded 2x2 tile box ('A1' or 'A2') containing `boardPt`.
  String? hitFoldedBox(GridBoard st, Vec2 boardPt) {
    for (final CellNode v in st.verts.values) {
      if (!v.isBox) continue;
      if ((boardPt.x - v.x).abs() <= kBoxHalf && (boardPt.y - v.y).abs() <= kBoxHalf) {
        return v.id;
      }
    }
    return null;
  }

  /// Find the nearest legal clickable connector within a generous touch/hover corridor.
  Connector? hitLegalConnector(GridBoard st, Switches s, Vec2 boardPt) {
    double maxDist = math.max(26.0, 22.0 / math.max(0.45, scale));
    Connector? best;
    double bestD = maxDist;
    for (final Connector e in st.edges) {
      if (Rules.connectorActionsOf(st, s, e).isEmpty) continue;
      EndAnchor a = endOf(st, e, e.u);
      EndAnchor b = endOf(st, e, e.v);
      double dx = b.x - a.x;
      double dy = b.y - a.y;
      double len = math.sqrt(dx * dx + dy * dy);
      if (len <= a.r + b.r) continue;
      double ux = dx / len;
      double uy = dy / len;
      Vec2 p1 = Vec2(a.x + ux * (a.r + 2.5), a.y + uy * (a.r + 2.5));
      Vec2 p2 = Vec2(b.x - ux * (b.r + 2.5), b.y - uy * (b.r + 2.5));
      double segDx = p2.x - p1.x;
      double segDy = p2.y - p1.y;
      double l2 = segDx * segDx + segDy * segDy;
      double u = l2 == 0
          ? 0.0
          : (((boardPt.x - p1.x) * segDx + (boardPt.y - p1.y) * segDy) / l2).clamp(0.0, 1.0);
      Vec2 proj = Vec2(p1.x + segDx * u, p1.y + segDy * u);
      double d = proj.distTo(boardPt);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }
}
