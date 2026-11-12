import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ladder_core/ladder_core.dart';

import 'board_geometry.dart';
import 'board_painter.dart';
import 'game_state.dart';

/// Interactive Complexity Ladder grid canvas:
/// - Hovering or pressing a legal connector lights up a player-colored glow + preview arrow
/// - Tapping/clicking a legal connector immediately executes its directional move
/// - Tapping a folded 2x2 tile box unfolds it in place
/// - Dragging a meeple constrains it along its legal connector paths
/// - Reaching the win condition sweeps a shimmer pulse across the graph, coloring it
class BoardWidget extends StatefulWidget {
  final GameState game;

  const BoardWidget({super.key, required this.game});

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> with TickerProviderStateMixin {
  static const double _kClickJitterMaxPx = 20.0;

  late final AnimationController _winAnim;
  late final AnimationController _walkAnim;
  late Listenable _mergedRepaint;
  int _seenWinEpoch = 0;
  int _seenWalkEpoch = 0;
  bool _pendingWinPulse = false;

  String? _pressedConnectorId;
  String? _pressedBoxId;
  Offset? _panDownLocal;
  Offset? _panLastLocal;
  double _panMaxDist = 0.0;

  @override
  void initState() {
    super.initState();
    _winAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    );
    _walkAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onWalkAnimTick);
    _mergedRepaint = Listenable.merge([widget.game, _winAnim, _walkAnim]);
    _seenWinEpoch = widget.game.winPulseEpoch;
    _seenWalkEpoch = widget.game.activeSlideEpoch;
    if (widget.game.solved) {
      _winAnim.value = 1.0;
    }
    widget.game.addListener(_onGameChanged);
  }

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeListener(_onGameChanged);
      _mergedRepaint = Listenable.merge([widget.game, _winAnim, _walkAnim]);
      _seenWinEpoch = widget.game.winPulseEpoch;
      _seenWalkEpoch = widget.game.activeSlideEpoch;
      _pendingWinPulse = false;
      _walkAnim.reset();
      if (widget.game.solved) {
        _winAnim.value = 1.0;
      } else {
        _winAnim.reset();
      }
      widget.game.addListener(_onGameChanged);
    }
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGameChanged);
    _walkAnim.removeListener(_onWalkAnimTick);
    _walkAnim.dispose();
    _winAnim.dispose();
    super.dispose();
  }

  void _onWalkAnimTick() {
    if (_pendingWinPulse && _walkAnim.value >= 0.82) {
      _pendingWinPulse = false;
      if (widget.game.solved) {
        _winAnim.forward(from: 0.0);
      }
    }
  }

  void _onGameChanged() {
    int curWalkEpoch = widget.game.activeSlideEpoch;
    bool newWalkSlide = widget.game.hasSlideTransition && curWalkEpoch != _seenWalkEpoch;
    _seenWalkEpoch = curWalkEpoch;
    if (!widget.game.hasSlideTransition && (_walkAnim.isAnimating || _walkAnim.value > 0.0)) {
      _walkAnim.reset();
    } else if (newWalkSlide) {
      _walkAnim.forward(from: 0.0);
    }

    if (!widget.game.solved) {
      _seenWinEpoch = widget.game.winPulseEpoch;
      _pendingWinPulse = false;
      if (_winAnim.isAnimating || _winAnim.value > 0.0) {
        _winAnim.reset();
      }
      return;
    }
    if (widget.game.winPulseEpoch != _seenWinEpoch) {
      _seenWinEpoch = widget.game.winPulseEpoch;
      if (newWalkSlide) {
        _pendingWinPulse = true;
        _winAnim.reset();
      } else {
        _pendingWinPulse = false;
        _winAnim.forward(from: 0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    GameState game = widget.game;
    GridBoard? board = game.board;
    if (board == null) {
      return const Center(child: CircularProgressIndicator());
    }
    ColorScheme colors = Theme.of(context).colorScheme;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool showTileLegend = game.switches.coded || board.initialBoxes > 0;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        BoardGeometry geometry = BoardGeometry(
          canvasWidth: constraints.maxWidth,
          canvasHeight: constraints.maxHeight,
          gridN: board.gridN,
          showTileLegend: showTileLegend,
        );

        Widget painted = AnimatedBuilder(
          animation: Listenable.merge([_winAnim, _walkAnim]),
          builder: (BuildContext context, Widget? child) {
            double? winProg = (game.solved && !_pendingWinPulse) ? _winAnim.value : null;
            double? walkProg =
                (game.hasSlideTransition && _walkAnim.isAnimating) ? _walkAnim.value : null;
            return CustomPaint(
              size: geometry.canvasSize,
              painter: BoardPainter(
                game: game,
                geometry: geometry,
                colors: colors,
                isDark: isDark,
                winProgress: winProg,
                walkProgress: walkProg,
                repaintListenable: _mergedRepaint,
              ),
            );
          },
        );

        GestureDetector gestures = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => _onTapDown(d, geometry),
          onTapUp: (TapUpDetails d) => _onTapUp(d, geometry),
          onPanStart: (DragStartDetails d) => _onPanStart(d, geometry),
          onPanUpdate: (DragUpdateDetails d) => _onPanUpdate(d, geometry),
          onPanEnd: (DragEndDetails d) => _onPanEnd(geometry),
          onPanCancel: _onPanCancel,
          child: painted,
        );

        MouseRegion hoverRegion = MouseRegion(
          cursor: game.hoveredConnectorId != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onHover: (PointerHoverEvent ev) => _onHover(ev.localPosition, geometry),
          onExit: (_) => game.setHoveredConnector(null),
          child: gestures,
        );

        return SizedBox(
          width: geometry.canvasSize.width,
          height: geometry.canvasSize.height,
          child: hoverRegion,
        );
      },
    );
  }

  void _onHover(Offset local, BoardGeometry geometry) {
    GameState game = widget.game;
    GridBoard? board = game.board;
    if (board == null || !game.yourTurn || game.drag != null) {
      game.setHoveredConnector(null);
      return;
    }
    Vec2 bp = geometry.toBoard(local);
    if (game.usePerimeterWalk) {
      Connector? tokConn = geometry.hitWalkPerimeterToken(board, game.switches, bp);
      if (tokConn != null) {
        game.setHoveredConnector(tokConn.id);
        return;
      }
    }
    Connector? conn = geometry.hitLegalConnector(board, game.switches, bp);
    if (conn != null) {
      game.setHoveredConnector(conn.id);
      return;
    }
    if (!game.usePerimeterWalk) {
      Meeple? mp = geometry.hitMovableMeeple(board, game.switches, bp);
      if (mp != null && mp.on != null) {
        game.setHoveredConnector(mp.on);
        return;
      }
    }
    game.setHoveredConnector(null);
  }

  void _onTapDown(TapDownDetails d, BoardGeometry geometry) {
    _pressedConnectorId = null;
    _pressedBoxId = null;
    GameState game = widget.game;
    GridBoard? board = game.board;
    if (board == null) return;
    Vec2 bp = geometry.toBoard(d.localPosition);
    String? boxId = geometry.hitFoldedBox(board, bp);
    if (boxId != null) {
      _pressedBoxId = boxId;
      return;
    }
    if (!game.yourTurn) return;
    if (game.usePerimeterWalk) {
      Connector? tokConn = geometry.hitWalkPerimeterToken(board, game.switches, bp);
      if (tokConn != null) {
        _pressedConnectorId = tokConn.id;
        game.setHoveredConnector(tokConn.id);
        return;
      }
    }
    Connector? conn = geometry.hitLegalConnector(board, game.switches, bp);
    if (conn != null) {
      _pressedConnectorId = conn.id;
      game.setHoveredConnector(conn.id);
      return;
    }
    if (!game.usePerimeterWalk) {
      Meeple? mp = geometry.hitMovableMeeple(board, game.switches, bp);
      if (mp != null && mp.on != null) {
        _pressedConnectorId = mp.on;
        game.setHoveredConnector(mp.on);
      }
    }
  }

  void _onTapUp(TapUpDetails d, BoardGeometry geometry) {
    GameState game = widget.game;
    GridBoard? board = game.board;
    String? fallbackConn = _pressedConnectorId;
    String? fallbackBox = _pressedBoxId;
    _pressedConnectorId = null;
    _pressedBoxId = null;
    if (board == null) return;
    Vec2 bp = geometry.toBoard(d.localPosition);
    // 1. Folded 2x2 tile box tap
    String? boxId = geometry.hitFoldedBox(board, bp) ?? fallbackBox;
    if (boxId != null) {
      game.openBox(boxId);
      return;
    }
    // 2. Coupled-perimeter walk token tap (L / NL / P)
    if (game.usePerimeterWalk) {
      Connector? tokConn = geometry.hitWalkPerimeterToken(board, game.switches, bp);
      if (tokConn != null && game.tapConnector(tokConn.id, clickBoardPt: bp)) {
        return;
      }
    }
    // 3. Direct connector click/tap (works across all 9 rungs!)
    Connector? conn = geometry.hitLegalConnector(board, game.switches, bp);
    if (conn != null && game.tapConnector(conn.id, clickBoardPt: bp)) {
      return;
    }
    if (fallbackConn != null && game.tapConnector(fallbackConn, clickBoardPt: bp)) {
      return;
    }
    // 4. Movable meeple tap fallback
    if (!game.usePerimeterWalk) {
      Meeple? mp = geometry.hitMovableMeeple(board, game.switches, bp);
      if (mp != null) {
        if (mp.on != null && game.tapConnector(mp.on!, clickBoardPt: bp)) return;
        List<DragLine> lines = BoardGeometry.buildDragLines(board, game.switches, mp);
        List<DragLine> cross = lines.where((l) => l.crosses).toList();
        if (cross.length == 1) {
          game.commitPlayerSequence(mp.id, cross.first.seq);
          return;
        }
      }
    }
    game.setHoveredConnector(null);
  }

  void _onPanStart(DragStartDetails d, BoardGeometry geometry) {
    _panDownLocal = d.localPosition;
    _panLastLocal = d.localPosition;
    _panMaxDist = 0.0;
    _pressedConnectorId = null;
    _pressedBoxId = null;

    GameState game = widget.game;
    GridBoard? board = game.board;
    if (board == null) return;
    Vec2 bp = geometry.toBoard(d.localPosition);

    String? boxId = geometry.hitFoldedBox(board, bp);
    if (boxId != null) {
      _pressedBoxId = boxId;
      return;
    }
    if (!game.yourTurn) return;

    if (game.usePerimeterWalk) {
      Meeple? star = board.starMeeple(0);
      Connector? tokConn =
          geometry.hitWalkPerimeterToken(board, game.switches, bp, forDrag: true);
      if (star != null && tokConn != null) {
        _pressedConnectorId = tokConn.id;
        DragLine line = BoardGeometry.buildWalkPerimeterDragLine(board, star, tokConn);
        game.beginMeepleDrag(
          pieceId: star.id,
          lines: [line],
          startSeat: line.stops.first,
          screenX: d.localPosition.dx,
          screenY: d.localPosition.dy,
          pressedConnectorId: tokConn.id,
        );
        return;
      }
      Connector? conn = geometry.hitLegalConnector(board, game.switches, bp);
      if (conn != null) {
        _pressedConnectorId = conn.id;
        game.setHoveredConnector(conn.id);
      }
      return;
    }

    Meeple? mp = geometry.hitMovableMeeple(board, game.switches, bp, forDrag: true);
    if (mp != null) {
      StepMove? unf =
          Rules.movesOf(board, game.switches, mp).where((m) => m.kind == 'unfold').firstOrNull;
      if (unf != null && unf.box != null) {
        _pressedBoxId = unf.box;
        return;
      }
      List<DragLine> lines = BoardGeometry.buildDragLines(board, game.switches, mp);
      if (lines.isNotEmpty) {
        _pressedConnectorId = mp.on;
        game.beginMeepleDrag(
          pieceId: mp.id,
          lines: lines,
          startSeat: BoardGeometry.seatOf(board, mp),
          screenX: d.localPosition.dx,
          screenY: d.localPosition.dy,
          pressedConnectorId: mp.on,
        );
        return;
      }
    }
    Connector? conn = geometry.hitLegalConnector(board, game.switches, bp);
    if (conn != null) {
      _pressedConnectorId = conn.id;
      game.setHoveredConnector(conn.id);
    }
  }

  void _onPanUpdate(DragUpdateDetails d, BoardGeometry geometry) {
    _panLastLocal = d.localPosition;
    if (_panDownLocal != null) {
      _panMaxDist = math.max(_panMaxDist, (d.localPosition - _panDownLocal!).distance);
    }
    GameState game = widget.game;
    if (game.drag != null) {
      Vec2 bp = geometry.toBoard(d.localPosition);
      game.updateMeepleDrag(bp, d.localPosition.dx, d.localPosition.dy);
    } else if (_pressedConnectorId != null && _panMaxDist <= _kClickJitterMaxPx) {
      game.setHoveredConnector(_pressedConnectorId);
    } else {
      _onHover(d.localPosition, geometry);
    }
  }

  void _onPanEnd(BoardGeometry geometry) {
    GameState game = widget.game;
    GridBoard? board = game.board;
    String? pressedConn = _pressedConnectorId;
    String? pressedBox = _pressedBoxId;
    Offset? releaseLocal = _panLastLocal ?? _panDownLocal;
    double maxDist = _panMaxDist;
    _pressedConnectorId = null;
    _pressedBoxId = null;
    _panDownLocal = null;
    _panLastLocal = null;
    _panMaxDist = 0.0;

    if (board == null) {
      game.cancelMeepleDrag();
      return;
    }
    Vec2? releaseBp = releaseLocal != null ? geometry.toBoard(releaseLocal) : null;

    if (game.drag != null) {
      game.endMeepleDrag(
        (String vid, Connector e, Vec2 pt) => BoardGeometry.alongT(board, vid, e, pt),
        clickBoardPt: releaseBp,
      );
      return;
    }
    if (pressedBox != null && maxDist <= _kClickJitterMaxPx) {
      game.openBox(pressedBox);
      return;
    }
    if (pressedConn != null && maxDist <= _kClickJitterMaxPx) {
      game.tapConnector(pressedConn, clickBoardPt: releaseBp);
      return;
    }
    if (releaseBp != null) {
      Connector? releaseConn = geometry.hitLegalConnector(board, game.switches, releaseBp);
      if (releaseConn != null && (pressedConn == null || releaseConn.id == pressedConn)) {
        game.tapConnector(releaseConn.id, clickBoardPt: releaseBp);
        return;
      }
    }
    game.setHoveredConnector(null);
  }

  void _onPanCancel() {
    _pressedConnectorId = null;
    _pressedBoxId = null;
    _panDownLocal = null;
    _panLastLocal = null;
    _panMaxDist = 0.0;
    widget.game.cancelMeepleDrag();
  }
}
