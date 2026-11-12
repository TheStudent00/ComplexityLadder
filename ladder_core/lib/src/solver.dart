import 'dart:math' as math;

import 'board.dart';
import 'rules.dart';
import 'switches.dart';

class SolveResult {
  final int? dist;
  final int? oppDist;
  final TreeAction? action;
  final List<GridBoard> pathBoards;
  final int visited;
  final String unit;

  const SolveResult({
    required this.dist,
    required this.oppDist,
    required this.action,
    required this.pathBoards,
    required this.visited,
    required this.unit,
  });
}

/// One node in the bounded Combinatorial Move Tree T_C.
class TreeNode {
  final int id;
  final int? superId;
  final int depth;
  final GridBoard board;
  final String key;
  final TreeAction? action;
  final String shortLabel;
  final bool isGoal;
  final bool isOppLoss;
  final List<int> subIds = [];
  String? trimmedKind; // 'cycle', 'dead', 'forall', or null
  bool onWinPath = false;
  bool onPlayerTrail = false;
  int bruteOrder = -1;
  int trimOrder = -1;

  TreeNode({
    required this.id,
    required this.superId,
    required this.depth,
    required this.board,
    required this.key,
    required this.action,
    required this.shortLabel,
    required this.isGoal,
    required this.isOppLoss,
  });
}

class MoveTree {
  final List<TreeNode> nodes;
  final List<int> bruteSeq;
  final List<int> trimSeq;
  final int activeNodeId;
  final Set<int> activeChainIds;
  final int maxDepth;

  const MoveTree({
    required this.nodes,
    required this.bruteSeq,
    required this.trimSeq,
    required this.activeNodeId,
    required this.activeChainIds,
    required this.maxDepth,
  });
}

class _FlatEdge {
  final String id;
  final String? edgeId;
  final String u;
  final String v;
  final String tail;
  final int w;
  final String to; // 'u' or 'v'
  final int owner;
  final int? star;
  final bool moved;
  final bool fixed;

  const _FlatEdge({
    required this.id,
    required this.edgeId,
    required this.u,
    required this.v,
    required this.tail,
    required this.w,
    required this.to,
    required this.owner,
    required this.star,
    required this.moved,
    required this.fixed,
  });
}

class _TwoOut {
  final String id;
  final String? edgeId;
  final String? to;
  final String nk;

  const _TwoOut({required this.id, this.edgeId, this.to, required this.nk});
}

class _TwoMeta {
  final int mv;
  final int om;
  final int mm;
  final int? win;

  const _TwoMeta({required this.mv, required this.om, required this.mm, required this.win});
}

class _TwoTable {
  final List<_FlatEdge> conn;
  final Map<String, List<_TwoOut>> succ;
  final Map<String, int> gDist;
  final Map<String, int> pDist;
  final int visited;

  const _TwoTable({
    required this.conn,
    required this.succ,
    required this.gDist,
    required this.pDist,
    required this.visited,
  });
}

class Solver {
  static String _mKey(String vid, String? from) => '$vid|${from ?? ''}';

  static List<(String, String?)> _mPlaces(GridBoard st) {
    List<(String, String?)> out = [];
    for (final entry in st.verts.entries) {
      if (entry.value.isBox) continue;
      String n = entry.key;
      out.add((n, null));
      for (final Connector e in st.edges) {
        if (e.touches(n)) out.add((n, e.id));
      }
    }
    return out;
  }

  static List<String> _mSucc(GridBoard st, Switches s, String vid, String? from) {
    return Rules.exitsFrom(st, s, vid, from).map((e) => _mKey(e.farOf(vid), e.id)).toList();
  }

  static Set<String> walkWinSet(GridBoard st, Switches s) {
    List<(String, String?)> places = _mPlaces(st);
    Set<String> win = {
      for (final (String n, String? f) in places)
        if (st.verts[n]?.goal == 0) _mKey(n, f),
    };
    bool changed = true;
    while (changed) {
      changed = false;
      for (final (String n, String? f) in places) {
        String k = _mKey(n, f);
        if (win.contains(k)) continue;
        List<String> sc = _mSucc(st, s, n, f);
        if (sc.isEmpty) continue;
        bool ok = Rules.isAltCell(st, s, n) ? sc.every(win.contains) : sc.any(win.contains);
        if (ok) {
          win.add(k);
          changed = true;
        }
      }
    }
    return win;
  }

  static Map<String, int> walkDist(GridBoard st, Switches s) {
    List<(String, String?)> places = _mPlaces(st);
    Map<String, int> dist = {};
    for (final (String n, String? f) in places) {
      if (st.verts[n]?.goal == 0) dist[_mKey(n, f)] = 0;
    }
    bool changed = true;
    while (changed) {
      changed = false;
      for (final (String n, String? f) in places) {
        String k = _mKey(n, f);
        if (st.verts[n]?.goal == 0) continue;
        List<String> all = _mSucc(st, s, n, f);
        List<String> sc = all.where(dist.containsKey).toList();
        if (sc.isEmpty) continue;
        int? d;
        if (Rules.isAltCell(st, s, n)) {
          if (all.every(dist.containsKey)) {
            int worst = 0;
            for (final String m in all) {
              worst = math.max(worst, dist[m]!);
            }
            d = worst + 1;
          }
        } else {
          int best = sc.map((m) => dist[m]!).reduce(math.min);
          d = best + 1;
        }
        if (d != null && (!dist.containsKey(k) || d < dist[k]!)) {
          dist[k] = d;
          changed = true;
        }
      }
    }
    return dist;
  }

  static (Map<String, CellNode>, List<_FlatEdge>) _flatView(GridBoard st) {
    GridBoard exp = st.expandAll();
    List<_FlatEdge> edges = [];
    List<Meeple> ordered = List<Meeple>.from(exp.pieces)..sort((a, b) => a.id.compareTo(b.id));
    for (final Meeple p in ordered) {
      if (p.on != null) {
        Connector? e = exp.edgeOf(p.on);
        if (e != null) {
          edges.add(_FlatEdge(
            id: p.id,
            edgeId: e.id,
            u: e.u,
            v: e.v,
            tail: e.tail,
            w: p.w,
            to: p.at == e.v ? 'v' : 'u',
            owner: p.owner,
            star: p.star,
            moved: p.moved,
            fixed: false,
          ));
        }
      } else {
        edges.add(_FlatEdge(
          id: p.id,
          edgeId: null,
          u: p.at,
          v: p.at,
          tail: 'u',
          w: p.w,
          to: 'u',
          owner: p.owner,
          star: p.star,
          moved: p.moved,
          fixed: true,
        ));
      }
    }
    return (exp.verts, edges);
  }

  static String? _boxHoldingPiece(GridBoard st, Switches s, String? pieceId) {
    if (pieceId == null) return null;
    Meeple? p = st.pieceOf(pieceId);
    if (p == null) {
      String? b = st.ownerBoxOfHiddenPiece(pieceId);
      return (b != null && st.isBox(b)) ? b : null;
    }
    StepMove? u = Rules.movesOf(st, s, p).where((m) => m.kind == 'unfold').firstOrNull;
    return u?.box;
  }

  static _TwoTable _buildTwoPlayerRetrograde(GridBoard refSt, Switches s) {
    var (Map<String, CellNode> verts, List<_FlatEdge> allEdges) = _flatView(refSt);
    List<_FlatEdge> conn = allEdges.where((e) => !e.fixed).toList();
    int initOrient = 0;
    int initMoved = 0;
    for (int i = 0; i < conn.length; i++) {
      if (conn[i].to == 'v') initOrient |= (1 << i);
      if (conn[i].moved) initMoved |= (1 << i);
    }
    String keyOf(int mv, int om, int mm) => s.once ? '$mv|$om|$mm' : '$mv|$om';

    Map<String, int> fixedHave = {for (final v in verts.keys) v: 0};
    for (final _FlatEdge e in allEdges) {
      if (e.fixed) fixedHave[e.u] = (fixedHave[e.u] ?? 0) + e.w;
    }

    String headOf(int i, int om) => ((om & (1 << i)) != 0) ? conn[i].v : conn[i].u;

    int? winMask(int om) {
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].star != null) {
          String h = headOf(i, om);
          if (verts[h]?.goal == conn[i].star) return conn[i].star;
        }
      }
      return null;
    }

    List<(int, String, String?, String, int, int)> legalFor(int mover, int om, int mm) {
      Map<String, int> hv = Map<String, int>.from(fixedHave);
      for (int i = 0; i < conn.length; i++) {
        String h = headOf(i, om);
        hv[h] = (hv[h] ?? 0) + conn[i].w;
      }
      List<(int, String, String?, String, int, int)> out = [];
      for (int i = 0; i < conn.length; i++) {
        _FlatEdge e = conn[i];
        if (e.owner != mover) continue;
        if (s.once && ((mm & (1 << i)) != 0)) continue;
        String h = headOf(i, om);
        if (s.directed && ((e.tail == 'u' ? e.u : e.v) != h)) continue;
        int need = verts[h]?.goal != null ? 0 : s.thr;
        if ((hv[h] ?? 0) - e.w >= need) {
          String toCell = ((om & (1 << i)) != 0) ? e.u : e.v;
          out.add((i, e.id, e.edgeId, toCell, om ^ (1 << i), mm | (1 << i)));
        }
      }
      return out;
    }

    String startK = keyOf(refSt.turn, initOrient, initMoved);
    Map<String, _TwoMeta> metaMap = {
      startK: _TwoMeta(mv: refSt.turn, om: initOrient, mm: initMoved, win: winMask(initOrient)),
    };
    Map<String, List<_TwoOut>> succ = {};
    List<String> queue = [startK];
    int qi = 0;

    while (qi < queue.length && metaMap.length < 45000) {
      String k = queue[qi++];
      if (succ.containsKey(k)) continue;
      _TwoMeta info = metaMap[k]!;
      if (info.win != null) {
        succ[k] = const [];
        continue;
      }
      var mvs = legalFor(info.mv, info.om, info.mm);
      List<_TwoOut> outs = [];
      if (mvs.isEmpty) {
        if (info.mv == 1 && legalFor(0, info.om, info.mm).isNotEmpty) {
          String nk = keyOf(0, info.om, info.mm);
          metaMap.putIfAbsent(nk, () {
            queue.add(nk);
            return _TwoMeta(mv: 0, om: info.om, mm: info.mm, win: winMask(info.om));
          });
          outs.add(_TwoOut(id: 'pass', nk: nk));
        }
      } else {
        for (final (_, String id, String? edgeId, String toCell, int nextOm, int nextMm) in mvs) {
          String nk = keyOf(1 - info.mv, nextOm, nextMm);
          metaMap.putIfAbsent(nk, () {
            queue.add(nk);
            return _TwoMeta(mv: 1 - info.mv, om: nextOm, mm: nextMm, win: winMask(nextOm));
          });
          outs.add(_TwoOut(id: id, edgeId: edgeId, to: toCell, nk: nk));
        }
      }
      succ[k] = outs;
    }

    Map<String, int> computeMinimaxDist(int targetWinner) {
      Map<String, int> dist = {};
      for (final entry in metaMap.entries) {
        if (entry.value.win == targetWinner) dist[entry.key] = 0;
      }
      bool changed = true;
      while (changed) {
        changed = false;
        for (final entry in succ.entries) {
          String k = entry.key;
          List<_TwoOut> outs = entry.value;
          _TwoMeta info = metaMap[k]!;
          if (info.win != null || outs.isEmpty) continue;
          if (info.mv == targetWinner) {
            int? best;
            for (final _TwoOut o in outs) {
              int? d = dist[o.nk];
              if (d != null && (best == null || d + 1 < best)) best = d + 1;
            }
            if (best != null && (!dist.containsKey(k) || best < dist[k]!)) {
              dist[k] = best;
              changed = true;
            }
          } else {
            bool allIn = true;
            int worst = 0;
            for (final _TwoOut o in outs) {
              int? d = dist[o.nk];
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
      return dist;
    }

    return _TwoTable(
      conn: conn,
      succ: succ,
      gDist: computeMinimaxDist(0),
      pDist: computeMinimaxDist(1),
      visited: succ.length,
    );
  }

  /// Exact solver across all regimes of the Complexity Ladder.
  static SolveResult solve(Switches s, GridBoard st) {
    int? w = Rules.winnerOf(st);
    if (w == 0) {
      return SolveResult(
        dist: 0,
        oppDist: null,
        action: null,
        pathBoards: [st.clone()],
        visited: 1,
        unit: s.open ? 'connectors' : (s.two ? 'plies' : 'slides'),
      );
    }
    if (w == 1) {
      return const SolveResult(
        dist: null,
        oppDist: 0,
        action: null,
        pathBoards: [],
        visited: 1,
        unit: 'plies',
      );
    }

    // 1. Open-centre reachability regime (L, NL, P, plus folded walk)
    if (st.isWalkRegime(s)) {
      GridBoard exp = st.expandAll();
      Set<String> win = walkWinSet(exp, s);
      Map<String, int> distMap = walkDist(exp, s);
      Meeple? pm = exp.starMeeple(0);
      if (pm == null) {
        return SolveResult(
          dist: null,
          oppDist: null,
          action: null,
          pathBoards: const [],
          visited: 0,
          unit: s.alt ? 'plies' : 'connectors',
        );
      }

      Set<String> reachVerts = {pm.at};
      List<String> rq = [pm.at];
      int rqi = 0;
      while (rqi < rq.length) {
        String u = rq[rqi++];
        for (final Connector e in Rules.exitsFrom(exp, s, u, null)) {
          String v = e.farOf(u);
          if (reachVerts.add(v)) rq.add(v);
        }
      }

      String curPlace = pm.on != null ? _mKey(pm.at, null) : _mKey(pm.at, pm.from);
      bool canWin = s.alt ? win.contains(curPlace) : distMap.containsKey(curPlace);
      if (!canWin && st.turn == 0) {
        return SolveResult(
          dist: null,
          oppDist: null,
          action: null,
          pathBoards: const [],
          visited: reachVerts.length,
          unit: s.alt ? 'plies' : 'connectors',
        );
      }

      List<GridBoard> pathBoards = [st.clone()];
      GridBoard cur = st.clone();
      TreeAction? firstAction;
      for (int step = 0; step < 48 && Rules.winnerOf(cur) == null; step++) {
        Meeple? pCur = cur.starMeeple(0);
        if (pCur == null) break;
        if (cur.isBox(pCur.at)) {
          TreeAction act = TreeAction(kind: 'unfold', box: pCur.at, by: cur.turn);
          firstAction ??= act;
          cur = Rules.applyAction(cur, s, act);
          pathBoards.add(cur.clone());
          continue;
        }
        List<Connector> es;
        if (pCur.on != null) {
          Connector? eOn = cur.edgeOf(pCur.on);
          es = (eOn != null && (!s.directed || eOn.arrowFrom(pCur.at))) ? [eOn] : const [];
        } else {
          es = Rules.exitsFrom(cur, s, pCur.at, pCur.from);
        }
        if (es.isEmpty) break;

        String nextKey(Connector e) {
          String far = e.farOf(pCur.at);
          if (cur.isBox(far)) {
            Connector? eExp = exp.edgeOf(e.id);
            return _mKey(eExp != null ? eExp.farOf(pCur.at) : far, e.id);
          }
          return _mKey(far, e.id);
        }

        Connector chosen;
        if (cur.turn == 1) {
          List<Connector> losing = es.where((e) => !win.contains(nextKey(e))).toList();
          List<Connector> pool = losing.isNotEmpty ? losing : List<Connector>.from(es);
          pool.sort((a, b) => (distMap[nextKey(b)] ?? 99).compareTo(distMap[nextKey(a)] ?? 99));
          chosen = pool.first;
        } else {
          List<Connector> winning = es.where((e) => !s.alt || win.contains(nextKey(e))).toList();
          if (winning.isEmpty) break;
          winning.sort((a, b) => (distMap[nextKey(a)] ?? 99).compareTo(distMap[nextKey(b)] ?? 99));
          chosen = winning.first;
        }
        String far = chosen.farOf(pCur.at);
        TreeAction act = cur.isBox(far)
            ? TreeAction(kind: 'unfold', box: far, by: cur.turn)
            : TreeAction(kind: 'walk', pieceId: pCur.id, edge: chosen.id, to: far, by: cur.turn);
        firstAction ??= act;
        cur = Rules.applyAction(cur, s, act);
        pathBoards.add(cur.clone());
      }

      return SolveResult(
        dist: canWin ? distMap[curPlace] : null,
        oppDist: null,
        action: firstAction,
        pathBoards: pathBoards,
        visited: reachVerts.length,
        unit: s.alt ? 'plies' : 'connectors',
      );
    }

    // 2. Closed-centre 1-player regime (NP, PSPACE, NEXPTIME, EXPSPACE)
    if (!s.open && !s.two) {
      var (Map<String, CellNode> verts, List<_FlatEdge> allEdges) = _flatView(st);
      List<_FlatEdge> conn = allEdges.where((e) => !e.fixed).toList();
      Map<String, int> fixedHave = {for (final v in verts.keys) v: 0};
      for (final _FlatEdge e in allEdges) {
        if (e.fixed) fixedHave[e.u] = (fixedHave[e.u] ?? 0) + e.w;
      }

      int initOm = 0;
      int initMm = 0;
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].to == 'v') initOm |= (1 << i);
        if (conn[i].moved) initMm |= (1 << i);
      }

      String headOf(int i, int om) => ((om & (1 << i)) != 0) ? conn[i].v : conn[i].u;
      bool isWin0(int om) {
        for (int i = 0; i < conn.length; i++) {
          if (conn[i].star == 0 && verts[headOf(i, om)]?.goal == 0) return true;
        }
        return false;
      }

      int startState = s.once ? 0 : initOm;
      Map<int, (int, int)?> prev = {startState: null};
      List<int> q = [startState];
      int qi = 0;
      int? goalState;

      while (qi < q.length && prev.length < 80000) {
        int state = q[qi++];
        int om = s.once ? (initOm ^ state) : state;
        int mm = s.once ? (initMm | state) : 0;
        if (isWin0(om)) {
          goalState ??= state;
          continue;
        }
        Map<String, int> hv = Map<String, int>.from(fixedHave);
        for (int i = 0; i < conn.length; i++) {
          String h = headOf(i, om);
          hv[h] = (hv[h] ?? 0) + conn[i].w;
        }
        for (int i = 0; i < conn.length; i++) {
          _FlatEdge e = conn[i];
          if (e.owner != 0) continue;
          if (s.once && ((mm & (1 << i)) != 0)) continue;
          String h = headOf(i, om);
          if (s.directed && ((e.tail == 'u' ? e.u : e.v) != h)) continue;
          int need = verts[h]?.goal != null ? 0 : s.thr;
          if ((hv[h] ?? 0) - e.w >= need) {
            int ns = state ^ (1 << i);
            if (!prev.containsKey(ns)) {
              prev[ns] = (state, i);
              q.add(ns);
            }
          }
        }
      }

      if (goalState == null) {
        return SolveResult(
          dist: null,
          oppDist: null,
          action: null,
          pathBoards: const [],
          visited: prev.length,
          unit: 'slides',
        );
      }

      List<int> slideIndices = [];
      int curS = goalState;
      while (prev[curS] != null) {
        var (int ps, int idx) = prev[curS]!;
        slideIndices.add(idx);
        curS = ps;
      }
      slideIndices = slideIndices.reversed.toList();

      List<GridBoard> pathBoards = [st.clone()];
      GridBoard cur = st.clone();
      TreeAction? firstAction;
      for (final int idx in slideIndices) {
        String pid = conn[idx].id;
        int guard = 0;
        while (guard++ < 8) {
          String? b = _boxHoldingPiece(cur, s, pid);
          if (b == null) break;
          TreeAction uAct = TreeAction(kind: 'unfold', box: b, by: 0);
          firstAction ??= uAct;
          cur = Rules.applyAction(cur, s, uAct);
          pathBoards.add(cur.clone());
        }
        Meeple? p = cur.pieceOf(pid);
        StepMove? sl = p == null ? null : Rules.realMoves(cur, s, p).where((m) => m.kind == 'slide').firstOrNull;
        if (sl == null) break;
        TreeAction sAct = TreeAction(kind: 'slide', pieceId: pid, edge: sl.edge, to: sl.to, by: 0);
        firstAction ??= sAct;
        cur = Rules.applyAction(cur, s, sAct);
        pathBoards.add(cur.clone());
      }

      return SolveResult(
        dist: slideIndices.length,
        oppDist: null,
        action: firstAction,
        pathBoards: pathBoards,
        visited: prev.length,
        unit: 'slides',
      );
    }

    // 3. Closed-centre 2-player regime (EXPTIME, 2EXPTIME)
    if (!s.open && s.two) {
      _TwoTable tbl = _buildTwoPlayerRetrograde(st, s);
      var (_, List<_FlatEdge> allEdges) = _flatView(st);
      List<_FlatEdge> conn = allEdges.where((e) => !e.fixed).toList();
      int om = 0;
      int mm = 0;
      for (int i = 0; i < conn.length; i++) {
        if (conn[i].to == 'v') om |= (1 << i);
        if (conn[i].moved) mm |= (1 << i);
      }
      String k = s.once ? '${st.turn}|$om|$mm' : '${st.turn}|$om';
      int? gD = tbl.gDist[k];
      int? pD = tbl.pDist[k];
      List<_TwoOut> outs = tbl.succ[k] ?? const [];

      _TwoOut? pickBestOut(int mover, List<_TwoOut> outsList) {
        if (outsList.isEmpty) return null;
        if (mover == 0) {
          List<_TwoOut> winMoves = outsList.where((o) => tbl.gDist.containsKey(o.nk)).toList();
          if (winMoves.isNotEmpty) {
            winMoves.sort((a, b) => tbl.gDist[a.nk]!.compareTo(tbl.gDist[b.nk]!));
            return winMoves.first;
          }
          List<_TwoOut> safeMoves = outsList.where((o) => !tbl.pDist.containsKey(o.nk)).toList();
          if (safeMoves.isNotEmpty) return safeMoves.first;
          List<_TwoOut> rest = List<_TwoOut>.from(outsList)
            ..sort((a, b) => (tbl.pDist[b.nk] ?? 0).compareTo(tbl.pDist[a.nk] ?? 0));
          return rest.first;
        } else {
          List<_TwoOut> oppWins = outsList.where((o) => tbl.pDist.containsKey(o.nk)).toList();
          if (oppWins.isNotEmpty) {
            oppWins.sort((a, b) => tbl.pDist[a.nk]!.compareTo(tbl.pDist[b.nk]!));
            return oppWins.first;
          }
          List<_TwoOut> draws = outsList.where((o) => !tbl.gDist.containsKey(o.nk)).toList();
          if (draws.isNotEmpty) return draws.first;
          List<_TwoOut> tough = List<_TwoOut>.from(outsList)
            ..sort((a, b) => (tbl.gDist[b.nk] ?? 0).compareTo(tbl.gDist[a.nk] ?? 0));
          return tough.first;
        }
      }

      TreeAction? firstAction;
      List<GridBoard> pathBoards = [st.clone()];
      _TwoOut? chosen0 = pickBestOut(st.turn, outs);
      if (chosen0 != null && (st.turn == 1 || gD != null)) {
        GridBoard cur = st.clone();
        String curKey = k;
        int curMover = st.turn;
        for (int ply = 0; ply < 36 && Rules.winnerOf(cur) == null; ply++) {
          List<_TwoOut> curOuts = tbl.succ[curKey] ?? const [];
          _TwoOut? pick = pickBestOut(curMover, curOuts);
          if (pick == null) break;
          if (pick.id == 'pass') {
            const TreeAction pAct = TreeAction(kind: 'pass', by: 1);
            firstAction ??= pAct;
            cur = Rules.applyAction(cur, s, pAct);
            pathBoards.add(cur.clone());
          } else if (curMover == 0) {
            int guard = 0;
            while (guard++ < 8) {
              String? b = _boxHoldingPiece(cur, s, pick.id);
              if (b == null) break;
              TreeAction uAct = TreeAction(kind: 'unfold', box: b, by: 0);
              firstAction ??= uAct;
              cur = Rules.applyAction(cur, s, uAct);
              pathBoards.add(cur.clone());
            }
            Meeple? p = cur.pieceOf(pick.id);
            StepMove? sl = p == null ? null : Rules.realMoves(cur, s, p).where((m) => m.kind == 'slide').firstOrNull;
            if (sl == null) break;
            TreeAction sAct = TreeAction(kind: 'slide', pieceId: pick.id, edge: sl.edge, to: sl.to, by: 0);
            firstAction ??= sAct;
            cur = Rules.applyAction(cur, s, sAct);
            pathBoards.add(cur.clone());
          } else {
            TreeAction sAct = TreeAction(
              kind: 'slide',
              pieceId: pick.id,
              edge: pick.edgeId,
              to: pick.to,
              by: 1,
              autoExpand: true,
            );
            firstAction ??= sAct;
            cur = Rules.applyAction(cur, s, sAct);
            pathBoards.add(cur.clone());
          }
          curKey = pick.nk;
          curMover = 1 - curMover;
        }
      }

      return SolveResult(
        dist: gD,
        oppDist: pD,
        action: firstAction,
        pathBoards: pathBoards,
        visited: tbl.visited,
        unit: 'plies',
      );
    }

    // 4. Fallback bounded BFS for custom mixed switch settings
    String startK = st.boardKey(s);
    Map<String, (String, TreeAction)?> prev = {startK: null};
    Map<String, GridBoard> stateMap = {startK: st.clone()};
    List<String> q = [startK];
    int qi = 0;
    String? goalK;
    while (qi < q.length && prev.length < 2500) {
      String uk = q[qi++];
      GridBoard us = stateMap[uk]!;
      if (Rules.winnerOf(us) == 0) {
        goalK = uk;
        break;
      }
      if (us.turn != 0) continue;
      for (final TreeAction act in Rules.enumerateLegalActions(us, s)) {
        GridBoard ns = Rules.applyAction(us, s, act);
        String nk = ns.boardKey(s);
        if (!prev.containsKey(nk)) {
          prev[nk] = (uk, act);
          stateMap[nk] = ns;
          q.add(nk);
        }
      }
    }
    if (goalK == null) {
      return SolveResult(
        dist: null,
        oppDist: null,
        action: null,
        pathBoards: const [],
        visited: prev.length,
        unit: 'moves',
      );
    }
    List<TreeAction> acts = [];
    List<GridBoard> boards = [stateMap[goalK]!];
    String ck = goalK;
    while (prev[ck] != null) {
      var (String pk, TreeAction act) = prev[ck]!;
      acts.add(act);
      boards.add(stateMap[pk]!);
      ck = pk;
    }
    acts = acts.reversed.toList();
    boards = boards.reversed.toList();
    int realCount = acts.where((a) => a.kind != 'unfold').length;
    return SolveResult(
      dist: realCount,
      oppDist: null,
      action: acts.firstOrNull,
      pathBoards: boards,
      visited: prev.length,
      unit: 'moves',
    );
  }

  /// Build a bounded Combinatorial Move Tree T_C synchronised with the player's
  /// live board trail and the exact solver's winning path & branch trimming.
  static MoveTree buildMoveTree({
    required Switches switches,
    required GridBoard initialBoard,
    required GridBoard curBoard,
    required List<GridBoard> history,
    int maxNodes = 44,
    int maxDepthCap = 7,
  }) {
    List<TreeNode> nodes = [];
    Map<String, int> keyToId = {};

    String rootKey = initialBoard.boardKey(switches);
    TreeNode root = TreeNode(
      id: 0,
      superId: null,
      depth: 0,
      board: initialBoard.clone(),
      key: rootKey,
      action: null,
      shortLabel: 's₀',
      isGoal: Rules.winnerOf(initialBoard) == 0,
      isOppLoss: Rules.winnerOf(initialBoard) == 1,
    );
    nodes.add(root);
    keyToId[rootKey] = 0;

    // Ensure the player's actual played trail is represented first in T_C.
    List<GridBoard> trail = [...history, curBoard];
    int curSuper = 0;
    root.onPlayerTrail = true;
    for (int i = 1; i < trail.length && nodes.length < maxNodes; i++) {
      GridBoard b = trail[i];
      String bk = b.boardKey(switches);
      if (keyToId.containsKey(bk)) {
        curSuper = keyToId[bk]!;
        nodes[curSuper].onPlayerTrail = true;
        continue;
      }
      TreeAction? matchAct;
      for (final TreeAction cand in Rules.enumerateLegalActions(nodes[curSuper].board, switches)) {
        if (Rules.applyAction(nodes[curSuper].board, switches, cand).boardKey(switches) == bk) {
          matchAct = cand;
          break;
        }
      }
      int nid = nodes.length;
      TreeNode tn = TreeNode(
        id: nid,
        superId: curSuper,
        depth: nodes[curSuper].depth + 1,
        board: b.clone(),
        key: bk,
        action: matchAct,
        shortLabel: Rules.shortActionLabel(matchAct, b),
        isGoal: Rules.winnerOf(b) == 0,
        isOppLoss: Rules.winnerOf(b) == 1,
      )..onPlayerTrail = true;
      nodes.add(tn);
      nodes[curSuper].subIds.add(nid);
      keyToId[bk] = nid;
      curSuper = nid;
    }

    // Also splice the optimal winning path from curBoard so tree-trimming reaches ★.
    SolveResult sol = solve(switches, curBoard);
    Set<String> winPathKeys = {for (final b in sol.pathBoards) b.boardKey(switches)};
    if (sol.pathBoards.length > 1) {
      int pSuper = keyToId[curBoard.boardKey(switches)] ?? 0;
      for (int i = 1; i < sol.pathBoards.length && nodes.length < maxNodes; i++) {
        GridBoard wb = sol.pathBoards[i];
        String wk = wb.boardKey(switches);
        if (keyToId.containsKey(wk)) {
          pSuper = keyToId[wk]!;
          continue;
        }
        TreeAction? matchAct;
        for (final TreeAction cand in Rules.enumerateLegalActions(nodes[pSuper].board, switches)) {
          if (Rules.applyAction(nodes[pSuper].board, switches, cand).boardKey(switches) == wk) {
            matchAct = cand;
            break;
          }
        }
        int nid = nodes.length;
        TreeNode tn = TreeNode(
          id: nid,
          superId: pSuper,
          depth: nodes[pSuper].depth + 1,
          board: wb.clone(),
          key: wk,
          action: matchAct,
          shortLabel: Rules.shortActionLabel(matchAct, wb),
          isGoal: Rules.winnerOf(wb) == 0,
          isOppLoss: Rules.winnerOf(wb) == 1,
        );
        nodes.add(tn);
        nodes[pSuper].subIds.add(nid);
        keyToId[wk] = nid;
        pSuper = nid;
      }
    }

    // BFS expansion to show branching, cycles (↺), dead ends (×), and opponent refutations (∀×).
    List<int> q = [for (int i = 0; i < nodes.length; i++) i];
    int qi = 0;
    while (qi < q.length && nodes.length < maxNodes) {
      int uid = q[qi++];
      TreeNode u = nodes[uid];
      if (u.depth >= maxDepthCap || u.isGoal || u.isOppLoss || u.trimmedKind != null) continue;
      List<TreeAction> acts = Rules.enumerateLegalActions(u.board, switches);
      if (acts.isEmpty) {
        u.trimmedKind = (switches.two || switches.alt) && u.board.turn == 1 ? null : 'dead';
        continue;
      }
      int branchCap = u.depth == 0 ? 5 : (u.depth <= 2 ? 3 : 2);
      int added = 0;
      for (final TreeAction act in acts) {
        if (added >= branchCap || nodes.length >= maxNodes) break;
        GridBoard nb = Rules.applyAction(u.board, switches, act);
        String nk = nb.boardKey(switches);
        if (u.subIds.any((sid) => nodes[sid].key == nk && nodes[sid].trimmedKind == null)) {
          added++;
          continue;
        }
        if (keyToId.containsKey(nk)) {
          // Duplicate / cycle branch (↺)
          int nid = nodes.length;
          TreeNode dup = TreeNode(
            id: nid,
            superId: uid,
            depth: u.depth + 1,
            board: nb,
            key: '$nk#dup$nid',
            action: act,
            shortLabel: Rules.shortActionLabel(act, nb),
            isGoal: false,
            isOppLoss: false,
          )..trimmedKind = 'cycle';
          nodes.add(dup);
          u.subIds.add(nid);
          added++;
          continue;
        }
        SolveResult subSol = solve(switches, nb);
        int nid = nodes.length;
        String? trim;
        if (Rules.winnerOf(nb) == 1) {
          trim = 'forall';
        } else if (subSol.dist == null && Rules.winnerOf(nb) != 0) {
          trim = (switches.two || switches.alt) ? 'forall' : 'dead';
        }
        TreeNode tn = TreeNode(
          id: nid,
          superId: uid,
          depth: u.depth + 1,
          board: nb,
          key: nk,
          action: act,
          shortLabel: Rules.shortActionLabel(act, nb),
          isGoal: Rules.winnerOf(nb) == 0,
          isOppLoss: Rules.winnerOf(nb) == 1,
        )..trimmedKind = trim;
        nodes.add(tn);
        u.subIds.add(nid);
        keyToId[nk] = nid;
        if (trim == null) q.add(nid);
        added++;
      }
    }

    for (final TreeNode n in nodes) {
      if (winPathKeys.contains(n.key) || n.isGoal) n.onWinPath = true;
    }

    List<int> bruteSeq = [];
    List<int> trimSeq = [];
    for (final TreeNode n in nodes) {
      n.bruteOrder = bruteSeq.length;
      bruteSeq.add(n.id);
      if (n.trimmedKind == null) {
        n.trimOrder = trimSeq.length;
        trimSeq.add(n.id);
      }
    }

    int activeId = keyToId[curBoard.boardKey(switches)] ?? 0;
    Set<int> activeChain = {};
    int? walk = activeId;
    while (walk != null) {
      activeChain.add(walk);
      walk = nodes[walk].superId;
    }

    int maxD = 0;
    for (final TreeNode n in nodes) {
      if (n.depth > maxD) maxD = n.depth;
    }

    return MoveTree(
      nodes: nodes,
      bruteSeq: bruteSeq,
      trimSeq: trimSeq,
      activeNodeId: activeId,
      activeChainIds: activeChain,
      maxDepth: maxD,
    );
  }
}
