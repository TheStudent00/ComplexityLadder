import 'dart:math' as math;

import 'board.dart';
import 'random32.dart';
import 'solver.dart';
import 'switches.dart';

class SynthRequest {
  final Switches switches;
  final int n;
  final int seed;

  const SynthRequest({required this.switches, required this.n, required this.seed});
}

class Puzzle {
  final GridBoard board;
  final List<String> log;

  const Puzzle({required this.board, required this.log});
}

class _ConnSpec {
  final String u;
  final String v;
  final int w;
  final bool atV;
  final int owner;
  final int? star;

  const _ConnSpec({
    required this.u,
    required this.v,
    required this.w,
    required this.atV,
    required this.owner,
    this.star,
  });

  String get restingCell => atV ? v : u;
  String get targetCell => atV ? u : v;

  _ConnSpec canonical() {
    var (String cu, String cv) = canonPair(u, v);
    return _ConnSpec(
      u: cu,
      v: cv,
      w: w,
      atV: cu == u ? atV : !atV,
      owner: owner,
      star: star,
    );
  }
}

class _BoxSpec {
  final String id; // 'A1', 'A2', 'A3', 'A4'
  final Map<String, String> cellMap; // 'n00'..'n11' -> grid cell id
  final int owner;
  final bool rot180;
  final Set<String> allowedPortSlots; // canonical 'u-v' slots matching TileDef.basePorts

  const _BoxSpec({
    required this.id,
    required this.cellMap,
    required this.owner,
    required this.rot180,
    required this.allowedPortSlots,
  });
}

class _FoldSpec {
  final List<_BoxSpec> boxes;
  final int sym;
  final TileDef tileDef;

  const _FoldSpec({
    required this.boxes,
    required this.sym,
    required this.tileDef,
  });
}

class Synthesis {
  // ---- Fast Bitmask Solver Probes (64-bit safe up to 60 connectors) ----

  static (int?, List<int>, int) _probe1P(
    String goal0,
    List<_ConnSpec> conn,
    int thrVal,
    bool onceFlag, {
    int cap = 2600,
  }) {
    int initOm = 0;
    for (int i = 0; i < conn.length; i++) {
      if (conn[i].atV) initOm |= (1 << i);
    }
    String headOf(int i, int om) => ((om & (1 << i)) != 0) ? conn[i].v : conn[i].u;
    bool isWin(int om) {
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].star == 0 && headOf(i, om) == goal0) return true;
      }
      return false;
    }

    int startS = onceFlag ? 0 : initOm;
    Map<int, (int, int)?> prev = {startS: null};
    List<int> q = [startS];
    int qi = 0;
    int? goalS;
    while (qi < q.length && prev.length < cap) {
      int s = q[qi++];
      int om = onceFlag ? (initOm ^ s) : s;
      int mm = onceFlag ? s : 0;
      if (isWin(om)) {
        goalS ??= s;
        continue;
      }
      Map<String, int> hv = {};
      for (int i = 0; i < conn.length; i++) {
        String h = headOf(i, om);
        hv[h] = (hv[h] ?? 0) + conn[i].w;
      }
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].owner != 0) continue;
        if (onceFlag && ((mm & (1 << i)) != 0)) continue;
        String h = headOf(i, om);
        int need = h == goal0 ? 0 : thrVal;
        if ((hv[h] ?? 0) - conn[i].w >= need) {
          int ns = s ^ (1 << i);
          if (!prev.containsKey(ns)) {
            prev[ns] = (s, i);
            q.add(ns);
          }
        }
      }
    }
    if (prev.length >= cap || goalS == null) return (null, const [], prev.length);
    List<int> path = [];
    int cur = goalS;
    while (prev[cur] != null) {
      var (int ps, int idx) = prev[cur]!;
      path.add(idx);
      cur = ps;
    }
    return (path.length, path.reversed.toList(), prev.length);
  }

  static (int?, List<(String, int?)>, int) _probe2P(
    String goal0,
    String goal1,
    List<_ConnSpec> conn,
    int thrVal, {
    int cap = 2200,
  }) {
    int initOm = 0;
    for (int i = 0; i < conn.length; i++) {
      if (conn[i].atV) initOm |= (1 << i);
    }
    String headOf(int i, int om) => ((om & (1 << i)) != 0) ? conn[i].v : conn[i].u;
    int? winMask(int om) {
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].star == 0 && headOf(i, om) == goal0) return 0;
        if (conn[i].star == 1 && headOf(i, om) == goal1) return 1;
      }
      return null;
    }

    List<(int, int)> legalFor(int mv, int om) {
      Map<String, int> hv = {};
      for (int i = 0; i < conn.length; i++) {
        String h = headOf(i, om);
        hv[h] = (hv[h] ?? 0) + conn[i].w;
      }
      List<(int, int)> out = [];
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].owner != mv) continue;
        String h = headOf(i, om);
        int need = (h == goal0 || h == goal1) ? 0 : thrVal;
        if ((hv[h] ?? 0) - conn[i].w >= need) out.add((i, om ^ (1 << i)));
      }
      return out;
    }

    String startK = '0|$initOm';
    Map<String, (int, int, int?)> meta = {startK: (0, initOm, winMask(initOm))};
    Map<String, List<(String, String)>> succ = {};
    List<String> q = [startK];
    int qi = 0;
    while (qi < q.length && meta.length < cap) {
      String k = q[qi++];
      if (succ.containsKey(k)) continue;
      var (int mv, int om, int? win) = meta[k]!;
      if (win != null) {
        succ[k] = const [];
        continue;
      }
      List<(int, int)> mvs = legalFor(mv, om);
      List<(String, String)> outs = [];
      if (mvs.isEmpty) {
        if (mv == 1 && legalFor(0, om).isNotEmpty) {
          String nk = '0|$om';
          meta.putIfAbsent(nk, () {
            q.add(nk);
            return (0, om, winMask(om));
          });
          outs.add(('pass', nk));
        }
      } else {
        for (final (int idx, int nom) in mvs) {
          String nk = '${1 - mv}|$nom';
          meta.putIfAbsent(nk, () {
            q.add(nk);
            return (1 - mv, nom, winMask(nom));
          });
          outs.add(('$idx', nk));
        }
      }
      succ[k] = outs;
    }
    if (meta.length >= cap) return (null, const [], meta.length);

    Map<String, int> dist = {};
    for (final entry in meta.entries) {
      if (entry.value.$3 == 0) dist[entry.key] = 0;
    }
    bool changed = true;
    while (changed) {
      changed = false;
      for (final entry in succ.entries) {
        String k = entry.key;
        List<(String, String)> outs = entry.value;
        var (int mv, _, int? win) = meta[k]!;
        if (win != null || outs.isEmpty) continue;
        if (mv == 0) {
          int? best;
          for (final (_, String nk) in outs) {
            int? d = dist[nk];
            if (d != null && (best == null || d + 1 < best)) best = d + 1;
          }
          if (best != null && (!dist.containsKey(k) || best < dist[k]!)) {
            dist[k] = best;
            changed = true;
          }
        } else {
          bool allIn = true;
          int worst = 0;
          for (final (_, String nk) in outs) {
            int? d = dist[nk];
            if (d == null) {
              allIn = false;
              break;
            }
            if (d + 1 > worst) worst = d + 1;
          }
          if (allIn && (!dist.containsKey(k) || worst < dist[k]!)) {
            dist[k] = worst;
            changed = true;
          }
        }
      }
    }
    int? d0 = dist[startK];
    List<(String, int?)> d1Outs =
        (succ[startK] ?? const []).map((o) => (o.$1, dist[o.$2])).toList();
    return (d0, d1Outs, meta.length);
  }

  // ---- Grid Topology & Full-Span Helpers ----

  static String _slotKey(String a, String b) {
    var (String cu, String cv) = canonPair(a, b);
    return '$cu-$cv';
  }

  static int _manhattan(String a, String b) {
    var (int ax, int ay) = parseCell(a);
    var (int bx, int by) = parseCell(b);
    return (ax - bx).abs() + (ay - by).abs();
  }

  /// Verifies that the active edges touch all `n` columns and all `n` rows so
  /// larger boards (`5x5`, `6x6`) genuinely span the full grid rather than clustering.
  static bool _spansAllRowsAndCols(int n, Iterable<(String, String)> pairs) {
    int colMask = 0;
    int rowMask = 0;
    for (final (String a, String b) in pairs) {
      var (int ax, int ay) = parseCell(a);
      var (int bx, int by) = parseCell(b);
      colMask |= (1 << ax) | (1 << bx);
      rowMask |= (1 << ay) | (1 << by);
    }
    int full = (1 << n) - 1;
    return colMask == full && rowMask == full;
  }

  /// Target active connector count scaled to `2 * n * (n - 1)` grid slots (~64%–74%).
  static (int, int) _targetConnectorRange(int n) {
    if (n <= 4) return (15, 18); // out of 24 slots
    if (n == 5) return (25, 30); // out of 40 slots
    return (37, 44); // out of 60 slots on 6x6
  }

  /// Grow a random connected subgraph that prioritizes visiting unreached rows/cols
  /// first so the puzzle naturally spreads across the entire `n x n` board.
  static List<(String, String)> _growFullGridSubgraph(
    Random32 rng,
    int n,
    List<(String, String)> slots,
    List<(String, String)> seedSlots,
    int targetM,
    Set<String> forbidVerts, {
    Set<String>? forbidSlotKeys,
  }) {
    Map<String, List<(String, String)>> adj = {};
    for (final s in slots) {
      String sk = '${s.$1}-${s.$2}';
      if (forbidSlotKeys != null && forbidSlotKeys.contains(sk)) continue;
      (adj[s.$1] ??= []).add(s);
      (adj[s.$2] ??= []).add(s);
    }
    List<(String, String)> chosen = [];
    Set<String> chosenKeys = {};
    Set<String> activeVerts = {};
    Set<int> cols = {};
    Set<int> rows = {};

    void addSlot((String, String) raw) {
      var (String cu, String cv) = canonPair(raw.$1, raw.$2);
      String sk = '$cu-$cv';
      if (!chosenKeys.add(sk)) return;
      chosen.add((cu, cv));
      for (final String v in [cu, cv]) {
        if (!forbidVerts.contains(v)) activeVerts.add(v);
        var (int cx, int cy) = parseCell(v);
        cols.add(cx);
        rows.add(cy);
      }
    }

    for (final s in seedSlots) {
      addSlot(s);
    }
    if (activeVerts.isEmpty) {
      for (final s in rng.shuffled(slots)) {
        if (!forbidVerts.contains(s.$1) && !forbidVerts.contains(s.$2)) {
          addSlot(s);
          break;
        }
      }
    }

    int guard = 0;
    while (chosen.length < targetM && guard++ < 400) {
      List<(String, String)> expanding = [];
      List<(String, String)> normal = [];
      for (final String v in activeVerts) {
        for (final s in (adj[v] ?? const <(String, String)>[])) {
          String sk = '${s.$1}-${s.$2}';
          if (chosenKeys.contains(sk)) continue;
          if (forbidVerts.contains(s.$1) || forbidVerts.contains(s.$2)) continue;
          String other = activeVerts.contains(s.$1) ? s.$2 : s.$1;
          var (int ox, int oy) = parseCell(other);
          bool newAxis = !cols.contains(ox) || !rows.contains(oy);
          bool newVert = !activeVerts.contains(other);
          if (newAxis || (newVert && rng.nextBool(0.65))) {
            expanding.add(s);
          } else {
            normal.add(s);
          }
        }
      }
      List<(String, String)> pool =
          (expanding.isNotEmpty && rng.nextBool(0.75)) ? expanding : (normal.isNotEmpty ? normal : expanding);
      if (pool.isEmpty) break;
      addSlot(rng.choice(pool));
    }
    return chosen;
  }

  static Map<String, int> _bfsGraphDist(String root, List<(String, String)> edges) {
    Map<String, List<String>> adj = {};
    for (final (String u, String v) in edges) {
      (adj[u] ??= []).add(v);
      (adj[v] ??= []).add(u);
    }
    Map<String, int> dist = {root: 0};
    List<String> q = [root];
    int qi = 0;
    while (qi < q.length) {
      String u = q[qi++];
      int du = dist[u]!;
      for (final String v in (adj[u] ?? const <String>[])) {
        if (!dist.containsKey(v)) {
          dist[v] = du + 1;
          q.add(v);
        }
      }
    }
    return dist;
  }

  // ---- Board Assembly (Supporting 2, 3, or 4 Folded 2x2 Tile Boxes) ----

  static GridBoard _buildBoardFromSpec({
    required int n,
    required String goal0,
    String? goal1,
    Set<String>? altSet,
    Set<String>? crossSet,
    required List<Connector> edgesSpec,
    required List<Meeple> piecesSpec,
    required bool isWalkBoard,
    _FoldSpec? foldSpec,
  }) {
    List<(String, String)> slots = allGridSlots(n);
    Map<String, CellNode> verts = {};
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        String cid = cellId(c, r);
        int? g = cid == goal0 ? 0 : (cid == goal1 ? 1 : null);
        verts[cid] = CellNode(
          id: cid,
          x: c * kGridPitch,
          y: r * kGridPitch,
          goal: g,
          alt: altSet != null && altSet.contains(cid),
          crossExits: (crossSet != null && crossSet.contains(cid)) ? makeCrossExits(cid) : null,
        );
      }
    }

    Set<String> activeSet = {for (final e in edgesSpec) e.id};
    List<(String, String)> off = slots.where((uv) => !activeSet.contains('${uv.$1}-${uv.$2}')).toList();

    if (foldSpec == null || foldSpec.boxes.isEmpty) {
      return GridBoard(
        gridN: n,
        isWalkBoard: isWalkBoard,
        tileDef: null,
        verts: verts,
        edges: edgesSpec.map((e) => e.clone()).toList(),
        pieces: piecesSpec.map((p) => p.clone()).toList(),
        off: off,
      );
    }

    Map<String, (String, String)> cellToBox = {};
    Map<String, Vec2> boxCenters = {};
    for (final _BoxSpec box in foldSpec.boxes) {
      CellNode p00 = verts[box.cellMap['n00']!]!;
      CellNode p11 = verts[box.cellMap['n11']!]!;
      boxCenters[box.id] = Vec2((p00.x + p11.x) / 2.0, (p00.y + p11.y) / 2.0);
      for (final entry in box.cellMap.entries) {
        cellToBox[entry.value] = (box.id, entry.key);
      }
    }

    Map<String, CellNode> origCellVerts = Map<String, CellNode>.from(verts);
    for (final _BoxSpec box in foldSpec.boxes) {
      for (final String cid in box.cellMap.values) {
        verts.remove(cid);
      }
    }

    List<String> altList = altSet == null ? const [] : altSet.toList();
    for (final _BoxSpec box in foldSpec.boxes) {
      Vec2 c = boxCenters[box.id]!;
      verts[box.id] = CellNode(
        id: box.id,
        x: c.x,
        y: c.y,
        box: 'A',
        owner: box.owner,
        rot180: box.rot180,
        sym: foldSpec.sym,
        cellMap: Map<String, String>.from(box.cellMap),
        altMap: altList,
      );
    }

    Set<String> usedPortSet = {};
    String matchPort(CellNode bv, String insideCell, CellNode outsideCell) {
      String bestP = 'p1';
      double bestD = double.infinity;
      for (final entry in TileDef.basePorts.entries) {
        TilePortDef pt = entry.value;
        if (bv.cellMap![pt.node] != insideCell) continue;
        Vec2 pp = gadOffset(bv, pt.dx, pt.dy);
        double d = pp.distTo(Vec2(outsideCell.x, outsideCell.y));
        if (d < bestD) {
          bestD = d;
          bestP = entry.key;
        }
      }
      usedPortSet.add(bestP);
      return bestP;
    }

    List<(String, String)> finalOff =
        off.where((uv) => !cellToBox.containsKey(uv.$1) && !cellToBox.containsKey(uv.$2)).toList();

    List<Connector> foldedEdges = [];
    for (final Connector e in edgesSpec) {
      var bu = cellToBox[e.u];
      var bv = cellToBox[e.v];
      if (bu != null && bv != null && bu.$1 == bv.$1) continue;
      Connector ne = e.clone();
      if (bu != null && bv == null) {
        ne.u = bu.$1;
        ne.uport = matchPort(verts[bu.$1]!, e.u, origCellVerts[e.v]!);
      } else if (bv != null && bu == null) {
        ne.v = bv.$1;
        ne.vport = matchPort(verts[bv.$1]!, e.v, origCellVerts[e.u]!);
      } else if (bu != null && bv != null && bu.$1 != bv.$1) {
        ne.u = bu.$1;
        ne.uport = matchPort(verts[bu.$1]!, e.u, origCellVerts[e.v]!);
        ne.v = bv.$1;
        ne.vport = matchPort(verts[bv.$1]!, e.v, origCellVerts[e.u]!);
      }
      foldedEdges.add(ne);
    }

    List<Meeple> foldedPieces = [];
    for (final Meeple p in piecesSpec) {
      if (p.on != null) {
        List<String> parts = p.on!.split('-');
        var bu = cellToBox[parts[0]];
        var bv = cellToBox[parts[1]];
        if (bu != null && bv != null && bu.$1 == bv.$1) continue;
      }
      Meeple np = p.clone();
      if (cellToBox.containsKey(np.at)) np.at = cellToBox[np.at]!.$1;
      foldedPieces.add(np);
    }

    List<String> usedPorts = ['p1', 'p2', 'p3', 'p4'].where(usedPortSet.contains).toList();
    if (usedPorts.isEmpty) usedPorts = ['p1', 'p2'];

    TileDef finalTile = TileDef(
      usedPorts: usedPorts,
      pairs: foldSpec.tileDef.pairs,
      off: foldSpec.tileDef.off,
      spawnPieces: foldSpec.tileDef.spawnPieces,
    );

    return GridBoard(
      gridN: n,
      isWalkBoard: isWalkBoard,
      tileDef: finalTile,
      verts: verts,
      edges: foldedEdges,
      pieces: foldedPieces,
      off: finalOff,
    );
  }

  static GridBoard _connListToBoard(
    int n,
    String goal0,
    String? goal1,
    List<_ConnSpec> conn, {
    _FoldSpec? foldSpec,
  }) {
    List<Connector> edgesSpec = [];
    List<Meeple> piecesSpec = [];
    for (final _ConnSpec raw in conn) {
      _ConnSpec c = raw.canonical();
      String id = '${c.u}-${c.v}';
      String tail = c.atV ? 'u' : 'v';
      edgesSpec.add(Connector(id: id, u: c.u, v: c.v, tail: tail));
      piecesSpec.add(Meeple(
        id: id,
        w: c.w,
        owner: c.owner,
        star: c.star,
        at: c.atV ? c.v : c.u,
        on: id,
      ));
    }
    return _buildBoardFromSpec(
      n: n,
      goal0: goal0,
      goal1: goal1,
      edgesSpec: edgesSpec,
      piecesSpec: piecesSpec,
      isWalkBoard: false,
      foldSpec: foldSpec,
    );
  }

  // ---- Random Disjoint 2x2 Box Placement Across Full Grid (2 on 4x4, 3 on 5x5, 4 on 6x6) ----

  static (List<_BoxSpec>, int, TileDef, List<(int, int, int, bool, String)>) _sampleFoldSetup(
    int n,
    Random32 rng,
    Switches s, {
    required bool twoPlayer,
  }) {
    int sym = rng.nextIntRange(0, 7);
    String G(int x, int y) {
      var (int cx, int cy) = transformCoord(x, y, n, sym);
      return cellId(cx, cy);
    }

    int wantedBoxes = n <= 4 ? 2 : (n == 5 ? 3 : 4);
    List<(int, int)> anchors = [];
    for (int by = 0; by <= n - 2; by++) {
      for (int bx = 0; bx <= n - 2; bx++) {
        anchors.add((bx, by));
      }
    }

    List<(int, int, bool)> picked = [];
    for (int tryLayout = 0; tryLayout < 40; tryLayout++) {
      picked = [];
      Set<String> occ = {};
      for (final (int bx, int by) in rng.shuffled(anchors)) {
        if (occ.contains('$bx,$by') ||
            occ.contains('${bx + 1},$by') ||
            occ.contains('$bx,${by + 1}') ||
            occ.contains('${bx + 1},${by + 1}')) {
          continue;
        }
        bool canNormal = (bx + 2 < n) || (by + 2 < n);
        bool canRot180 = (bx >= 1) || (by >= 1);
        if (!canNormal && !canRot180) continue;
        bool rot180;
        if (canNormal && canRot180) {
          // Alternate/randomize so both A and A' appear
          rot180 = picked.length.isOdd ? rng.nextBool(0.75) : rng.nextBool(0.25);
        } else {
          rot180 = canRot180;
        }
        picked.add((bx, by, rot180));
        occ.addAll(['$bx,$by', '${bx + 1},$by', '$bx,${by + 1}', '${bx + 1},${by + 1}']);
        if (picked.length >= wantedBoxes) break;
      }
      if (picked.length >= wantedBoxes) break;
    }

    const List<String> names = ['n00', 'n10', 'n01', 'n11'];
    const List<(int, int)> localSlots = [(0, 1), (0, 2), (1, 3), (2, 3)];
    int offIdx = rng.nextIntRange(0, 3);
    List<(int, int, int, bool, String)> localSpecs = [];
    Map<int, int> hvLocal = {};
    for (int i = 0; i < 4; i++) {
      if (i == offIdx) continue;
      int a = localSlots[i].$1;
      int b = localSlots[i].$2;
      bool walkMode = s.open && s.thr == 0 && !s.two;
      int w = walkMode ? 1 : (rng.nextBool(0.48) ? 2 : 1);
      int capA = a == 0 ? 1 : 2;
      int capB = b == 0 ? 1 : 2;
      bool canA = (hvLocal[a] ?? 0) + w <= capA;
      bool canB = (hvLocal[b] ?? 0) + w <= capB;
      bool atSecond;
      if (canA && canB) {
        atSecond = rng.nextBool(0.5);
      } else if (canB) {
        atSecond = true;
      } else if (canA) {
        atSecond = false;
      } else {
        w = 1;
        atSecond = (hvLocal[b] ?? 0) <= (hvLocal[a] ?? 0);
      }
      int restIdx = atSecond ? b : a;
      hvLocal[restIdx] = (hvLocal[restIdx] ?? 0) + w;
      String bTail = rng.nextBool(0.5) ? 'u' : 'v';
      localSpecs.add((a, b, w, atSecond, bTail));
    }

    List<TilePairSpec> pairs = localSpecs
        .map((ls) => TilePairSpec(
              ka: names[ls.$1],
              kb: names[ls.$2],
              w: ls.$3,
              kat: ls.$4 ? names[ls.$2] : names[ls.$1],
              baseTail: ls.$5,
            ))
        .toList();
    var offPair = localSlots[offIdx];
    TileDef tileDef = TileDef(
      usedPorts: const ['p1', 'p2', 'p3', 'p4'],
      pairs: pairs,
      off: [(names[offPair.$1], names[offPair.$2])],
      spawnPieces: !s.open || s.thr > 0 || s.two,
    );

    List<_BoxSpec> boxes = [];
    for (int i = 0; i < picked.length; i++) {
      var (int bx, int by, bool rot180) = picked[i];
      Map<String, String> cmap = rot180
          ? {
              'n00': G(bx + 1, by + 1),
              'n10': G(bx, by + 1),
              'n01': G(bx + 1, by),
              'n11': G(bx, by),
            }
          : {
              'n00': G(bx, by),
              'n10': G(bx + 1, by),
              'n01': G(bx, by + 1),
              'n11': G(bx + 1, by + 1),
            };
      Set<String> portSlots = {};
      if (!rot180) {
        if (bx + 2 < n) {
          portSlots.add(_slotKey(G(bx + 1, by), G(bx + 2, by)));
          portSlots.add(_slotKey(G(bx + 1, by + 1), G(bx + 2, by + 1)));
        }
        if (by + 2 < n) {
          portSlots.add(_slotKey(G(bx, by + 1), G(bx, by + 2)));
          portSlots.add(_slotKey(G(bx + 1, by + 1), G(bx + 1, by + 2)));
        }
      } else {
        if (bx >= 1) {
          portSlots.add(_slotKey(G(bx, by), G(bx - 1, by)));
          portSlots.add(_slotKey(G(bx, by + 1), G(bx - 1, by + 1)));
        }
        if (by >= 1) {
          portSlots.add(_slotKey(G(bx, by), G(bx, by - 1)));
          portSlots.add(_slotKey(G(bx + 1, by), G(bx + 1, by - 1)));
        }
      }
      int owner = twoPlayer ? (i % 2) : 0;
      boxes.add(_BoxSpec(
        id: 'A${i + 1}',
        cellMap: cmap,
        owner: owner,
        rot180: rot180,
        allowedPortSlots: portSlots,
      ));
    }

    return (boxes, sym, tileDef, localSpecs);
  }

  /// Assigns weights and token resting ends along a random subgraph using controlled
  /// initial inflow (`hv <= 2` on locked gates, `hv >= 3` on a few random starter cells)
  /// so full-grid `5x5` and `6x6` puzzles remain causally deep without state explosion.
  static List<_ConnSpec> _orientControlled1P(
    Random32 rng,
    String g0,
    (String, String) starSlot,
    List<(String, String)> otherSlots, {
    required int numStarters,
    required double weight2Prob,
    double reverseProb = 0.0,
    List<_ConnSpec> prebuilt = const [],
  }) {
    String uStar = starSlot.$1 == g0 ? starSlot.$2 : starSlot.$1;
    List<(String, String)> allPairs = [
      starSlot,
      ...otherSlots,
      for (final c in prebuilt) (c.u, c.v),
    ];
    Map<String, int> dist = _bfsGraphDist(g0, allPairs);

    Map<String, int> hv = {};
    List<_ConnSpec> out = [
      _ConnSpec(u: starSlot.$1, v: starSlot.$2, w: 2, atV: starSlot.$1 == g0, owner: 0, star: 0),
      ...prebuilt,
    ];
    for (final c in out) {
      String h = c.restingCell;
      hv[h] = (hv[h] ?? 0) + c.w;
    }

    // Pick random distant/mid vertices allowed to start unlocked (`hv` up to 3 or 4)
    List<String> cands = dist.keys.where((v) => v != g0 && v != uStar && (dist[v] ?? 0) >= 2).toList();
    Set<String> starters = rng.shuffled(cands).take(numStarters).toSet();
    if (starters.isEmpty && cands.isNotEmpty) starters.add(rng.choice(cands));

    // Order slots roughly from near-goal outward with random tie-breaking
    List<(String, String)> ordered = rng.shuffled(otherSlots);
    ordered.sort((a, b) {
      int da = math.min(dist[a.$1] ?? 99, dist[a.$2] ?? 99);
      int db = math.min(dist[b.$1] ?? 99, dist[b.$2] ?? 99);
      return da.compareTo(db);
    });

    for (final (String a, String b) in ordered) {
      int da = dist[a] ?? 99;
      int db = dist[b] ?? 99;
      String farEnd = da <= db ? b : a;
      String nearEnd = da <= db ? a : b;
      if ((da == db && rng.nextBool(0.5)) || (reverseProb > 0 && rng.nextBool(reverseProb))) {
        String tmp = farEnd;
        farEnd = nearEnd;
        nearEnd = tmp;
      }

      int capFar = starters.contains(farEnd) ? 4 : 2;
      int capNear = starters.contains(nearEnd) ? 4 : 2;
      int hvFar = hv[farEnd] ?? 0;
      int hvNear = hv[nearEnd] ?? 0;

      int w = rng.nextBool(weight2Prob) ? 2 : 1;
      String rest;
      if (hvFar + w <= capFar) {
        rest = farEnd;
      } else if (hvFar + 1 <= capFar) {
        w = 1;
        rest = farEnd;
      } else if (hvNear + w <= capNear) {
        rest = nearEnd;
      } else if (hvNear + 1 <= capNear) {
        w = 1;
        rest = nearEnd;
      } else {
        w = 1;
        rest = hvFar <= hvNear ? farEnd : nearEnd;
      }

      hv[rest] = (hv[rest] ?? 0) + w;
      out.add(_ConnSpec(u: a, v: b, w: w, atV: rest == b, owner: 0));
    }
    return out;
  }

  // ---- Main Procedural Synthesizer ----

  static Puzzle synthesize(SynthRequest req) {
    Switches Rg = req.switches;
    int n = req.n.clamp(4, 6);
    int seedHash = ((req.seed * 2654435761) ^ (n * 2246822519)) & 0x7FFFFFFF;
    if (seedHash == 0) seedHash = 1042;
    Random32 rng = Random32(seedHash);
    List<(String, String)> slots = allGridSlots(n);
    var (int minM, int maxM) = _targetConnectorRange(n);

    // =========================================================================
    // A. Open-Centre Walk Regimes (L, NL, P, plus Custom Folded Walk)
    // =========================================================================
    if (Rg.open && Rg.thr == 0 && !Rg.two) {
      if (Rg.coded) {
        Puzzle? foldedWalk = _synthesizeFoldedWalk(n, rng, Rg, slots, minM, maxM);
        if (foldedWalk != null) return foldedWalk;
      }
      if (Rg.alt) {
        Puzzle? altWalk = _synthesizeAlternatingWalkP(n, rng, Rg, slots, minM, maxM);
        if (altWalk != null) return altWalk;
      }
      if (Rg.directed) {
        Puzzle? dirWalk = _synthesizeDirectedWalkNL(n, rng, Rg, slots, minM, maxM);
        if (dirWalk != null) return dirWalk;
      }
      Puzzle? symWalk = _synthesizeSymmetricWalkL(n, rng, Rg, slots, minM, maxM);
      if (symWalk != null) return symWalk;
    }

    // =========================================================================
    // B. 2-Player Regimes (2EXPTIME folded & EXPTIME open-tiles)
    // =========================================================================
    if (Rg.two && Rg.coded) {
      Puzzle? p2Fold = _synthesizeTwoPlayerFolded(n, rng, Rg, slots, minM, maxM);
      if (p2Fold != null) return p2Fold;
    }
    if (Rg.two) {
      Puzzle? p2Open = _synthesizeTwoPlayerOpen(n, rng, Rg, slots, minM, maxM);
      if (p2Open != null) return p2Open;
    }

    // =========================================================================
    // C. 1-Player Folded 2x2 Tile Regimes (NEXPTIME once & EXPSPACE shuttle)
    // =========================================================================
    if (Rg.coded && Rg.once) {
      Puzzle? nexp = _synthesizeOnePlayerFoldedOnce(n, rng, Rg, slots, minM, maxM);
      if (nexp != null) return nexp;
    } else if (Rg.coded) {
      Puzzle? expspace = _synthesizeOnePlayerFoldedShuttle(n, rng, Rg, slots, minM, maxM);
      if (expspace != null) return expspace;
    }

    // =========================================================================
    // D. 1-Player Unfolded Closed-Centre Regimes (NP once & PSPACE shuttle)
    // =========================================================================
    if (Rg.once) {
      Puzzle? np = _synthesizeOnePlayerOnceNP(n, rng, Rg, slots, minM, maxM);
      if (np != null) return np;
    }

    Puzzle? pspace = _synthesizeOnePlayerShuttlePSPACE(n, rng, Rg, slots, minM, maxM);
    if (pspace != null) return pspace;

    // Guaranteed full-grid procedural fallback (never a sparse 5-edge stub)
    return _synthesizeGuaranteedFullGridFallback(n, rng, Rg, slots, minM, maxM);
  }

  // ---- Regime A1: Procedural L (2-way walk with crossing bridges) ----

  static Puzzle? _synthesizeSymmetricWalkL(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    List<String> allCells = [
      for (int r = 0; r < n; r++)
        for (int c = 0; c < n; c++) cellId(c, r),
    ];
    List<String> interior = [
      for (int r = 1; r < n - 1; r++)
        for (int c = 1; c < n - 1; c++) cellId(c, r),
    ];
    int wantBridges = n <= 4 ? 1 : (n == 5 ? 2 : 3);
    int minDist = n <= 4 ? 6 : (n == 5 ? 9 : 12);

    int maxAtt = n <= 4 ? 420 : 220;
    for (int att = 0; att < maxAtt; att++) {
      // Pick non-adjacent crossing bridges in the interior
      Set<String> crossSet = {};
      for (final String cid in rng.shuffled(interior)) {
        if (crossSet.every((b) => _manhattan(b, cid) >= 2)) {
          crossSet.add(cid);
          if (crossSet.length >= wantBridges) break;
        }
      }
      if (crossSet.isEmpty) crossSet.add(rng.choice(interior));

      List<String> nonCross = allCells.where((c) => !crossSet.contains(c)).toList();
      String startC = rng.choice(nonCross);
      List<String> farGoals = nonCross.where((c) => _manhattan(startC, c) >= n).toList();
      if (farGoals.isEmpty) continue;
      String goalC = rng.choice(farGoals);

      // Seed all 4 incident connectors on every crossing bridge so bridges act as real 4-way overpasses
      List<(String, String)> bridgeSlots = [];
      for (final String bc in crossSet) {
        for (final s in slots) {
          if (s.$1 == bc || s.$2 == bc) bridgeSlots.add(s);
        }
      }
      if (bridgeSlots.any((s) => s.$1 == goalC || s.$2 == goalC)) continue;

      // Single goal entry slot so goal doesn't become trivially adjacent from every side
      List<(String, String)> goalCands = slots
          .where((s) => (s.$1 == goalC || s.$2 == goalC) && !crossSet.contains(s.$1) && !crossSet.contains(s.$2))
          .toList();
      if (goalCands.isEmpty) continue;
      var goalSlot = rng.choice(goalCands);

      int targetM = rng.nextIntRange(minM, maxM);
      // Grow a sparse winding core first, then add dead-end branches to hit full-grid density
      int coreM = (targetM * 0.72).round().clamp(bridgeSlots.length + 4, targetM);
      List<(String, String)> chosen = _growFullGridSubgraph(
        rng,
        n,
        slots,
        [goalSlot, ...bridgeSlots],
        coreM,
        {goalC},
      );
      Set<String> chosenKeys = {for (final s in chosen) '${s.$1}-${s.$2}'};
      Set<String> visitedVerts = {for (final s in chosen) ...[s.$1, s.$2]};

      // Add tree-like side corridors into unvisited cells first, then sparse loops away from goal
      for (final s in rng.shuffled(slots)) {
        if (chosen.length >= targetM) break;
        String sk = '${s.$1}-${s.$2}';
        if (chosenKeys.contains(sk) || s.$1 == goalC || s.$2 == goalC) continue;
        bool uIn = visitedVerts.contains(s.$1);
        bool vIn = visitedVerts.contains(s.$2);
        if (uIn != vIn) {
          chosen.add(s);
          chosenKeys.add(sk);
          visitedVerts.add(s.$1);
          visitedVerts.add(s.$2);
        }
      }
      for (final s in rng.shuffled(slots)) {
        if (chosen.length >= targetM) break;
        String sk = '${s.$1}-${s.$2}';
        if (chosenKeys.contains(sk) || s.$1 == goalC || s.$2 == goalC) continue;
        chosen.add(s);
        chosenKeys.add(sk);
        visitedVerts.add(s.$1);
        visitedVerts.add(s.$2);
      }

      if (!visitedVerts.contains(startC) || !_spansAllRowsAndCols(n, chosen)) continue;

      List<Connector> edgesSpec = [
        for (final (String u, String v) in chosen)
          Connector(id: '$u-$v', u: u, v: v, tail: rng.nextBool(0.5) ? 'u' : 'v'),
      ];
      GridBoard board = _buildBoardFromSpec(
        n: n,
        goal0: goalC,
        crossSet: crossSet,
        edgesSpec: edgesSpec,
        piecesSpec: [Meeple(id: 'm', w: 1, owner: 0, star: 0, at: startC, on: null)],
        isWalkBoard: true,
      );
      SolveResult sol = Solver.solve(Rg, board);
      if (sol.dist == null || sol.dist! < minDist) continue;
      // Ensure crossing bridges meaningfully shape the corridor (shorter if bridges were ordinary)
      SolveResult noCross = Solver.solve(Rg.copyWith(cross: false), board);
      if (Rg.cross && noCross.dist != null && noCross.dist! >= sol.dist! && att < 150) continue;

      return Puzzle(
        board: board,
        log: [
          'Procedural 2-way corridor from $startC to ★$goalC across ${crossSet.length} crossing bridge${crossSet.length == 1 ? '' : 's'}.',
          '${edgesSpec.length} active connectors spanning the $n×$n grid (shortest walk: ${sol.dist}).',
        ],
      );
    }
    return null;
  }

  // ---- Regime A2: Procedural NL (1-way directed maze with bridges & dead-end sinks) ----

  static Puzzle? _synthesizeDirectedWalkNL(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    List<String> allCells = [
      for (int r = 0; r < n; r++)
        for (int c = 0; c < n; c++) cellId(c, r),
    ];
    List<String> interior = [
      for (int r = 1; r < n - 1; r++)
        for (int c = 1; c < n - 1; c++) cellId(c, r),
    ];
    int wantBridges = n <= 4 ? 1 : (n == 5 ? 2 : 3);
    int minDist = n <= 4 ? 5 : (n == 5 ? 7 : 9);

    for (int att = 0; att < 260; att++) {
      Set<String> crossSet = {};
      for (final String cid in rng.shuffled(interior)) {
        if (crossSet.every((b) => _manhattan(b, cid) >= 2)) {
          crossSet.add(cid);
          if (crossSet.length >= wantBridges) break;
        }
      }
      if (crossSet.isEmpty) crossSet.add(rng.choice(interior));

      List<String> nonCross = allCells.where((c) => !crossSet.contains(c)).toList();
      String startC = rng.choice(nonCross);
      List<String> farGoals = nonCross.where((c) => _manhattan(startC, c) >= n).toList();
      if (farGoals.isEmpty) continue;
      String goalC = rng.choice(farGoals);

      List<(String, String)> bridgeSlots = [];
      for (final String bc in crossSet) {
        for (final s in slots) {
          if (s.$1 == bc || s.$2 == bc) bridgeSlots.add(s);
        }
      }
      if (bridgeSlots.any((s) => s.$1 == goalC || s.$2 == goalC)) continue;

      List<(String, String)> goalCands = slots
          .where((s) => (s.$1 == goalC || s.$2 == goalC) && !crossSet.contains(s.$1) && !crossSet.contains(s.$2))
          .toList();
      if (goalCands.isEmpty) continue;
      var goalSlot = rng.choice(goalCands);

      int targetM = rng.nextIntRange(minM, maxM);
      List<(String, String)> chosen = _growFullGridSubgraph(
        rng,
        n,
        slots,
        [goalSlot, ...bridgeSlots],
        targetM,
        {goalC},
      );
      if (!_spansAllRowsAndCols(n, chosen)) continue;

      // Rank vertices roughly from start -> goal, with 2-3 dead-end sink vertices
      Map<String, int> dGoal = _bfsGraphDist(goalC, chosen);
      if (!dGoal.containsKey(startC)) continue;
      List<String> sinkCands = nonCross
          .where((c) => c != startC && c != goalC && (dGoal[c] ?? 0) >= 2)
          .toList();
      Set<String> sinks = rng.shuffled(sinkCands).take(n <= 4 ? 2 : 3).toSet();

      Map<String, double> rank = {};
      for (final String c in allCells) {
        if (c == goalC) {
          rank[c] = 0.0;
        } else if (sinks.contains(c)) {
          rank[c] = -2.0 - rng.nextDouble();
        } else if (c == startC) {
          rank[c] = 100.0;
        } else {
          rank[c] = (dGoal[c] ?? n * 2).toDouble() + (rng.nextDouble() - 0.5) * 2.4;
        }
      }

      // Ensure each crossing bridge has 1 in + 1 out horizontally and 1 in + 1 out vertically
      Map<String, String> forcedTail = {};
      for (final String bc in crossSet) {
        var (int bx, int by) = parseCell(bc);
        String wC = cellId(bx - 1, by);
        String eC = cellId(bx + 1, by);
        String nC = cellId(bx, by - 1);
        String sC = cellId(bx, by + 1);
        bool lr = (rank[wC] ?? 0) >= (rank[eC] ?? 0);
        forcedTail[_slotKey(wC, bc)] = lr ? wC : bc;
        forcedTail[_slotKey(bc, eC)] = lr ? bc : eC;
        bool tb = (rank[nC] ?? 0) >= (rank[sC] ?? 0);
        forcedTail[_slotKey(nC, bc)] = tb ? nC : bc;
        forcedTail[_slotKey(bc, sC)] = tb ? bc : sC;
      }

      List<Connector> edgesSpec = [];
      for (final (String u, String v) in chosen) {
        String id = '$u-$v';
        String src;
        if (u == goalC) {
          src = v;
        } else if (v == goalC) {
          src = u;
        } else if (forcedTail.containsKey(id)) {
          src = forcedTail[id]!;
        } else {
          src = (rank[u] ?? 0) >= (rank[v] ?? 0) ? u : v;
        }
        edgesSpec.add(Connector(id: id, u: u, v: v, tail: src == u ? 'u' : 'v'));
      }

      GridBoard board = _buildBoardFromSpec(
        n: n,
        goal0: goalC,
        crossSet: crossSet,
        edgesSpec: edgesSpec,
        piecesSpec: [Meeple(id: 'm', w: 1, owner: 0, star: 0, at: startC, on: null)],
        isWalkBoard: true,
      );
      SolveResult sol = Solver.solve(Rg, board);
      if (sol.dist == null || sol.dist! < minDist) continue;

      // Require at least one genuine wrong-turn choice from start or along reachable DAG
      Map<String, int> distMap = Solver.walkDist(board, Rg);
      bool hasWrongTurn = false;
      for (final Connector e in edgesSpec) {
        String src = e.tail == 'u' ? e.u : e.v;
        String dst = e.farOf(src);
        if (distMap.containsKey('$src|') && !distMap.containsKey('$dst|${e.id}')) {
          hasWrongTurn = true;
          break;
        }
      }
      if (!hasWrongTurn && att < 180) continue;

      return Puzzle(
        board: board,
        log: [
          'Procedural 1-way grid maze from $startC to ★$goalC with ${crossSet.length} crossing bridge${crossSet.length == 1 ? '' : 's'} and dead-end sinks.',
          '${edgesSpec.length} directed connectors across $n×$n (shortest path: ${sol.dist}).',
        ],
      );
    }
    return null;
  }

  // ---- Regime A3: Procedural P (Alternating ∀ walk where crossing bridges decide winability) ----

  static Puzzle? _synthesizeAlternatingWalkP(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    List<String> allCells = [
      for (int r = 0; r < n; r++)
        for (int c = 0; c < n; c++) cellId(c, r),
    ];
    List<String> interior = [
      for (int r = 1; r < n - 1; r++)
        for (int c = 1; c < n - 1; c++) cellId(c, r),
    ];
    int wantBridges = n <= 4 ? 1 : (n == 5 ? 2 : 3);
    int minDist = n <= 4 ? 5 : (n == 5 ? 7 : 9);

    for (int att = 0; att < 360; att++) {
      // Pick 1 primary bridge (which is also a ∀ cell!) + optional extra bridges
      Set<String> crossSet = {};
      String? primaryBridge;
      for (final String cid in rng.shuffled(interior)) {
        if (crossSet.every((b) => _manhattan(b, cid) >= 2)) {
          crossSet.add(cid);
          primaryBridge ??= cid;
          if (crossSet.length >= wantBridges) break;
        }
      }
      if (primaryBridge == null) continue;

      var (int bx, int by) = parseCell(primaryBridge);
      bool safeVertical = rng.nextBool(0.5);
      bool posFlow = rng.nextBool(0.5);
      String safeIn = safeVertical ? cellId(bx, by + (posFlow ? -1 : 1)) : cellId(bx + (posFlow ? -1 : 1), by);
      String safeOut = safeVertical ? cellId(bx, by + (posFlow ? 1 : -1)) : cellId(bx + (posFlow ? 1 : -1), by);
      String sinkIn = safeVertical ? cellId(bx + (rng.nextBool(0.5) ? -1 : 1), by) : cellId(bx, by + (rng.nextBool(0.5) ? -1 : 1));
      String sinkOut = safeVertical
          ? cellId(bx + (parseCell(sinkIn).$1 < bx ? 1 : -1), by)
          : cellId(bx, by + (parseCell(sinkIn).$2 < by ? 1 : -1));

      Set<String> reserved = {...crossSet, safeIn, safeOut, sinkIn, sinkOut};
      List<String> freeCells = allCells.where((c) => !reserved.contains(c)).toList();
      if (freeCells.length < 2) continue;

      // Pick start near safeIn side and goal near safeOut side
      freeCells.sort((a, b) => _manhattan(a, safeIn).compareTo(_manhattan(b, safeIn)));
      String startC = rng.choice(freeCells.take(math.min(4, freeCells.length)).toList());
      List<String> goalPool = freeCells.where((c) => c != startC && _manhattan(c, startC) >= n - 1).toList();
      if (goalPool.isEmpty) continue;
      goalPool.sort((a, b) => _manhattan(a, safeOut).compareTo(_manhattan(b, safeOut)));
      String goalC = rng.choice(goalPool.take(math.min(4, goalPool.length)).toList());
      if (goalC == sinkOut || startC == sinkOut) continue;

      List<(String, String)> bridgeSlots = [];
      for (final String bc in crossSet) {
        for (final s in slots) {
          if (s.$1 == bc || s.$2 == bc) bridgeSlots.add(s);
        }
      }
      if (bridgeSlots.any((s) => s.$1 == goalC || s.$2 == goalC)) continue;

      // Allow 2 goal entry connectors so both branches of downstream ∀ cells can converge on goal!
      List<(String, String)> goalSlots = rng
          .shuffled(slots.where((s) => (s.$1 == goalC || s.$2 == goalC) && !crossSet.contains(s.$1) && !crossSet.contains(s.$2)).toList())
          .take(2)
          .toList();
      if (goalSlots.isEmpty) continue;

      int targetM = rng.nextIntRange(minM, maxM);
      List<(String, String)> chosen = _growFullGridSubgraph(
        rng,
        n,
        slots,
        [...goalSlots, ...bridgeSlots],
        targetM,
        {goalC},
      );
      if (!_spansAllRowsAndCols(n, chosen)) continue;

      // Orient edges along a randomized topological rank from startC -> safeIn -> primaryBridge -> safeOut -> goalC,
      // while sinkOut is a strict dead-end trap (-5 rank) so turning cross:false lets ∀ at primaryBridge force a loss!
      Map<String, int> dGoal = _bfsGraphDist(goalC, chosen);
      if (!dGoal.containsKey(startC) || !dGoal.containsKey(safeOut)) continue;

      Map<String, double> rank = {};
      for (final String c in allCells) {
        if (c == goalC) {
          rank[c] = 0.0;
        } else if (c == sinkOut) {
          rank[c] = -5.0;
        } else if (c == startC) {
          rank[c] = 50.0;
        } else if (c == safeIn) {
          rank[c] = 30.0 + rng.nextDouble();
        } else if (c == sinkIn) {
          rank[c] = 31.0 + rng.nextDouble();
        } else if (c == primaryBridge) {
          rank[c] = 25.0;
        } else if (c == safeOut) {
          rank[c] = 18.0 + rng.nextDouble();
        } else {
          rank[c] = (dGoal[c] ?? n * 2).toDouble() * 3.0 + rng.nextDouble() * 3.5;
        }
      }

      Map<String, String> forcedTail = {
        _slotKey(safeIn, primaryBridge): safeIn,
        _slotKey(primaryBridge, safeOut): primaryBridge,
        _slotKey(sinkIn, primaryBridge): sinkIn,
        _slotKey(primaryBridge, sinkOut): primaryBridge,
      };
      for (final String bc in crossSet) {
        if (bc == primaryBridge) continue;
        var (int cx, int cy) = parseCell(bc);
        String wC = cellId(cx - 1, cy), eC = cellId(cx + 1, cy);
        String nC = cellId(cx, cy - 1), sC = cellId(cx, cy + 1);
        bool lr = (rank[wC] ?? 0) >= (rank[eC] ?? 0);
        forcedTail[_slotKey(wC, bc)] = lr ? wC : bc;
        forcedTail[_slotKey(bc, eC)] = lr ? bc : eC;
        bool tb = (rank[nC] ?? 0) >= (rank[sC] ?? 0);
        forcedTail[_slotKey(nC, bc)] = tb ? nC : bc;
        forcedTail[_slotKey(bc, sC)] = tb ? bc : sC;
      }

      List<Connector> edgesSpec = [];
      Map<String, int> outDeg = {};
      for (final (String u, String v) in chosen) {
        String id = '$u-$v';
        String src;
        if (u == goalC) {
          src = v;
        } else if (v == goalC) {
          src = u;
        } else if (u == sinkOut) {
          src = v; // only incoming into sinkOut so sinkOut is a true dead end!
        } else if (v == sinkOut) {
          src = u;
        } else if (forcedTail.containsKey(id)) {
          src = forcedTail[id]!;
        } else {
          src = (rank[u] ?? 0) >= (rank[v] ?? 0) ? u : v;
        }
        outDeg[src] = (outDeg[src] ?? 0) + 1;
        edgesSpec.add(Connector(id: id, u: u, v: v, tail: src == u ? 'u' : 'v'));
      }

      // Pick additional ∀ cells among branching vertices that don't directly step into sinkOut
      List<String> altCands = allCells
          .where((c) =>
              c != startC &&
              c != goalC &&
              c != primaryBridge &&
              c != sinkOut &&
              (outDeg[c] ?? 0) >= 2 &&
              !edgesSpec.any((e) => e.arrowFrom(c) && e.farOf(c) == sinkOut))
          .toList();
      int extraAlts = rng.nextIntRange(n <= 4 ? 1 : 2, n <= 4 ? 3 : (n == 5 ? 4 : 5));
      Set<String> altSet = {primaryBridge, ...rng.shuffled(altCands).take(extraAlts)};

      GridBoard board = _buildBoardFromSpec(
        n: n,
        goal0: goalC,
        altSet: altSet,
        crossSet: crossSet,
        edgesSpec: edgesSpec,
        piecesSpec: [Meeple(id: 'm', w: 1, owner: 0, star: 0, at: startC, on: null)],
        isWalkBoard: true,
      );

      Switches checkWithCross = Rg.copyWith(cross: true);
      SolveResult withBridge = Solver.solve(checkWithCross, board);
      if (withBridge.dist == null || withBridge.dist! < minDist) continue;
      SolveResult ordinary = Solver.solve(Rg.copyWith(cross: false), board);
      if (ordinary.dist != null) continue; // Crossing bridge MUST be essential to beat ∀!

      // Ensure if Rg itself has cross==false (user started custom), board still solvable
      if (!Rg.cross) continue;

      return Puzzle(
        board: board,
        log: [
          'Procedural alternating ∀ walk from $startC to ★$goalC across ${crossSet.length} bridge${crossSet.length == 1 ? '' : 's'} and ${altSet.length} ∀ cells.',
          '${edgesSpec.length} directed connectors across $n×$n (forced win in ${withBridge.dist} plies).',
        ],
      );
    }
    return null;
  }

  // ---- Regime A4: Procedural Custom Folded Walk ----

  static Puzzle? _synthesizeFoldedWalk(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    for (int att = 0; att < 180; att++) {
      var (boxes, sym, tileDef, localSpecs) = _sampleFoldSetup(n, rng, Rg, twoPlayer: false);
      if (boxes.length < 2) continue;
      Set<String> tileCells = {for (final b in boxes) ...b.cellMap.values};
      Set<String> allowedPortSlots = {for (final b in boxes) ...b.allowedPortSlots};

      List<String> openCells = [
        for (int r = 0; r < n; r++)
          for (int c = 0; c < n; c++)
            if (!tileCells.contains(cellId(c, r))) cellId(c, r),
      ];
      if (openCells.isEmpty) continue;
      String goalC = rng.choice(openCells);
      String startC = boxes.first.cellMap['n00']!;

      const List<String> names = ['n00', 'n10', 'n01', 'n11'];
      List<(String, String)> validOuter = slots.where((uv) {
        String sk = '${uv.$1}-${uv.$2}';
        bool uTile = tileCells.contains(uv.$1);
        bool vTile = tileCells.contains(uv.$2);
        if (uTile && vTile) return allowedPortSlots.contains(sk);
        if (uTile || vTile) return allowedPortSlots.contains(sk);
        return true;
      }).toList();

      int internalCount = boxes.length * localSpecs.length;
      if (validOuter.isEmpty) continue;
      int wantOuter = math.min(validOuter.length, math.max(1, rng.nextIntRange(minM, maxM) - internalCount));
      List<(String, String)> outerChosen = rng.shuffled(validOuter).take(wantOuter).toList();

      List<Connector> edgesSpec = [];
      Set<String> seen = {};
      for (final b in boxes) {
        for (final ls in localSpecs) {
          String rawU = b.cellMap[names[ls.$1]]!;
          String rawV = b.cellMap[names[ls.$2]]!;
          var (String cu, String cv) = canonPair(rawU, rawV);
          String id = '$cu-$cv';
          if (seen.add(id)) {
            String tailSrc = ls.$5 == 'v' ? rawV : rawU;
            edgesSpec.add(Connector(id: id, u: cu, v: cv, tail: tailSrc == cu ? 'u' : 'v'));
          }
        }
      }
      Map<String, int> dGoal = _bfsGraphDist(goalC, [
        ...outerChosen,
        for (final e in edgesSpec) (e.u, e.v),
      ]);
      for (final (String u, String v) in outerChosen) {
        String id = '$u-$v';
        if (!seen.add(id)) continue;
        int du = dGoal[u] ?? 99;
        int dv = dGoal[v] ?? 99;
        String src = u == goalC ? v : (v == goalC ? u : (du >= dv ? u : v));
        edgesSpec.add(Connector(id: id, u: u, v: v, tail: src == u ? 'u' : 'v'));
      }

      GridBoard board = _buildBoardFromSpec(
        n: n,
        goal0: goalC,
        edgesSpec: edgesSpec,
        piecesSpec: [Meeple(id: 'm', w: 1, owner: 0, star: 0, at: startC, on: null)],
        isWalkBoard: true,
        foldSpec: _FoldSpec(boxes: boxes, sym: sym, tileDef: tileDef),
      );
      SolveResult sol = Solver.solve(Rg, board);
      if (sol.dist != null && sol.dist! >= 4) {
        return Puzzle(
          board: board,
          log: ['Procedural folded 2×2 walk across ${boxes.length} boxes to ★$goalC.'],
        );
      }
    }
    return null;
  }

  // ---- Regime B1: Procedural 2-Player Folded (2EXPTIME) ----

  static Puzzle? _synthesizeTwoPlayerFolded(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    int minDist = n <= 4 ? 5 : (n == 5 ? 7 : 9);
    int maxDist = n <= 4 ? 15 : (n == 5 ? 21 : 25);

    for (int att = 0; att < 320; att++) {
      var (boxes, sym, tileDef, localSpecs) = _sampleFoldSetup(n, rng, Rg, twoPlayer: true);
      if (boxes.length < 2) continue;
      Set<String> tileCells = {for (final b in boxes) ...b.cellMap.values};
      Set<String> allowedPortSlots = {for (final b in boxes) ...b.allowedPortSlots};

      List<String> openCells = [
        for (int r = 0; r < n; r++)
          for (int c = 0; c < n; c++)
            if (!tileCells.contains(cellId(c, r))) cellId(c, r),
      ];
      if (openCells.length < 4) continue;

      List<(String, String)> validOuter = slots.where((uv) {
        String sk = '${uv.$1}-${uv.$2}';
        bool uTile = tileCells.contains(uv.$1);
        bool vTile = tileCells.contains(uv.$2);
        if (uTile && vTile) {
          String b1 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$1)).id;
          String b2 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$2)).id;
          return b1 != b2 && boxes.any((b) => b.id == b1 && b.allowedPortSlots.contains(sk)) &&
              boxes.any((b) => b.id == b2 && b.allowedPortSlots.contains(sk));
        }
        if (uTile || vTile) return allowedPortSlots.contains(sk);
        return true;
      }).toList();

      // Pick g0 and g1 among open cells that have open-cell neighbours
      List<String> goalCands = openCells
          .where((c) => validOuter.any((uv) =>
              (uv.$1 == c && !tileCells.contains(uv.$2)) || (uv.$2 == c && !tileCells.contains(uv.$1))))
          .toList();
      if (goalCands.length < 2) continue;
      String g0 = rng.choice(goalCands);
      List<String> g1Pool = goalCands.where((c) => c != g0 && _manhattan(c, g0) >= n - 1).toList();
      if (g1Pool.isEmpty) g1Pool = goalCands.where((c) => c != g0).toList();
      if (g1Pool.isEmpty) continue;
      String g1 = rng.choice(g1Pool);

      var s0 = rng.choice(validOuter
          .where((uv) => (uv.$1 == g0 || uv.$2 == g0) && !tileCells.contains(uv.$1) && !tileCells.contains(uv.$2))
          .toList());
      var s1Pool = validOuter
          .where((uv) =>
              (uv.$1 == g1 || uv.$2 == g1) &&
              !tileCells.contains(uv.$1) &&
              !tileCells.contains(uv.$2) &&
              '${uv.$1}-${uv.$2}' != '${s0.$1}-${s0.$2}' &&
              uv.$1 != g0 &&
              uv.$2 != g0)
          .toList();
      if (s1Pool.isEmpty) continue;
      var s1 = rng.choice(s1Pool);

      const List<String> names = ['n00', 'n10', 'n01', 'n11'];
      List<_ConnSpec> conn = [
        _ConnSpec(u: s0.$1, v: s0.$2, w: 2, atV: s0.$1 == g0, owner: 0, star: 0),
        _ConnSpec(u: s1.$1, v: s1.$2, w: 2, atV: s1.$1 == g1, owner: 1, star: 1),
      ];
      for (final b in boxes) {
        for (final ls in localSpecs) {
          conn.add(_ConnSpec(
            u: b.cellMap[names[ls.$1]]!,
            v: b.cellMap[names[ls.$2]]!,
            w: ls.$3,
            atV: ls.$4,
            owner: b.owner,
          ));
        }
      }

      Set<String> usedKeys = {
        for (final c in conn) _slotKey(c.u, c.v),
      };
      List<(String, String)> restOuter = validOuter
          .where((uv) =>
              !usedKeys.contains('${uv.$1}-${uv.$2}') &&
              uv.$1 != g0 &&
              uv.$2 != g0 &&
              uv.$1 != g1 &&
              uv.$2 != g1)
          .toList();

      if (restOuter.length < 4) continue;
      int minFoldM = n <= 4 ? 14 : (n == 5 ? 23 : 32);
      int targetTotal = rng.nextIntRange(minFoldM, maxM);
      int needOuter = math.min(restOuter.length, math.max(4, targetTotal - conn.length));
      List<(String, String)> candPicked = rng.shuffled(restOuter);

      List<(String, String)> allGraphEdges = [
        ...candPicked.take(needOuter),
        for (final c in conn) (c.u, c.v),
      ];
      Map<String, int> d0 = _bfsGraphDist(g0, allGraphEdges);
      Map<String, int> d1 = _bfsGraphDist(g1, allGraphEdges);

      Map<String, int> hv = {};
      for (final c in conn) {
        String h = c.restingCell;
        hv[h] = (hv[h] ?? 0) + c.w;
      }
      List<String> openPool = rng.shuffled(openCells.where((c) => c != g0 && c != g1).toList());
      Set<String> starters0 = openPool.take(2).toSet();
      Set<String> starters1 = openPool.skip(2).take(2).toSet();
      Set<String> starters = {...starters0, ...starters1};

      int addedOuter = 0;
      for (final (String u, String v) in candPicked) {
        if (addedOuter >= needOuter) break;
        int owner;
        if (starters0.contains(u) || starters0.contains(v)) {
          owner = 0;
        } else if (starters1.contains(u) || starters1.contains(v)) {
          owner = 1;
        } else {
          owner = rng.nextBool(0.45) ? 1 : 0;
        }
        Map<String, int> dm = owner == 0 ? d0 : d1;
        String farEnd = (dm[u] ?? 99) <= (dm[v] ?? 99) ? v : u;
        String nearEnd = farEnd == v ? u : v;
        if (owner == 0 && starters0.contains(nearEnd) && !starters0.contains(farEnd)) {
          String tmp = farEnd;
          farEnd = nearEnd;
          nearEnd = tmp;
        } else if (owner == 1 && starters1.contains(nearEnd) && !starters1.contains(farEnd)) {
          String tmp = farEnd;
          farEnd = nearEnd;
          nearEnd = tmp;
        }
        int capFar = starters.contains(farEnd) ? 4 : 2;
        int capNear = starters.contains(nearEnd) ? 4 : 2;
        bool touchesStarter = starters.contains(farEnd) || starters.contains(nearEnd);
        int w = rng.nextBool(touchesStarter ? 0.65 : (n >= 6 ? 0.35 : 0.48)) ? 2 : 1;
        String? rest;
        if ((hv[farEnd] ?? 0) + w <= capFar) {
          rest = farEnd;
        } else if ((hv[farEnd] ?? 0) + 1 <= capFar) {
          w = 1;
          rest = farEnd;
        } else if ((hv[nearEnd] ?? 0) + w <= capNear) {
          rest = nearEnd;
        } else if ((hv[nearEnd] ?? 0) + 1 <= capNear) {
          w = 1;
          rest = nearEnd;
        } else if (conn.length < minFoldM) {
          w = 1;
          rest = (hv[farEnd] ?? 0) <= (hv[nearEnd] ?? 0) ? farEnd : nearEnd;
        }
        if (rest == null) continue;
        hv[rest] = (hv[rest] ?? 0) + w;
        conn.add(_ConnSpec(u: u, v: v, w: w, atV: rest == v, owner: owner));
        addedOuter++;
      }

      List<_ConnSpec> norm = conn.map((c) => c.canonical()).toList();
      if (!_spansAllRowsAndCols(n, norm.map((c) => (c.u, c.v)))) continue;

      var (int? dist, List<(String, int?)> d1Outs, _) =
          _probe2P(g0, g1, norm, Rg.thr, cap: 1400);
      if (dist != null &&
          dist >= minDist &&
          dist <= maxDist &&
          d1Outs.length >= 2 &&
          d1Outs.any((o) => o.$2 == null)) {
        GridBoard b = _connListToBoard(
          n,
          g0,
          g1,
          norm,
          foldSpec: _FoldSpec(boxes: boxes, sym: sym, tileDef: tileDef),
        );
        return Puzzle(
          board: b,
          log: [
            'Procedural 2-player game with ${boxes.length} folded 2×2 boxes verified by retrograde minimax.',
            'Forced win in $dist plies across ${norm.length} unfolded connectors on $n×$n.',
          ],
        );
      }
    }
    return null;
  }

  // ---- Regime B2: Procedural 2-Player Open-Tiles (EXPTIME) ----

  static Puzzle? _synthesizeTwoPlayerOpen(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    List<String> allCells = [
      for (int r = 0; r < n; r++)
        for (int c = 0; c < n; c++) cellId(c, r),
    ];
    int minDist = n <= 4 ? 5 : (n == 5 ? 7 : 9);
    int maxDist = n <= 4 ? 15 : (n == 5 ? 21 : 25);

    for (int att = 0; att < 320; att++) {
      String g0 = rng.choice(allCells);
      List<String> g1Pool = allCells.where((c) => _manhattan(c, g0) >= n).toList();
      if (g1Pool.isEmpty) continue;
      String g1 = rng.choice(g1Pool);

      var s0Cands = slots.where((s) => (s.$1 == g0 || s.$2 == g0) && s.$1 != g1 && s.$2 != g1).toList();
      if (s0Cands.isEmpty) continue;
      var s0 = rng.choice(s0Cands);
      var s1Cands = slots
          .where((s) =>
              (s.$1 == g1 || s.$2 == g1) &&
              s.$1 != g0 &&
              s.$2 != g0 &&
              '${s.$1}-${s.$2}' != '${s0.$1}-${s0.$2}')
          .toList();
      if (s1Cands.isEmpty) continue;
      var s1 = rng.choice(s1Cands);

      int targetM = rng.nextIntRange(minM, maxM);
      List<(String, String)> chosen = _growFullGridSubgraph(
        rng,
        n,
        slots,
        [s0, s1],
        targetM,
        {g0, g1},
      );
      if (!_spansAllRowsAndCols(n, chosen)) continue;

      Map<String, int> d0 = _bfsGraphDist(g0, chosen);
      Map<String, int> d1 = _bfsGraphDist(g1, chosen);

      List<_ConnSpec> conn = [
        _ConnSpec(u: s0.$1, v: s0.$2, w: 2, atV: s0.$1 == g0, owner: 0, star: 0),
        _ConnSpec(u: s1.$1, v: s1.$2, w: 2, atV: s1.$1 == g1, owner: 1, star: 1),
      ];
      Map<String, int> hv = {
        conn[0].restingCell: 2,
        conn[1].restingCell: 2,
      };

      List<String> inner = allCells.where((c) => c != g0 && c != g1).toList();
      Set<String> starters = rng.shuffled(inner).take(4).toSet();

      String k0 = '${s0.$1}-${s0.$2}';
      String k1 = '${s1.$1}-${s1.$2}';
      List<(String, String)> rest = chosen.where((s) {
        String sk = '${s.$1}-${s.$2}';
        return sk != k0 && sk != k1;
      }).toList();

      for (final (String u, String v) in rng.shuffled(rest)) {
        int owner = rng.nextBool(0.45) ? 1 : 0;
        Map<String, int> dm = owner == 0 ? d0 : d1;
        String farEnd = (dm[u] ?? 99) <= (dm[v] ?? 99) ? v : u;
        String nearEnd = farEnd == v ? u : v;

        int capFar = starters.contains(farEnd) ? 4 : 2;
        int capNear = starters.contains(nearEnd) ? 4 : 2;
        int w = rng.nextBool(0.52) ? 2 : 1;
        String restCell;
        if ((hv[farEnd] ?? 0) + w <= capFar) {
          restCell = farEnd;
        } else if ((hv[nearEnd] ?? 0) + w <= capNear) {
          restCell = nearEnd;
        } else {
          w = 1;
          restCell = (hv[farEnd] ?? 0) <= (hv[nearEnd] ?? 0) ? farEnd : nearEnd;
        }
        hv[restCell] = (hv[restCell] ?? 0) + w;
        conn.add(_ConnSpec(u: u, v: v, w: w, atV: restCell == v, owner: owner));
      }

      var (int? dist, List<(String, int?)> d1Outs, _) = _probe2P(g0, g1, conn, Rg.thr);
      if (dist != null &&
          dist >= minDist &&
          dist <= maxDist &&
          d1Outs.length >= 2 &&
          d1Outs.any((o) => o.$2 == null)) {
        GridBoard b = _connListToBoard(n, g0, g1, conn);
        return Puzzle(
          board: b,
          log: [
            'Procedural 2-player constraint-logic race (★$g0 vs ★$g1) verified by retrograde minimax.',
            'Forced win in $dist plies across ${conn.length} connectors on $n×$n.',
          ],
        );
      }
    }
    return null;
  }

  // ---- Regime C1: Procedural 1-Player Folded Once (NEXPTIME) ----

  static Puzzle? _synthesizeOnePlayerFoldedOnce(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    int minDist = n <= 4 ? 4 : (n == 5 ? 6 : 8);
    int maxDist = n <= 4 ? 11 : (n == 5 ? 16 : 22);

    for (int att = 0; att < 300; att++) {
      var (boxes, sym, tileDef, localSpecs) = _sampleFoldSetup(n, rng, Rg, twoPlayer: false);
      if (boxes.length < 2) continue;
      Set<String> tileCells = {for (final b in boxes) ...b.cellMap.values};
      Set<String> allowedPortSlots = {for (final b in boxes) ...b.allowedPortSlots};

      List<String> openCells = [
        for (int r = 0; r < n; r++)
          for (int c = 0; c < n; c++)
            if (!tileCells.contains(cellId(c, r))) cellId(c, r),
      ];
      if (openCells.length < 2) continue;

      List<(String, String)> validOuter = slots.where((uv) {
        String sk = '${uv.$1}-${uv.$2}';
        bool uTile = tileCells.contains(uv.$1);
        bool vTile = tileCells.contains(uv.$2);
        if (uTile && vTile) {
          String b1 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$1)).id;
          String b2 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$2)).id;
          return b1 != b2 && boxes.any((b) => b.id == b1 && b.allowedPortSlots.contains(sk)) &&
              boxes.any((b) => b.id == b2 && b.allowedPortSlots.contains(sk));
        }
        if (uTile || vTile) return allowedPortSlots.contains(sk);
        return true;
      }).toList();

      List<String> goalCands = openCells
          .where((c) => validOuter.any((uv) =>
              (uv.$1 == c && !tileCells.contains(uv.$2)) || (uv.$2 == c && !tileCells.contains(uv.$1))))
          .toList();
      if (goalCands.isEmpty) continue;
      String g0 = rng.choice(goalCands);
      var s0 = rng.choice(validOuter
          .where((uv) => (uv.$1 == g0 || uv.$2 == g0) && !tileCells.contains(uv.$1) && !tileCells.contains(uv.$2))
          .toList());
      String s0Key = '${s0.$1}-${s0.$2}';

      const List<String> names = ['n00', 'n10', 'n01', 'n11'];
      List<_ConnSpec> boxConns = [];
      for (final b in boxes) {
        for (final ls in localSpecs) {
          boxConns.add(_ConnSpec(
            u: b.cellMap[names[ls.$1]]!,
            v: b.cellMap[names[ls.$2]]!,
            w: ls.$3,
            atV: ls.$4,
            owner: 0,
          ));
        }
      }

      List<(String, String)> restOuter = validOuter
          .where((uv) => '${uv.$1}-${uv.$2}' != s0Key && uv.$1 != g0 && uv.$2 != g0)
          .toList();
      if (restOuter.length < 4) continue;
      int targetTotal = rng.nextIntRange(minM, maxM);
      int needOuter = math.min(restOuter.length, math.max(4, targetTotal - 1 - boxConns.length));
      List<(String, String)> pickedOuter = rng.shuffled(restOuter).take(needOuter).toList();

      List<_ConnSpec> conn = _orientControlled1P(
        rng,
        g0,
        s0,
        pickedOuter,
        numStarters: 3,
        weight2Prob: 0.48,
        prebuilt: boxConns,
      );
      List<_ConnSpec> norm = conn.map((c) => c.canonical()).toList();
      if (!_spansAllRowsAndCols(n, norm.map((c) => (c.u, c.v)))) continue;

      var (int? dist, List<int> path, _) = _probe1P(g0, norm, Rg.thr, true);
      if (dist != null &&
          dist >= minDist &&
          dist <= maxDist &&
          path.any((idx) => tileCells.contains(norm[idx].u) || tileCells.contains(norm[idx].v))) {
        GridBoard b = _connListToBoard(
          n,
          g0,
          null,
          norm,
          foldSpec: _FoldSpec(boxes: boxes, sym: sym, tileDef: tileDef),
        );
        return Puzzle(
          board: b,
          log: [
            'Procedural folded 2×2 board (${boxes.map((x) => x.id).join(', ')}) under once-only slides.',
            'Solvable in $dist slides across ${norm.length} unfolded connectors on $n×$n.',
          ],
        );
      }
    }
    return null;
  }

  // ---- Regime C2: Procedural 1-Player Folded Shuttle (EXPSPACE) ----

  static Puzzle? _synthesizeOnePlayerFoldedShuttle(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    int minDist = n <= 4 ? 8 : (n == 5 ? 9 : 11);
    int wantedBoxes = n <= 4 ? 2 : (n == 5 ? 3 : 4);

    int maxAtt = n <= 4 ? 420 : 220;
    for (int att = 0; att < maxAtt; att++) {
      // 1. Sample a random 3x2 (or 2x3) shuttle block H(0..2, 0..1) + adjacent g0 on the n x n grid
      int hubSym = rng.nextIntRange(0, 7);
      int dx = rng.nextIntRange(0, n - 3);
      int dy = rng.nextIntRange(0, n - 2);
      String H(int x, int y) {
        var (int cx, int cy) = transformCoord(x + dx, y + dy, n, hubSym);
        return cellId(cx, cy);
      }

      String uStar = H(0, 0);
      String hubC = H(0, 1);
      String c0 = H(1, 1);
      String c1 = H(2, 1);
      String c2 = H(2, 0);
      String c3 = H(1, 0);
      Set<String> hSet = {uStar, hubC, c0, c1, c2, c3};

      List<String> g0Cands = [
        for (final s in slots)
          if (s.$1 == uStar && !hSet.contains(s.$2))
            s.$2
          else if (s.$2 == uStar && !hSet.contains(s.$1))
            s.$1,
      ];
      if (g0Cands.isEmpty) continue;
      String g0 = rng.choice(g0Cands);

      List<String> inCands = [
        for (final s in slots)
          if (s.$1 == hubC && !hSet.contains(s.$2) && s.$2 != g0)
            s.$2
          else if (s.$2 == hubC && !hSet.contains(s.$1) && s.$1 != g0)
            s.$1,
      ];
      if (inCands.isEmpty) continue;
      String inC = rng.choice(inCands);

      List<String> anchCands = [
        for (final s in slots)
          if (s.$1 == c0 && !hSet.contains(s.$2) && s.$2 != g0)
            s.$2
          else if (s.$2 == c0 && !hSet.contains(s.$1) && s.$1 != g0)
            s.$1,
      ];
      if (anchCands.isEmpty) continue;
      String anchorC = rng.choice(anchCands);

      // 2. Pack disjoint 2x2 folded boxes into the remaining grid cells outside H u {g0}
      Set<String> blockedForBoxes = {...hSet, g0};
      int boxSym = rng.nextIntRange(0, 7);
      String BG(int x, int y) {
        var (int cx, int cy) = transformCoord(x, y, n, boxSym);
        return cellId(cx, cy);
      }
      List<(int, int)> anchors = [
        for (int by = 0; by <= n - 2; by++)
          for (int bx = 0; bx <= n - 2; bx++) (bx, by),
      ];
      List<(int, int, bool)> pickedBoxes = [];
      Set<String> occCells = {...blockedForBoxes};
      for (final (int bx, int by) in rng.shuffled(anchors)) {
        List<String> bCells = [BG(bx, by), BG(bx + 1, by), BG(bx, by + 1), BG(bx + 1, by + 1)];
        if (bCells.any(occCells.contains)) continue;
        bool canNormal = (bx + 2 < n) || (by + 2 < n);
        bool canRot180 = (bx >= 1) || (by >= 1);
        if (!canNormal && !canRot180) continue;
        // Prefer orientation whose port cells include inC or anchorC if either lies in bCells!
        List<bool> validRots = [
          if (canNormal) false,
          if (canRot180) true,
        ];
        bool? chosenRot;
        for (final bool r180 in rng.shuffled(validRots)) {
          String n00Cell = r180 ? BG(bx + 1, by + 1) : BG(bx, by);
          if (n00Cell == inC || n00Cell == anchorC) continue;
          Set<String> pSlots = {};
          if (!r180) {
            if (bx + 2 < n) {
              pSlots.add(_slotKey(BG(bx + 1, by), BG(bx + 2, by)));
              pSlots.add(_slotKey(BG(bx + 1, by + 1), BG(bx + 2, by + 1)));
            }
            if (by + 2 < n) {
              pSlots.add(_slotKey(BG(bx, by + 1), BG(bx, by + 2)));
              pSlots.add(_slotKey(BG(bx + 1, by + 1), BG(bx + 1, by + 2)));
            }
          } else {
            if (bx >= 1) {
              pSlots.add(_slotKey(BG(bx, by), BG(bx - 1, by)));
              pSlots.add(_slotKey(BG(bx, by + 1), BG(bx - 1, by + 1)));
            }
            if (by >= 1) {
              pSlots.add(_slotKey(BG(bx, by), BG(bx, by - 1)));
              pSlots.add(_slotKey(BG(bx + 1, by), BG(bx + 1, by - 1)));
            }
          }
          if (bCells.contains(inC) && !pSlots.contains(_slotKey(inC, hubC))) continue;
          if (bCells.contains(anchorC) && !pSlots.contains(_slotKey(anchorC, c0))) continue;
          chosenRot = r180;
          break;
        }
        if (chosenRot == null) continue;
        pickedBoxes.add((bx, by, chosenRot));
        occCells.addAll(bCells);
        if (pickedBoxes.length >= wantedBoxes) break;
      }
      int minAcceptBoxes = n <= 4 ? 2 : (n == 5 ? 2 : 3);
      if (pickedBoxes.length < minAcceptBoxes) continue;
      if (att < 120 && pickedBoxes.length < wantedBoxes) continue;

      const List<String> names = ['n00', 'n10', 'n01', 'n11'];
      const List<(int, int)> localSlots = [(0, 1), (0, 2), (1, 3), (2, 3)];
      int offIdx = rng.nextIntRange(0, 3);
      List<(int, int, int, bool, String)> localSpecs = [];
      Map<int, int> hvLocal = {};
      for (int i = 0; i < 4; i++) {
        if (i == offIdx) continue;
        int a = localSlots[i].$1;
        int b = localSlots[i].$2;
        int w = rng.nextBool(0.48) ? 2 : 1;
        int capA = a == 0 ? 1 : 2;
        int capB = b == 0 ? 1 : 2;
        bool canA = (hvLocal[a] ?? 0) + w <= capA;
        bool canB = (hvLocal[b] ?? 0) + w <= capB;
        bool atSecond = (canA && canB)
            ? rng.nextBool(0.5)
            : (canB ? true : (canA ? false : ((hvLocal[b] ?? 0) <= (hvLocal[a] ?? 0))));
        if (!canA && !canB) w = 1;
        int restIdx = atSecond ? b : a;
        hvLocal[restIdx] = (hvLocal[restIdx] ?? 0) + w;
        localSpecs.add((a, b, w, atSecond, 'u'));
      }
      List<TilePairSpec> pairs = localSpecs
          .map((ls) => TilePairSpec(
                ka: names[ls.$1],
                kb: names[ls.$2],
                w: ls.$3,
                kat: ls.$4 ? names[ls.$2] : names[ls.$1],
                baseTail: ls.$5,
              ))
          .toList();
      var offPair = localSlots[offIdx];
      TileDef tileDef = TileDef(
        usedPorts: const ['p1', 'p2', 'p3', 'p4'],
        pairs: pairs,
        off: [(names[offPair.$1], names[offPair.$2])],
        spawnPieces: true,
      );

      List<_BoxSpec> boxes = [];
      for (int i = 0; i < pickedBoxes.length; i++) {
        var (int bx, int by, bool r180) = pickedBoxes[i];
        Map<String, String> cmap = r180
            ? {
                'n00': BG(bx + 1, by + 1),
                'n10': BG(bx, by + 1),
                'n01': BG(bx + 1, by),
                'n11': BG(bx, by),
              }
            : {
                'n00': BG(bx, by),
                'n10': BG(bx + 1, by),
                'n01': BG(bx, by + 1),
                'n11': BG(bx + 1, by + 1),
              };
        Set<String> portSlots = {};
        if (!r180) {
          if (bx + 2 < n) {
            portSlots.add(_slotKey(BG(bx + 1, by), BG(bx + 2, by)));
            portSlots.add(_slotKey(BG(bx + 1, by + 1), BG(bx + 2, by + 1)));
          }
          if (by + 2 < n) {
            portSlots.add(_slotKey(BG(bx, by + 1), BG(bx, by + 2)));
            portSlots.add(_slotKey(BG(bx + 1, by + 1), BG(bx + 1, by + 2)));
          }
        } else {
          if (bx >= 1) {
            portSlots.add(_slotKey(BG(bx, by), BG(bx - 1, by)));
            portSlots.add(_slotKey(BG(bx, by + 1), BG(bx - 1, by + 1)));
          }
          if (by >= 1) {
            portSlots.add(_slotKey(BG(bx, by), BG(bx, by - 1)));
            portSlots.add(_slotKey(BG(bx + 1, by), BG(bx + 1, by - 1)));
          }
        }
        boxes.add(_BoxSpec(
          id: 'A${i + 1}',
          cellMap: cmap,
          owner: 0,
          rot180: r180,
          allowedPortSlots: portSlots,
        ));
      }

      Set<String> tileCells = {for (final b in boxes) ...b.cellMap.values};
      Set<String> allowedPortSlots = {for (final b in boxes) ...b.allowedPortSlots};

      List<_ConnSpec> coreConns = [
        _ConnSpec(u: uStar, v: g0, w: 2, atV: false, owner: 0, star: 0),
        _ConnSpec(u: hubC, v: uStar, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c3, v: uStar, w: 1, atV: false, owner: 0),
        _ConnSpec(u: hubC, v: c0, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c0, v: anchorC, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c0, v: c1, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c1, v: c2, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c2, v: c3, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c3, v: c0, w: 1, atV: false, owner: 0),
        _ConnSpec(u: inC, v: hubC, w: 1, atV: false, owner: 0),
      ];
      for (final b in boxes) {
        for (final ls in localSpecs) {
          coreConns.add(_ConnSpec(
            u: b.cellMap[names[ls.$1]]!,
            v: b.cellMap[names[ls.$2]]!,
            w: ls.$3,
            atV: ls.$4,
            owner: 0,
          ));
        }
      }

      Set<String> usedKeys = {for (final c in coreConns) _slotKey(c.u, c.v)};
      Set<String> lockedShuttleVerts = {g0, uStar, hubC, c0, c1, c2, c3};
      List<(String, String)> candOuter = slots.where((uv) {
        String sk = '${uv.$1}-${uv.$2}';
        if (usedKeys.contains(sk)) return false;
        if (lockedShuttleVerts.contains(uv.$1) || lockedShuttleVerts.contains(uv.$2)) return false;
        bool uTile = tileCells.contains(uv.$1);
        bool vTile = tileCells.contains(uv.$2);
        if (uTile && vTile) {
          String b1 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$1)).id;
          String b2 = boxes.firstWhere((b) => b.cellMap.containsValue(uv.$2)).id;
          return b1 != b2 &&
              boxes.any((b) => b.id == b1 && b.allowedPortSlots.contains(sk)) &&
              boxes.any((b) => b.id == b2 && b.allowedPortSlots.contains(sk));
        }
        if (uTile || vTile) return allowedPortSlots.contains(sk);
        return true;
      }).toList();

      int targetTotal = rng.nextIntRange(minM, maxM);
      int needMore = math.min(candOuter.length, math.max(0, targetTotal - coreConns.length));
      List<(String, String)> pickedOuter = rng.shuffled(candOuter).take(needMore).toList();

      // Orient pickedOuter toward `inC` so solving the folded boxes unlocks `(inC, hubC)`!
      Map<String, int> dIn = _bfsGraphDist(inC, [
        ...pickedOuter,
        for (final c in coreConns) (c.u, c.v),
      ]);
      Map<String, int> hv = {};
      for (final c in coreConns) {
        String h = c.restingCell;
        hv[h] = (hv[h] ?? 0) + c.w;
      }
      List<String> startPool = dIn.keys.where((v) => !lockedShuttleVerts.contains(v) && v != inC).toList();
      Set<String> starters = rng.shuffled(startPool).take(2).toSet();
      if (starters.isEmpty) starters.add(inC);

      List<_ConnSpec> allConns = List<_ConnSpec>.from(coreConns);
      for (final (String u, String v) in pickedOuter) {
        String farEnd = (dIn[u] ?? 99) <= (dIn[v] ?? 99) ? v : u;
        String nearEnd = farEnd == v ? u : v;
        int capFar = starters.contains(farEnd) ? 4 : 2;
        int capNear = starters.contains(nearEnd) ? 4 : 2;
        int w = rng.nextBool(0.48) ? 2 : 1;
        String rest = ((hv[farEnd] ?? 0) + w <= capFar)
            ? farEnd
            : (((hv[nearEnd] ?? 0) + w <= capNear) ? nearEnd : ((hv[farEnd] ?? 0) <= (hv[nearEnd] ?? 0) ? farEnd : nearEnd));
        if ((hv[rest] ?? 0) + w > (starters.contains(rest) ? 4 : 2)) w = 1;
        hv[rest] = (hv[rest] ?? 0) + w;
        allConns.add(_ConnSpec(u: u, v: v, w: w, atV: rest == v, owner: 0));
      }

      List<_ConnSpec> norm = allConns.map((c) => c.canonical()).toList();
      if (!_spansAllRowsAndCols(n, norm.map((c) => (c.u, c.v)))) continue;

      var (int? dFree, List<int> path, _) = _probe1P(g0, norm, Rg.thr, false, cap: 3500);
      if (dFree == null || dFree < minDist) continue;
      if (!path.any((idx) => tileCells.contains(norm[idx].u) || tileCells.contains(norm[idx].v))) continue;
      var (int? dOnce, _, _) = _probe1P(g0, norm, Rg.thr, true, cap: 3500);
      if (Rg.thr > 0 && dOnce != null) continue;

      GridBoard b = _connListToBoard(
        n,
        g0,
        null,
        norm,
        foldSpec: _FoldSpec(boxes: boxes, sym: boxSym, tileDef: tileDef),
      );
      return Puzzle(
        board: b,
        log: [
          'Procedural folded 2×2 shuttle (${boxes.map((x) => x.id).join(', ')}) solvable in $dFree slides.',
          'Unsolvable under once-only slides; ${norm.length} unfolded connectors on $n×$n.',
        ],
      );
    }
    return null;
  }

  // ---- Regime D1: Procedural 1-Player Once-Only (NP-complete) ----

  static Puzzle? _synthesizeOnePlayerOnceNP(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    List<String> allCells = [
      for (int r = 0; r < n; r++)
        for (int c = 0; c < n; c++) cellId(c, r),
    ];
    int minDist = n <= 4 ? 4 : (n == 5 ? 6 : 7);
    int maxDist = n <= 4 ? 10 : (n == 5 ? 16 : 22);

    for (int att = 0; att < 300; att++) {
      String g0 = rng.choice(allCells);
      var s0 = rng.choice(slots.where((s) => s.$1 == g0 || s.$2 == g0).toList());
      int targetM = rng.nextIntRange(minM, maxM);
      List<(String, String)> chosen = _growFullGridSubgraph(rng, n, slots, [s0], targetM, {g0});
      if (!_spansAllRowsAndCols(n, chosen)) continue;

      String s0Key = '${s0.$1}-${s0.$2}';
      List<(String, String)> rest = chosen.where((s) => '${s.$1}-${s.$2}' != s0Key).toList();
      List<_ConnSpec> conn = _orientControlled1P(
        rng,
        g0,
        s0,
        rest,
        numStarters: 3,
        weight2Prob: 0.46,
      );

      var (int? dist, _, _) = _probe1P(g0, conn, Rg.thr, true);
      if (dist == null || dist < minDist || dist > maxDist) continue;

      Map<String, int> hv = {};
      for (final c in conn) {
        String h = c.restingCell;
        hv[h] = (hv[h] ?? 0) + c.w;
      }
      List<int> openMvs = [];
      for (int idx = 0; idx < conn.length; idx++) {
        _ConnSpec c = conn[idx];
        String h = c.restingCell;
        if ((hv[h] ?? 0) - c.w >= (h == g0 ? 0 : Rg.thr)) openMvs.add(idx);
      }
      if (openMvs.length < 2) continue;

      bool hasTrap = false;
      for (final int idx in openMvs) {
        List<_ConnSpec> sub = [
          for (int j = 0; j < conn.length; j++)
            j == idx
                ? _ConnSpec(
                    u: conn[j].u,
                    v: conn[j].v,
                    w: conn[j].w,
                    atV: !conn[j].atV,
                    owner: 1,
                    star: conn[j].star,
                  )
                : conn[j],
        ];
        if (_probe1P(g0, sub, Rg.thr, true).$1 == null) {
          hasTrap = true;
          break;
        }
      }
      if (!hasTrap) continue;

      GridBoard b = _connListToBoard(n, g0, null, conn);
      return Puzzle(
        board: b,
        log: [
          'Procedural once-only constraint-logic board solvable in $dist slides (${conn.length} connectors on $n×$n).',
          'Includes at least one dead-end opening trap under the once rule.',
        ],
      );
    }
    return null;
  }

  // ---- Regime D2: Procedural 1-Player Reversible Shuttle (PSPACE-complete) ----

  static Puzzle? _synthesizeOnePlayerShuttlePSPACE(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    int minDist = n <= 4 ? 8 : (n == 5 ? 10 : 12);

    int maxAtt = n <= 4 ? 420 : 220;
    for (int att = 0; att < maxAtt; att++) {
      int hubSym = rng.nextIntRange(0, 7);
      int dx = rng.nextIntRange(0, n - 3);
      int dy = rng.nextIntRange(0, n - 2);
      String H(int x, int y) {
        var (int cx, int cy) = transformCoord(x + dx, y + dy, n, hubSym);
        return cellId(cx, cy);
      }

      String uStar = H(0, 0);
      String hubC = H(0, 1);
      String c0 = H(1, 1);
      String c1 = H(2, 1);
      String c2 = H(2, 0);
      String c3 = H(1, 0);
      Set<String> hSet = {uStar, hubC, c0, c1, c2, c3};

      List<String> g0Cands = [
        for (final s in slots)
          if (s.$1 == uStar && !hSet.contains(s.$2))
            s.$2
          else if (s.$2 == uStar && !hSet.contains(s.$1))
            s.$1,
      ];
      if (g0Cands.isEmpty) continue;
      String g0 = rng.choice(g0Cands);

      List<String> inCands = [
        for (final s in slots)
          if (s.$1 == hubC && !hSet.contains(s.$2) && s.$2 != g0)
            s.$2
          else if (s.$2 == hubC && !hSet.contains(s.$1) && s.$1 != g0)
            s.$1,
      ];
      if (inCands.isEmpty) continue;
      String inC = rng.choice(inCands);

      List<String> anchCands = [
        for (final s in slots)
          if (s.$1 == c0 && !hSet.contains(s.$2) && s.$2 != g0)
            s.$2
          else if (s.$2 == c0 && !hSet.contains(s.$1) && s.$1 != g0)
            s.$1,
      ];
      if (anchCands.isEmpty) continue;
      String anchorC = rng.choice(anchCands);

      List<_ConnSpec> coreConns = [
        _ConnSpec(u: uStar, v: g0, w: 2, atV: false, owner: 0, star: 0),
        _ConnSpec(u: hubC, v: uStar, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c3, v: uStar, w: 1, atV: false, owner: 0),
        _ConnSpec(u: hubC, v: c0, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c0, v: anchorC, w: 1, atV: false, owner: 0),
        _ConnSpec(u: c0, v: c1, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c1, v: c2, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c2, v: c3, w: 2, atV: false, owner: 0),
        _ConnSpec(u: c3, v: c0, w: 1, atV: false, owner: 0),
        _ConnSpec(u: inC, v: hubC, w: 1, atV: false, owner: 0),
      ];

      Set<String> coreKeys = {for (final c in coreConns) _slotKey(c.u, c.v)};
      Set<String> protectVerts =
          n <= 4 ? {g0, uStar, hubC, c0, c3} : {g0, uStar, hubC, c0, c1, c2, c3};
      int targetM = rng.nextIntRange(minM, maxM);
      int wantExtra = math.max(2, targetM - coreConns.length);

      List<(String, String)> outerGraph = _growFullGridSubgraph(
        rng,
        n,
        slots,
        [(inC, hubC), (c0, anchorC)],
        wantExtra + 2,
        protectVerts,
        forbidSlotKeys: coreKeys,
      );
      List<(String, String)> outerOnly =
          outerGraph.where((uv) => !coreKeys.contains('${uv.$1}-${uv.$2}')).toList();
      if (outerOnly.length < wantExtra) {
        Set<String> haveKeys = {
          ...coreKeys,
          for (final uv in outerOnly) '${uv.$1}-${uv.$2}',
        };
        List<(String, String)> extraPool = slots
            .where((uv) =>
                !haveKeys.contains('${uv.$1}-${uv.$2}') &&
                !protectVerts.contains(uv.$1) &&
                !protectVerts.contains(uv.$2))
            .toList();
        outerOnly.addAll(rng.shuffled(extraPool).take(wantExtra - outerOnly.length));
      }

      Map<String, int> dIn = _bfsGraphDist(inC, [
        ...outerOnly,
        for (final c in coreConns) (c.u, c.v),
      ]);
      if (n >= 5) {
        int reachableOuter = dIn.keys.where((v) => !protectVerts.contains(v)).length;
        if (reachableOuter < 10) continue;
      }
      Map<String, int> hv = {};
      for (final c in coreConns) {
        String h = c.restingCell;
        hv[h] = (hv[h] ?? 0) + c.w;
      }

      List<String> inCNeighbors = [
        for (final uv in outerOnly)
          if (uv.$1 == inC) uv.$2 else if (uv.$2 == inC) uv.$1,
      ];
      if (inCNeighbors.isEmpty) continue;

      List<String> startPool = dIn.keys
          .where((v) => !hSet.contains(v) && v != g0 && v != inC && (dIn[v] ?? 0) >= 1)
          .toList();
      Set<String> starters = rng.shuffled(startPool).take(n <= 4 ? 2 : 3).toSet();
      if (inCNeighbors.length == 1) starters.add(inCNeighbors.first);
      if (starters.isEmpty) starters.add(inC);

      List<(String, String)> orderedOuter = rng.shuffled(outerOnly);
      orderedOuter.sort((a, b) {
        int da = math.min(dIn[a.$1] ?? 99, dIn[a.$2] ?? 99);
        int db = math.min(dIn[b.$1] ?? 99, dIn[b.$2] ?? 99);
        return da.compareTo(db);
      });

      bool primedInC = false;
      List<_ConnSpec> allConns = List<_ConnSpec>.from(coreConns);
      for (final (String u, String v) in orderedOuter) {
        String farEnd = (dIn[u] ?? 99) <= (dIn[v] ?? 99) ? v : u;
        String nearEnd = farEnd == v ? u : v;
        if (farEnd == c1 || farEnd == c2) {
          String tmp = farEnd;
          farEnd = nearEnd;
          nearEnd = tmp;
        }
        if (nearEnd == inC && inCNeighbors.length >= 2 && !primedInC && farEnd != c1 && farEnd != c2) {
          primedInC = true;
          hv[inC] = (hv[inC] ?? 0) + 1;
          allConns.add(_ConnSpec(u: u, v: v, w: 1, atV: inC == v, owner: 0));
          continue;
        }
        int capFar = starters.contains(farEnd) ? 4 : 2;
        int capNear = (nearEnd == c1 || nearEnd == c2) ? 2 : (starters.contains(nearEnd) ? 4 : 2);
        int w = (nearEnd == inC && inCNeighbors.length == 1)
            ? 2
            : (rng.nextBool(0.48) ? 2 : 1);
        String rest;
        if ((hv[farEnd] ?? 0) + w <= capFar) {
          rest = farEnd;
        } else if ((hv[farEnd] ?? 0) + 1 <= capFar && !(nearEnd == inC && inCNeighbors.length == 1)) {
          w = 1;
          rest = farEnd;
        } else if ((hv[nearEnd] ?? 0) + w <= capNear) {
          rest = nearEnd;
        } else {
          w = 1;
          rest = (nearEnd == c1 || nearEnd == c2) ? farEnd : nearEnd;
        }
        hv[rest] = (hv[rest] ?? 0) + w;
        allConns.add(_ConnSpec(u: u, v: v, w: w, atV: rest == v, owner: 0));
      }

      List<_ConnSpec> norm = allConns.map((c) => c.canonical()).toList();
      if (!_spansAllRowsAndCols(n, norm.map((c) => (c.u, c.v)))) continue;

      var (int? dFree, _, _) = _probe1P(g0, norm, Rg.thr, false, cap: 3500);
      if (dFree == null || dFree < minDist) continue;
      var (int? dOnce, _, _) = _probe1P(g0, norm, Rg.thr, true, cap: 3500);
      if (Rg.thr > 0 && !Rg.once && dOnce != null) continue;

      GridBoard b = _connListToBoard(n, g0, null, norm);
      return Puzzle(
        board: b,
        log: [
          'Procedural PSPACE shuttle board solvable in $dFree slides (${norm.length} connectors on $n×$n).',
          'Strictly requires reversing a shuttle meeple (unsolvable under once-only slides).',
        ],
      );
    }
    return null;
  }

  // ---- Guaranteed Full-Grid Fallback ----

  static Puzzle _synthesizeGuaranteedFullGridFallback(
    int n,
    Random32 rng,
    Switches Rg,
    List<(String, String)> slots,
    int minM,
    int maxM,
  ) {
    String g0 = cellId(n - 1, n - 1);
    var s0 = (cellId(n - 2, n - 1), g0);
    int targetM = rng.nextIntRange(minM, maxM);
    List<(String, String)> chosen = _growFullGridSubgraph(rng, n, slots, [s0], targetM, {g0});
    String s0Key = '${s0.$1}-${s0.$2}';
    List<(String, String)> rest = chosen.where((s) => '${s.$1}-${s.$2}' != s0Key).toList();
    List<_ConnSpec> conn = _orientControlled1P(rng, g0, s0, rest, numStarters: 4, weight2Prob: 0.5);
    return Puzzle(
      board: _connListToBoard(n, g0, null, conn),
      log: ['Procedural $n×$n constraint-logic board (${conn.length} connectors).'],
    );
  }
}
