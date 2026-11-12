import 'board.dart';
import 'switches.dart';

/// Atomic meeple step on the grid:
/// - `out`: step from cell centre onto an incident connector's perimeter
/// - `slide`: slide along `edge` to `to`
/// - `in`: step from connector perimeter into cell centre
/// - `unfold`: open a folded 2x2 tile box (`box`)
class StepMove {
  final String kind; // 'out', 'slide', 'in', 'unfold'
  final String? edge;
  final String? to;
  final String? box;

  const StepMove.out(String edgeId)
      : kind = 'out',
        edge = edgeId,
        to = null,
        box = null;

  const StepMove.slide(String edgeId, String toCell)
      : kind = 'slide',
        edge = edgeId,
        to = toCell,
        box = null;

  const StepMove.enter()
      : kind = 'in',
        edge = null,
        to = null,
        box = null;

  const StepMove.unfold(String boxId)
      : kind = 'unfold',
        edge = null,
        to = null,
        box = boxId;
}

/// High-level action triggered by tapping/clicking a connector directly.
class ConnectorAction {
  final String kind; // 'run' or 'unfold'
  final String connectorId;
  final String? pieceId;
  final String? box;
  final List<StepMove> seq;
  final String from;
  final String to;

  const ConnectorAction({
    required this.kind,
    required this.connectorId,
    this.pieceId,
    this.box,
    this.seq = const [],
    required this.from,
    required this.to,
  });
}

/// Macro action in the Combinatorial Move Tree T_C and solver trace.
class TreeAction {
  final String kind; // 'walk', 'slide', 'unfold', 'pass'
  final String? pieceId;
  final String? edge;
  final String? to;
  final String? box;
  final int by; // 0 = player, 1 = opponent
  final bool autoExpand;

  const TreeAction({
    required this.kind,
    this.pieceId,
    this.edge,
    this.to,
    this.box,
    required this.by,
    this.autoExpand = false,
  });

  bool matchesHint(TreeAction? other) {
    if (other == null || kind != other.kind) return false;
    if (kind == 'unfold') return box == other.box;
    return pieceId == other.pieceId && edge == other.edge && to == other.to;
  }
}

class Rules {
  static int thresholdOf(GridBoard st, Switches s, String vid) {
    CellNode? v = st.verts[vid];
    return (v != null && v.goal != null) ? 0 : s.thr;
  }

  static int haveAt(GridBoard st, String vid) {
    int sum = 0;
    for (final Meeple p in st.pieces) {
      if (p.at == vid) sum += p.w;
    }
    return sum;
  }

  static List<Connector> exitsFrom(GridBoard st, Switches s, String vid, String? fromEdge) {
    CellNode? v = st.verts[vid];
    if (v == null || v.isBox) return const [];
    Map<String, List<String>>? tab = st.activeExitTable(vid, s);
    List<String>? allow = (tab != null && fromEdge != null) ? tab[fromEdge] : null;
    List<Connector> out = [];
    for (final Connector e in st.edges) {
      if (!e.touches(vid)) continue;
      if (s.directed && !e.arrowFrom(vid)) continue;
      if (allow != null && !allow.contains(e.id)) continue;
      out.add(e);
    }
    return out;
  }

  static bool isAltCell(GridBoard st, Switches s, String vid) {
    if (!s.alt) return false;
    CellNode? v = st.verts[vid];
    return v != null && v.alt;
  }

  static List<StepMove> movesOf(GridBoard st, Switches s, Meeple p) {
    if (st.isBox(p.at)) return [StepMove.unfold(p.at)];
    List<StepMove> out = [];
    if (p.on != null) {
      Connector? e = st.edgeOf(p.on);
      if (e != null) {
        String far = e.farOf(p.at);
        if ((!s.once || !p.moved) && (!s.directed || e.arrowFrom(p.at))) {
          if (st.isBox(far)) {
            out.add(StepMove.unfold(far));
          } else if (haveAt(st, p.at) - p.w >= thresholdOf(st, s, p.at)) {
            out.add(StepMove.slide(e.id, far));
          }
        }
      }
      if (s.open) out.add(const StepMove.enter());
    } else if (s.open) {
      for (final Connector e in exitsFrom(st, s, p.at, p.from)) {
        out.add(StepMove.out(e.id));
      }
    }
    return out;
  }

  static List<StepMove> realMoves(GridBoard st, Switches s, Meeple p) {
    return movesOf(st, s, p).where((m) => m.kind != 'unfold').toList();
  }

  static bool canRelease(GridBoard st, Switches s, String vid, int owner) {
    for (final Meeple p in st.pieces) {
      if (p.at == vid && p.owner == owner && realMoves(st, s, p).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static void applyStep(Meeple p, StepMove mv) {
    if (mv.kind == 'slide') {
      p.at = mv.to!;
      p.moved = true;
    } else if (mv.kind == 'in') {
      p.from = p.on;
      p.on = null;
    } else if (mv.kind == 'out') {
      p.on = mv.edge;
      p.from = null;
    }
  }

  static int? winnerOf(GridBoard st) {
    for (final Meeple p in st.pieces) {
      if (p.star == null) continue;
      CellNode? v = st.verts[p.at];
      if (v != null && v.goal == p.star) return p.star;
    }
    return null;
  }

  static bool hasAnyMove(GridBoard st, Switches s, int owner) {
    GridBoard exp = st.expandAll();
    for (final Meeple p in exp.pieces) {
      if (p.owner == owner && realMoves(exp, s, p).isNotEmpty) return true;
    }
    return false;
  }

  /// Legal one-click/one-tap actions available directly on connector `e` for the player.
  static List<ConnectorAction> connectorActionsOf(GridBoard st, Switches s, Connector e) {
    if (st.turn != 0 || st.winner != null || st.stuck) return const [];
    List<ConnectorAction> out = [];
    for (final Meeple p in st.pieces) {
      if (p.owner != 0) continue;
      List<StepMove> mvs = movesOf(st, s, p);
      if (mvs.isEmpty) continue;
      if (p.on == e.id) {
        StepMove? unf = mvs.where((m) => m.kind == 'unfold').firstOrNull;
        if (unf != null) {
          out.add(ConnectorAction(
            kind: 'unfold',
            connectorId: e.id,
            pieceId: p.id,
            box: unf.box,
            from: p.at,
            to: unf.box!,
          ));
          continue;
        }
        StepMove? sl = mvs.where((m) => m.kind == 'slide' && m.edge == e.id).firstOrNull;
        if (sl != null) {
          List<StepMove> seq = s.open ? [sl, const StepMove.enter()] : [sl];
          out.add(ConnectorAction(
            kind: 'run',
            connectorId: e.id,
            pieceId: p.id,
            seq: seq,
            from: p.at,
            to: sl.to!,
          ));
        } else {
          StepMove? inn = mvs.where((m) => m.kind == 'in').firstOrNull;
          if (inn != null) {
            out.add(ConnectorAction(
              kind: 'run',
              connectorId: e.id,
              pieceId: p.id,
              seq: [inn],
              from: p.at,
              to: p.at,
            ));
          }
        }
      } else if (p.on == null && s.open && e.touches(p.at)) {
        StepMove? outMv = mvs.where((m) => m.kind == 'out' && m.edge == e.id).firstOrNull;
        if (outMv == null) continue;
        String far = e.farOf(p.at);
        if (st.isBox(far)) {
          out.add(ConnectorAction(
            kind: 'unfold',
            connectorId: e.id,
            pieceId: p.id,
            box: far,
            from: p.at,
            to: far,
          ));
        } else {
          GridBoard probe = st.clone();
          Meeple pp = probe.pieceOf(p.id)!;
          applyStep(pp, outMv);
          StepMove? sl = movesOf(probe, s, pp).where((m) => m.kind == 'slide' && m.edge == e.id).firstOrNull;
          if (sl != null) {
            out.add(ConnectorAction(
              kind: 'run',
              connectorId: e.id,
              pieceId: p.id,
              seq: [outMv, sl, const StepMove.enter()],
              from: p.at,
              to: sl.to!,
            ));
          }
        }
      }
    }
    return out;
  }

  /// Apply a sequence of atomic steps on `pieceId` for `by` (0 = player, 1 = opponent).
  static GridBoard applySequence(GridBoard base, Switches s, String pieceId, List<StepMove> seq, int by) {
    GridBoard st = base.clone();
    Meeple? p = st.pieceOf(pieceId);
    if (p == null) return st;
    for (final StepMove mv in seq) {
      applyStep(p, mv);
    }
    st.last = by == 0
        ? (seq.length == 1 && seq.first.kind == 'slide' ? 'you slid a meeple' : 'you moved a meeple')
        : (s.two ? 'the opponent slid a meeple' : 'the opponent chose the connector');
    if (by == 0) st.moves += 1;
    st.winner = winnerOf(st);
    if (st.winner == null && by == 0) {
      if (s.two) {
        st.turn = 1;
      } else if (s.alt && p.star == 0 && p.on == null && isAltCell(st, s, p.at)) {
        st.turn = 1;
      } else {
        st.stuck = !hasAnyMove(st, s, 0);
      }
    } else if (st.winner == null) {
      if (s.alt && !s.two && p.star == 0 && p.on == null && isAltCell(st, s, p.at)) {
        st.turn = 1;
      } else {
        st.turn = 0;
        st.stuck = !hasAnyMove(st, s, 0);
      }
    }
    return st;
  }

  static List<TreeAction> enumerateLegalActions(GridBoard st, Switches s) {
    if (st.winner != null) return const [];
    int by = st.turn;

    if (st.isWalkRegime(s)) {
      Meeple? p = st.starMeeple(0);
      if (p == null) return const [];
      if (st.isBox(p.at)) return [TreeAction(kind: 'unfold', box: p.at, by: 0)];
      List<Connector> es;
      if (p.on != null) {
        Connector? curE = st.edgeOf(p.on);
        es = (curE != null && (!s.directed || curE.arrowFrom(p.at))) ? [curE] : const [];
      } else {
        es = exitsFrom(st, s, p.at, p.from);
      }
      List<TreeAction> actions = [];
      for (final Connector e in es) {
        String far = e.farOf(p.at);
        if (st.isBox(far)) {
          if (!actions.any((a) => a.kind == 'unfold' && a.box == far)) {
            actions.add(TreeAction(kind: 'unfold', box: far, by: by));
          }
        } else {
          actions.add(TreeAction(kind: 'walk', pieceId: p.id, edge: e.id, to: far, by: by));
        }
      }
      return actions;
    }

    if (s.two && by == 1) {
      GridBoard exp = st.expandAll();
      List<TreeAction> actions = [];
      for (final Meeple p in exp.pieces) {
        if (p.owner != 1) continue;
        for (final StepMove mv in realMoves(exp, s, p)) {
          if (mv.kind == 'slide') {
            actions.add(TreeAction(
              kind: 'slide',
              pieceId: p.id,
              edge: mv.edge,
              to: mv.to,
              by: 1,
              autoExpand: true,
            ));
          }
        }
      }
      if (actions.isEmpty && hasAnyMove(exp, s, 0)) {
        actions.add(const TreeAction(kind: 'pass', by: 1));
      }
      return actions;
    }

    List<TreeAction> actions = [];
    Set<String> seenBoxes = {};
    for (final String b in st.sortedBoxIds) {
      seenBoxes.add(b);
      actions.add(TreeAction(kind: 'unfold', box: b, by: 0));
    }
    for (final Meeple p in st.pieces) {
      if (p.owner != by) continue;
      for (final StepMove mv in movesOf(st, s, p)) {
        if (mv.kind == 'unfold') {
          if (!seenBoxes.contains(mv.box)) {
            seenBoxes.add(mv.box!);
            actions.add(TreeAction(kind: 'unfold', box: mv.box, by: by));
          }
        } else if (mv.kind == 'slide') {
          actions.add(TreeAction(kind: 'slide', pieceId: p.id, edge: mv.edge, to: mv.to, by: by));
        } else if (mv.kind == 'out' && s.open) {
          Connector? e = st.edgeOf(mv.edge);
          if (e == null) continue;
          String far = e.farOf(p.at);
          if (!st.isBox(far)) {
            GridBoard probe = st.clone();
            Meeple pp = probe.pieceOf(p.id)!;
            applyStep(pp, mv);
            StepMove? sl = movesOf(probe, s, pp).where((x) => x.kind == 'slide').firstOrNull;
            if (sl != null) {
              actions.add(TreeAction(kind: 'walk', pieceId: p.id, edge: e.id, to: far, by: by));
            }
          }
        }
      }
    }
    return actions;
  }

  static GridBoard applyAction(GridBoard baseSt, Switches s, TreeAction act) {
    GridBoard st = baseSt.clone();
    if (act.kind == 'unfold') {
      st.unfold(act.box!);
      st.last = 'opened box ${act.box}';
      return st;
    }
    if (act.kind == 'pass') {
      st.turn = 0;
      st.last = 'the opponent has no legal slide and passes';
      st.stuck = !hasAnyMove(st, s, 0);
      return st;
    }
    if (act.autoExpand) {
      int guard = 0;
      while (guard++ < 6) {
        Meeple? p0 = st.pieceOf(act.pieceId);
        if (p0 == null) {
          String? b = st.ownerBoxOfHiddenPiece(act.pieceId);
          if (b != null && st.isBox(b)) {
            st.unfold(b);
          } else {
            break;
          }
        } else {
          StepMove? u = movesOf(st, s, p0).where((m) => m.kind == 'unfold').firstOrNull;
          if (u != null) {
            st.unfold(u.box!);
          } else {
            break;
          }
        }
      }
    }
    Meeple? p = st.pieceOf(act.pieceId);
    if (p == null) return st;

    if (act.kind == 'walk') {
      if (p.on == null) applyStep(p, StepMove.out(act.edge!));
      applyStep(p, StepMove.slide(act.edge!, act.to!));
      if (s.open) applyStep(p, const StepMove.enter());
    } else if (act.kind == 'slide') {
      applyStep(p, StepMove.slide(act.edge!, act.to!));
    }

    if (act.by == 0) st.moves += 1;
    st.winner = winnerOf(st);
    if (st.winner == null && act.by == 0) {
      if (s.two) {
        st.turn = 1;
      } else if (s.alt && p.star == 0 && p.on == null && isAltCell(st, s, p.at)) {
        st.turn = 1;
      } else {
        st.stuck = !hasAnyMove(st, s, 0);
      }
    } else if (st.winner == null) {
      if (s.alt && !s.two && p.star == 0 && p.on == null && isAltCell(st, s, p.at)) {
        st.turn = 1;
      } else {
        st.turn = 0;
        st.stuck = !hasAnyMove(st, s, 0);
      }
    }
    return st;
  }

  static String shortActionLabel(TreeAction? act, GridBoard nb) {
    if (act == null) return 's₀';
    if (act.kind == 'unfold') return 'open ${act.box}';
    if (act.kind == 'pass') return 'pass';
    Meeple? p = nb.pieceOf(act.pieceId);
    String pName = p?.star == 0 ? '★' : (p?.star == 1 ? '★′' : (act.pieceId ?? ''));
    bool byOpp = act.by == 1;
    if (act.kind == 'walk') {
      return '${byOpp ? '∀' : ''}$pName→${act.to}';
    }
    Connector? ed = nb.edgeOf(act.edge);
    String fromId = (ed != null && act.to != null) ? ed.farOf(act.to!) : '';
    if (p != null && p.star != null) {
      return '$pName→${act.to}';
    }
    return '$fromId→${act.to}';
  }
}
