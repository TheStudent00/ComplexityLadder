import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:ladder_core/ladder_core.dart';

/// Active path-constrained meeple drag state in board coordinates.
class MeepleDragState {
  static const double kClickSlopPx = 16.0;

  final String pieceId;
  final List<DragLine> lines;
  final Vec2 startSeat;
  final double startScreenX;
  final double startScreenY;
  final String? pressedConnectorId;
  bool moved = false;
  Vec2 curPos;
  DragHold? held;

  MeepleDragState({
    required this.pieceId,
    required this.lines,
    required this.startSeat,
    required this.startScreenX,
    required this.startScreenY,
    this.pressedConnectorId,
  }) : curPos = startSeat;
}

class DragLine {
  final List<Vec2> stops;
  final List<StepMove> seq;
  final String? edgeId;
  final bool crosses;

  const DragLine({
    required this.stops,
    required this.seq,
    required this.edgeId,
    required this.crosses,
  });
}

class DragHold {
  final int lineIdx;
  final Vec2 pt;
  final double dist;
  final int segIdx;
  final double segU;
  final double arcLen;

  const DragHold({
    required this.lineIdx,
    required this.pt,
    required this.dist,
    required this.segIdx,
    required this.segU,
    required this.arcLen,
  });
}

/// Animated coupled-perimeter token transition on walk rungs (`L`, `NL`, `P`).
class WalkTransition {
  final int epoch;
  final String fromNode;
  final String toNode;
  final String edgeId;
  final Vec2? startPosOverride;

  const WalkTransition({
    required this.epoch,
    required this.fromNode,
    required this.toNode,
    required this.edgeId,
    this.startPosOverride,
  });
}

/// Animated single-piece slide transition across a connector on standard rungs.
class PieceSlideTransition {
  final int epoch;
  final String pieceId;
  final String fromNode;
  final String? fromEdgeId;
  final String edgeId;
  final Vec2? startPosOverride;

  const PieceSlideTransition({
    required this.epoch,
    required this.pieceId,
    required this.fromNode,
    required this.fromEdgeId,
    required this.edgeId,
    this.startPosOverride,
  });
}

/// Complete reactive controller for the Complexity Ladder app.
class GameState extends ChangeNotifier {
  Switches switches = rungs[4].switches; // Start on PSPACE
  int gridN = 4; // 4, 5, or 6
  int seed = 1042;

  GridBoard? initialBoard;
  GridBoard? board;
  List<GridBoard> history = [];
  List<GridBoard> redoStack = [];
  List<String> log = [];

  SolveResult? solve;
  MoveTree? moveTree;
  TreeAction? hint;

  String solverMode = 'manual'; // 'manual', 'trim', 'brute'
  int stepIdx = 0;
  Timer? _playTimer;
  Timer? _oppTimer;
  bool replying = false;

  String treeViewMode = 'fan'; // 'fan', 'window', 'rows', 'ring'
  bool treeZoom = true;
  String narrowPane = 'board'; // 'board', 'tree', 'split'

  String? hoveredConnectorId;
  MeepleDragState? drag;

  bool playAsPurple = false;
  bool walkPerimeterView = true;
  int winPulseEpoch = 0;
  int _walkTransEpoch = 0;
  WalkTransition? walkTransition;
  PieceSlideTransition? pieceSlide;

  int get activeSlideEpoch => walkTransition?.epoch ?? pieceSlide?.epoch ?? 0;
  bool get hasSlideTransition => walkTransition != null || pieceSlide != null;

  void _clearSlideTransitions() {
    walkTransition = null;
    pieceSlide = null;
  }

  static const Color kGreenLight = Color(0xFF1A7F5A);
  static const Color kGreenDark = Color(0xFF4FD1A5);
  static const Color kPurpleLight = Color(0xFF7A2890);
  static const Color kPurpleDark = Color(0xFFC58AF9);

  Color youColor(bool isDark) {
    if (playAsPurple) return isDark ? kPurpleDark : kPurpleLight;
    return isDark ? kGreenDark : kGreenLight;
  }

  Color oppColor(bool isDark) {
    if (playAsPurple) return isDark ? kGreenDark : kGreenLight;
    return isDark ? kPurpleDark : kPurpleLight;
  }

  String get yourColorName => playAsPurple ? 'purple' : 'green';
  String get oppColorName => playAsPurple ? 'green' : 'purple';

  void setPlayAsPurple(bool value) {
    if (playAsPurple == value) return;
    playAsPurple = value;
    if (solved) {
      winPulseEpoch += 1;
    }
    notifyListeners();
  }

  bool get usePerimeterWalk =>
      walkPerimeterView && board != null && board!.isWalkRegime(switches);

  void setWalkPerimeterView(bool value) {
    if (walkPerimeterView == value) return;
    walkPerimeterView = value;
    drag = null;
    hoveredConnectorId = null;
    _clearSlideTransitions();
    notifyListeners();
  }

  void _recordWalkTransition(
    GridBoard prevBoard,
    GridBoard nextBoard, {
    String? pieceIdHint,
    String? edgeHint,
    Vec2? startPosOverride,
  }) {
    if (walkPerimeterView && prevBoard.isWalkRegime(switches)) {
      pieceSlide = null;
      Meeple? p0 = prevBoard.starMeeple(0);
      Meeple? p1 = nextBoard.starMeeple(0);
      if (p0 == null ||
          p1 == null ||
          p0.at == p1.at ||
          prevBoard.isBox(p0.at) ||
          nextBoard.isBox(p1.at)) {
        walkTransition = null;
        return;
      }
      String? eid = edgeHint ?? p1.from;
      if (eid == null) {
        for (final Connector e in nextBoard.edges) {
          if ((e.u == p0.at && e.v == p1.at) || (e.v == p0.at && e.u == p1.at)) {
            eid = e.id;
            break;
          }
        }
      }
      if (eid == null) {
        walkTransition = null;
        return;
      }
      _walkTransEpoch += 1;
      walkTransition = WalkTransition(
        epoch: _walkTransEpoch,
        fromNode: p0.at,
        toNode: p1.at,
        edgeId: eid,
        startPosOverride: startPosOverride,
      );
      return;
    }

    walkTransition = null;
    Meeple? movedNext = pieceIdHint != null ? nextBoard.pieceOf(pieceIdHint) : null;
    if (movedNext == null) {
      for (final Meeple p1 in nextBoard.pieces) {
        Meeple? p0 = prevBoard.pieceOf(p1.id);
        if (p0 != null && p0.at != p1.at) {
          movedNext = p1;
          break;
        }
      }
    }
    Meeple? movedPrev = movedNext != null ? prevBoard.pieceOf(movedNext.id) : null;
    if (movedPrev == null ||
        movedNext == null ||
        movedPrev.at == movedNext.at ||
        prevBoard.isBox(movedPrev.at) ||
        nextBoard.isBox(movedNext.at)) {
      pieceSlide = null;
      return;
    }
    String? eid = edgeHint ?? movedNext.on ?? movedNext.from ?? movedPrev.on;
    if (eid == null) {
      for (final Connector e in nextBoard.edges) {
        if ((e.u == movedPrev.at && e.v == movedNext.at) ||
            (e.v == movedPrev.at && e.u == movedNext.at)) {
          eid = e.id;
          break;
        }
      }
    }
    if (eid == null) {
      pieceSlide = null;
      return;
    }
    _walkTransEpoch += 1;
    pieceSlide = PieceSlideTransition(
      epoch: _walkTransEpoch,
      pieceId: movedNext.id,
      fromNode: movedPrev.at,
      fromEdgeId: movedPrev.on ?? eid,
      edgeId: eid,
      startPosOverride: startPosOverride,
    );
  }

  void _checkWinPulse(int? prevWinner) {
    if (prevWinner != 0 && board?.winner == 0) {
      winPulseEpoch += 1;
    }
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _playTimer?.cancel();
    _playTimer = null;
    _oppTimer?.cancel();
    _oppTimer = null;
    replying = false;
  }

  bool get isPlayingSolver => _playTimer != null;

  Verdict get verdict => verdictOf(switches);

  RungPreset? get rung => rungOf(switches);

  int get moves => board?.moves ?? 0;

  bool get solved => board?.winner == 0;

  bool get lost => board?.winner == 1;

  bool get yourTurn =>
      !replying &&
      board != null &&
      board!.turn == 0 &&
      board!.winner == null &&
      !board!.stuck;

  // ---- Synthesis & Solver Refresh ----

  void rebuild() {
    _stopTimers();
    hoveredConnectorId = null;
    drag = null;
    hint = null;
    _clearSlideTransitions();
    solverMode = 'manual';
    stepIdx = 0;

    Puzzle puzzle = Synthesis.synthesize(
      SynthRequest(switches: switches, n: gridN, seed: seed),
    );
    initialBoard = puzzle.board.clone();
    board = puzzle.board.clone();
    history = [];
    redoStack = [];
    log = puzzle.log;
    _refreshAnalysis();
    notifyListeners();
  }

  void _refreshAnalysis() {
    GridBoard? cur = board;
    if (cur == null) return;
    solve = Solver.solve(switches, cur);
    moveTree = null;
  }

  // ---- Rungs, Switches & Parameters ----

  void setRung(RungPreset target) {
    if (switches == target.switches && board != null) return;
    switches = target.switches;
    rebuild();
  }

  /// Flip one switch. Pure rule switches (`thr`, `directed`, `once`, `alt`,
  /// `cross`) re-evaluate the current board in place so the counterfactual
  /// rule change is immediately visible; structural switches synthesize a
  /// fresh puzzle for the new regime.
  void setSwitches(Switches next) {
    if (next == switches) return;
    bool sameStructure = next.sameStructureAs(switches);
    switches = next;
    if (sameStructure && board != null && initialBoard != null) {
      _stopTimers();
      hint = null;
      _clearSlideTransitions();
      solverMode = 'manual';
      stepIdx = 0;
      GridBoard b = board!;
      int? prevWinner = b.winner;
      b.winner = Rules.winnerOf(b);
      _checkWinPulse(prevWinner);
      if (b.winner == null) {
        if (!switches.two && !switches.alt) b.turn = 0;
        b.stuck = b.turn == 0 && !Rules.hasAnyMove(b, switches, 0);
      }
      _refreshAnalysis();
      notifyListeners();
      if (b.turn == 1 && b.winner == null) {
        _scheduleOpponentTurn();
      }
    } else {
      rebuild();
    }
  }

  void setGridN(int nextN) {
    int clamped = nextN.clamp(4, 6);
    if (clamped == gridN) return;
    gridN = clamped;
    rebuild();
  }

  void setSeed(int nextSeed) {
    seed = nextSeed.abs() % 1000000;
    rebuild();
  }

  void rollNewSeed() {
    String prevSig = initialBoard?.topologySig(switches) ?? '';
    int candidate = (seed + 137) % 100000;
    if (candidate < 100) candidate += 100;
    for (int i = 0; i < 16; i++) {
      Puzzle p = Synthesis.synthesize(
        SynthRequest(switches: switches, n: gridN, seed: candidate),
      );
      if (p.board.topologySig(switches) != prevSig) break;
      candidate = (candidate + 293 + i * 31) % 100000;
    }
    seed = candidate;
    rebuild();
  }

  void setNarrowPane(String pane) {
    if (narrowPane == pane) return;
    narrowPane = pane;
    notifyListeners();
  }

  void setTreeViewMode(String mode) {
    if (treeViewMode == mode) return;
    treeViewMode = mode;
    notifyListeners();
  }

  void toggleTreeZoom() {
    treeZoom = !treeZoom;
    notifyListeners();
  }

  // ---- Hover & Direct Connector Click Play ----

  void setHoveredConnector(String? edgeId) {
    if (hoveredConnectorId == edgeId) return;
    hoveredConnectorId = edgeId;
    notifyListeners();
  }

  bool tapConnector(String edgeId, {Vec2? clickBoardPt}) {
    GridBoard? b = board;
    if (!yourTurn || b == null) return false;
    Connector? e = b.edgeOf(edgeId);
    if (e == null) return false;
    List<ConnectorAction> acts = Rules.connectorActionsOf(b, switches, e);
    if (acts.isEmpty) return false;

    ConnectorAction chosen = acts.first;
    bool matchedHint = false;
    if (hint != null) {
      for (final ConnectorAction a in acts) {
        if (a.kind == 'unfold' && hint!.kind == 'unfold' && a.box == hint!.box) {
          chosen = a;
          matchedHint = true;
          break;
        }
        if (a.pieceId == hint!.pieceId && a.to == hint!.to) {
          chosen = a;
          matchedHint = true;
          break;
        }
      }
    }
    if (!matchedHint && acts.length > 1 && clickBoardPt != null) {
      double bestD = double.infinity;
      for (final ConnectorAction a in acts) {
        CellNode? fn = b.verts[a.from];
        if (fn == null) continue;
        double d = Vec2(fn.x, fn.y).distTo(clickBoardPt);
        if (d < bestD) {
          bestD = d;
          chosen = a;
        }
      }
    }

    if (chosen.kind == 'unfold' && chosen.box != null) {
      openBox(chosen.box!);
    } else if (chosen.pieceId != null && chosen.seq.isNotEmpty) {
      commitPlayerSequence(chosen.pieceId!, chosen.seq);
    }
    return true;
  }

  void openBox(String boxId) {
    GridBoard? b = board;
    if (replying || b == null || b.winner != null || !b.isBox(boxId)) return;
    stopSolverPlay();
    solverMode = 'manual';
    hoveredConnectorId = null;
    _clearSlideTransitions();
    history.add(b.clone());
    redoStack = [];
    GridBoard next = b.clone()
      ..unfold(boxId)
      ..last = 'opened box $boxId';
    board = next;
    hint = null;
    _refreshAnalysis();
    notifyListeners();
  }

  void commitPlayerSequence(String pieceId, List<StepMove> seq, {Vec2? dragReleasePt}) {
    GridBoard? b = board;
    if (!yourTurn || b == null || seq.isEmpty) return;
    stopSolverPlay();
    solverMode = 'manual';
    hoveredConnectorId = null;
    GridBoard prev = b.clone();
    history.add(prev);
    redoStack = [];
    int? prevWinner = b.winner;
    GridBoard next = Rules.applySequence(b, switches, pieceId, seq, 0);
    String? slideEdge = seq.where((m) => m.kind == 'slide').map((m) => m.edge).firstOrNull;
    _recordWalkTransition(
      prev,
      next,
      pieceIdHint: pieceId,
      edgeHint: slideEdge,
      startPosOverride: dragReleasePt,
    );
    board = next;
    _checkWinPulse(prevWinner);
    hint = null;
    _refreshAnalysis();
    notifyListeners();
    if (next.turn == 1 && next.winner == null) {
      _scheduleOpponentTurn();
    }
  }

  void _scheduleOpponentTurn() {
    _oppTimer?.cancel();
    replying = true;
    notifyListeners();
    int delayMs = switches.two ? 380 : (usePerimeterWalk ? 460 : 300);
    _oppTimer = Timer(Duration(milliseconds: delayMs), _executeOpponentTurn);
  }

  void _executeOpponentTurn() {
    replying = false;
    GridBoard? b = board;
    if (b == null || b.turn != 1 || b.winner != null) {
      notifyListeners();
      return;
    }
    SolveResult sol = Solver.solve(switches, b);
    TreeAction? act = sol.action;
    int? prevWinner = b.winner;
    GridBoard prev = b.clone();
    history.add(prev);
    if (act == null) {
      _clearSlideTransitions();
      GridBoard next = b.clone()
        ..turn = 0
        ..stuck = !Rules.hasAnyMove(b, switches, 0);
      board = next;
    } else {
      GridBoard next = Rules.applyAction(b, switches, act);
      _recordWalkTransition(prev, next, pieceIdHint: act.pieceId, edgeHint: act.edge);
      board = next;
    }
    _checkWinPulse(prevWinner);
    _refreshAnalysis();
    notifyListeners();
    if (board != null && board!.turn == 1 && board!.winner == null) {
      _scheduleOpponentTurn();
    }
  }

  // ---- Undo / Redo / Reset / Two-Tap Hint ----

  void undo() {
    if (replying || drag != null || history.isEmpty || board == null) return;
    stopSolverPlay();
    solverMode = 'manual';
    _clearSlideTransitions();
    redoStack.add(board!.clone());
    board = history.removeLast();
    while ((switches.two || switches.alt) && board!.turn == 1 && history.isNotEmpty) {
      redoStack.add(board!.clone());
      board = history.removeLast();
    }
    hint = null;
    hoveredConnectorId = null;
    _refreshAnalysis();
    notifyListeners();
  }

  void redo() {
    if (replying || drag != null || redoStack.isEmpty || board == null) return;
    stopSolverPlay();
    solverMode = 'manual';
    _clearSlideTransitions();
    int? prevWinner = board!.winner;
    history.add(board!.clone());
    board = redoStack.removeLast();
    while ((switches.two || switches.alt) && board!.turn == 1 && redoStack.isNotEmpty) {
      history.add(board!.clone());
      board = redoStack.removeLast();
    }
    _checkWinPulse(prevWinner);
    hint = null;
    hoveredConnectorId = null;
    _refreshAnalysis();
    notifyListeners();
  }

  void reset() {
    if (replying || drag != null || initialBoard == null) return;
    stopSolverPlay();
    solverMode = 'manual';
    _clearSlideTransitions();
    board = initialBoard!.clone();
    history = [];
    redoStack = [];
    hint = null;
    hoveredConnectorId = null;
    stepIdx = 0;
    _refreshAnalysis();
    notifyListeners();
  }

  /// First tap highlights the optimal connector/box; second tap executes it.
  void hintStep() {
    GridBoard? b = board;
    if (!yourTurn || b == null) return;
    TreeAction? act = solve?.action;
    if (act == null) return;
    if (act.matchesHint(hint)) {
      if (act.kind == 'unfold' && act.box != null) {
        openBox(act.box!);
      } else {
        stopSolverPlay();
        solverMode = 'manual';
        int? prevWinner = b.winner;
        GridBoard prev = b.clone();
        history.add(prev);
        redoStack = [];
        GridBoard next = Rules.applyAction(b, switches, act);
        _recordWalkTransition(prev, next, pieceIdHint: act.pieceId, edgeHint: act.edge);
        board = next;
        _checkWinPulse(prevWinner);
        hint = null;
        _refreshAnalysis();
        notifyListeners();
        if (board!.turn == 1 && board!.winner == null) {
          _scheduleOpponentTurn();
        }
      }
    } else {
      hint = act;
      notifyListeners();
    }
  }

  // ---- Solver Mode (`manual` / `trim` / `brute`) & Tree Jump ----

  List<int> _activeSolverSeq() {
    MoveTree? t = moveTree;
    if (t == null) return const [];
    return solverMode == 'trim' ? t.trimSeq : t.bruteSeq;
  }

  void setSolverMode(String mode) {
    stopSolverPlay();
    solverMode = mode;
    stepIdx = 0;
    if (mode != 'manual' && initialBoard != null) {
      board = initialBoard!.clone();
      history = [];
      redoStack = [];
      hint = null;
      _refreshAnalysis();
    }
    notifyListeners();
  }

  void stepSolverTrace() {
    if (solverMode == 'manual') setSolverMode('trim');
    MoveTree? t = moveTree;
    List<int> seq = _activeSolverSeq();
    if (t == null || seq.isEmpty) return;
    if (stepIdx + 1 < seq.length) {
      stepIdx += 1;
    } else {
      stopSolverPlay();
    }
    int nid = seq[stepIdx.clamp(0, seq.length - 1)];
    _jumpToTreeNodeInternal(t, nid, keepSolverMode: true);
    notifyListeners();
  }

  void toggleSolverPlay() {
    if (_playTimer != null) {
      stopSolverPlay();
      notifyListeners();
      return;
    }
    if (solverMode == 'manual') {
      setSolverMode('trim');
    }
    List<int> seq = _activeSolverSeq();
    if (seq.isNotEmpty && stepIdx >= seq.length - 1) {
      stepIdx = 0;
      if (initialBoard != null) {
        board = initialBoard!.clone();
        history = [];
      }
    }
    _playTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
      List<int> curSeq = _activeSolverSeq();
      if (curSeq.isEmpty || stepIdx >= curSeq.length - 1) {
        stopSolverPlay();
        notifyListeners();
        return;
      }
      stepSolverTrace();
    });
    notifyListeners();
  }

  void stopSolverPlay() {
    _playTimer?.cancel();
    _playTimer = null;
  }

  void jumpToTreeNode(int nodeId) {
    MoveTree? t = moveTree;
    if (t == null || nodeId < 0 || nodeId >= t.nodes.length) return;
    stopSolverPlay();
    solverMode = 'manual';
    _jumpToTreeNodeInternal(t, nodeId, keepSolverMode: false);
    _refreshAnalysis();
    notifyListeners();
  }

  void _jumpToTreeNodeInternal(MoveTree t, int nodeId, {required bool keepSolverMode}) {
    TreeNode target = t.nodes[nodeId];
    if (target.trimmedKind == 'cycle') return;
    List<GridBoard> chain = [];
    int? cur = nodeId;
    while (cur != null) {
      chain.add(t.nodes[cur].board.clone());
      cur = t.nodes[cur].superId;
    }
    chain = chain.reversed.toList();
    int? prevWinner = board?.winner;
    if (board != null && chain.isNotEmpty) {
      _recordWalkTransition(board!, chain.last);
    } else {
      _clearSlideTransitions();
    }
    board = chain.last.clone();
    _checkWinPulse(prevWinner);
    history = chain.length > 1 ? chain.sublist(0, chain.length - 1) : [];
    redoStack = [];
    hint = null;
  }

  // ---- Path-Constrained Meeple Drag ----

  void beginMeepleDrag({
    required String pieceId,
    required List<DragLine> lines,
    required Vec2 startSeat,
    required double screenX,
    required double screenY,
    String? pressedConnectorId,
  }) {
    if (!yourTurn || lines.isEmpty) return;
    drag = MeepleDragState(
      pieceId: pieceId,
      lines: lines,
      startSeat: startSeat,
      startScreenX: screenX,
      startScreenY: screenY,
      pressedConnectorId: pressedConnectorId,
    );
    if (pressedConnectorId != null) {
      hoveredConnectorId = pressedConnectorId;
    }
    notifyListeners();
  }

  void updateMeepleDrag(Vec2 boardPt, double screenX, double screenY) {
    MeepleDragState? d = drag;
    if (d == null) return;
    double screenDist = math.sqrt(
      math.pow(screenX - d.startScreenX, 2) + math.pow(screenY - d.startScreenY, 2),
    );
    if (screenDist > MeepleDragState.kClickSlopPx) {
      d.moved = true;
    }
    if (!d.moved) {
      return;
    }
    DragHold? best;
    for (int i = 0; i < d.lines.length; i++) {
      if (d.held != null && d.held!.arcLen > 14.0 && d.held!.lineIdx != i) continue;
      DragHold? h = _nearestOnLine(d.lines[i], i, boardPt);
      if (h != null && (best == null || h.dist < best.dist)) best = h;
    }
    d.held = best;
    d.curPos = best?.pt ?? d.startSeat;
    if (best != null) {
      hoveredConnectorId = d.lines[best.lineIdx].edgeId;
    }
    notifyListeners();
  }

  void cancelMeepleDrag() {
    if (drag == null && hoveredConnectorId == null) return;
    drag = null;
    hoveredConnectorId = null;
    notifyListeners();
  }

  void endMeepleDrag(
    double Function(String vid, Connector e, Vec2 pt) alongT, {
    Vec2? clickBoardPt,
  }) {
    MeepleDragState? d = drag;
    drag = null;
    hoveredConnectorId = null;
    GridBoard? b = board;
    if (d == null || b == null || !yourTurn) {
      notifyListeners();
      return;
    }
    Meeple? p = b.pieceOf(d.pieceId);
    if (p == null) {
      notifyListeners();
      return;
    }
    List<StepMove> mvs = Rules.movesOf(b, switches, p);
    StepMove? slide = mvs.where((m) => m.kind == 'slide').firstOrNull;
    StepMove? inn = mvs.where((m) => m.kind == 'in').firstOrNull;

    if (!d.moved) {
      if (d.pressedConnectorId != null &&
          tapConnector(d.pressedConnectorId!, clickBoardPt: clickBoardPt)) {
        return;
      }
      if (slide != null) {
        DragLine? full = d.lines.where((l) => l.crosses && l.edgeId == slide.edge).firstOrNull;
        commitPlayerSequence(p.id, full != null ? full.seq : [slide]);
      } else if (p.on == null) {
        List<DragLine> crossLines = d.lines.where((l) => l.crosses).toList();
        if (crossLines.length == 1) {
          commitPlayerSequence(p.id, crossLines.first.seq);
        } else {
          notifyListeners();
        }
      } else if (inn != null) {
        commitPlayerSequence(p.id, [inn]);
      } else {
        notifyListeners();
      }
      return;
    }

    DragHold? held = d.held;
    if (held == null || held.arcLen < 3.0) {
      notifyListeners();
      return;
    }
    DragLine line = d.lines[held.lineIdx];
    if (line.crosses && line.edgeId != null) {
      Connector? e = b.edgeOf(line.edgeId);
      double progress =
          line.stops.length == 2 ? held.segU : (e != null ? alongT(p.at, e, held.pt) : 0.0);
      if (e != null && progress >= 0.28) {
        commitPlayerSequence(p.id, line.seq, dragReleasePt: held.pt);
        return;
      }
    }
    if (p.on == null && !line.crosses && held.segU > 0.4) {
      commitPlayerSequence(p.id, line.seq);
      return;
    }
    if (p.on != null && inn != null && !line.crosses && held.segU > 0.4) {
      commitPlayerSequence(p.id, [inn]);
      return;
    }
    notifyListeners();
  }

  static DragHold? _nearestOnLine(DragLine line, int lineIdx, Vec2 q) {
    DragHold? best;
    double runLen = 0.0;
    for (int k = 0; k < line.stops.length - 1; k++) {
      Vec2 a = line.stops[k];
      Vec2 b = line.stops[k + 1];
      double dx = b.x - a.x;
      double dy = b.y - a.y;
      double len = math.sqrt(dx * dx + dy * dy);
      double l2 = len * len == 0 ? 1.0 : len * len;
      double u = (((q.x - a.x) * dx + (q.y - a.y) * dy) / l2).clamp(0.0, 1.0);
      Vec2 pt = Vec2(a.x + dx * u, a.y + dy * u);
      double dist = q.distTo(pt);
      if (best == null || dist < best.dist) {
        best = DragHold(
          lineIdx: lineIdx,
          pt: pt,
          dist: dist,
          segIdx: k,
          segU: u,
          arcLen: runLen + len * u,
        );
      }
      runLen += len;
    }
    return best;
  }

  // ---- Status Text ----

  String statusText() {
    GridBoard? b = board;
    if (b == null) return 'Synthesizing puzzle…';
    String mText = '$moves move${moves == 1 ? '' : 's'}';
    if (b.winner == 0) return '$mText · ★ reached goal! Tap new for another puzzle.';
    if (b.winner == 1) return '$mText · $oppColorName reached ★ first — undo or reset.';
    if (replying) return '$mText · $oppColorName opponent choosing…';
    if (b.stuck) return '$mText · no legal move remaining — undo or reset.';

    SolveResult? s = solve;
    if (s == null) return mText;
    String states = '|V_C| = ${s.visited}';
    if (s.dist != null) {
      String kind = (switches.two || switches.alt) ? 'forced win in' : 'shortest win:';
      return '$mText · $kind ${s.dist} ${s.unit} ($states)';
    }
    return '$mText · ${(switches.two || switches.alt) ? 'no forced win' : 'unsolvable'} from here ($states)';
  }
}
