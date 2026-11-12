import 'dart:ui' show PointerDeviceKind;

import 'package:complexity_ladder/board_geometry.dart';
import 'package:complexity_ladder/board_widget.dart';
import 'package:complexity_ladder/game_screen.dart';
import 'package:complexity_ladder/game_state.dart';
import 'package:complexity_ladder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ladder_core/ladder_core.dart';

void main() {
  testWidgets('Complexity Ladder boots on PSPACE and renders controls', (WidgetTester tester) async {
    await tester.pumpWidget(const ComplexityLadderApp());
    await tester.pump();

    expect(find.textContaining('Complexity Ladder'), findsOneWidget);
    expect(find.text('PSPACE-complete'), findsWidgets);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('hint'), findsOneWidget);
    expect(find.text('Green'), findsOneWidget);
    expect(find.text('Purple'), findsOneWidget);
    // Solver mode bar & three-view tabs are omitted (always manual Grid view)
    expect(find.text('Solver:'), findsNothing);
    expect(find.text('Tree T_C'), findsNothing);
    expect(find.text('Both'), findsNothing);
  });

  testWidgets('two-tap hint advances board state cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const ComplexityLadderApp());
    await tester.pump();

    await tester.tap(find.text('hint'));
    await tester.pump();
    expect(find.text('make it'), findsOneWidget);

    await tester.tap(find.text('make it'));
    await tester.pump();
    expect(find.textContaining('1 move'), findsOneWidget);
    expect(rungs.length, equals(9));
  });

  testWidgets('walk-regime meeple is centered in its cell node', (WidgetTester tester) async {
    GameState game = GameState()..setRung(rungs[0]); // L
    addTearDown(game.dispose);

    GridBoard board = game.board!;
    Meeple star = board.starMeeple(0)!;
    CellNode node = board.verts[star.at]!;
    Vec2 seat = BoardGeometry.seatOf(board, star);
    expect(seat.x, equals(node.x));
    expect(seat.y, equals(node.y));

    BoardGeometry geom = BoardGeometry(
      canvasWidth: 411.0,
      canvasHeight: 540.0,
      gridN: 4,
      showTileLegend: false,
    );
    expect(geom.scaleX, greaterThan(1.0));
    expect(geom.scaleY, greaterThan(geom.scaleX));
  });

  testWidgets('player color toggle and win shimmer pulse work for green and purple', (WidgetTester tester) async {
    GameState game = GameState()..setRung(rungs[0]); // L
    addTearDown(game.dispose);

    await tester.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await tester.pump();

    expect(game.playAsPurple, isFalse);
    await tester.tap(find.text('Purple'));
    await tester.pump();
    expect(game.playAsPurple, isTrue);
    expect(game.youColor(false), equals(GameState.kPurpleLight));
    expect(game.oppColor(false), equals(GameState.kGreenLight));

    // Walk optimal hints all the way to goal and verify coupled-perimeter slide + win shimmer pulse
    expect(game.usePerimeterWalk, isTrue);
    expect(find.textContaining('Threshold E−1'), findsOneWidget);
    int guard = 0;
    while (!game.solved && guard++ < 50) {
      game.hintStep();
      game.hintStep();
      await tester.pump();
    }
    expect(game.solved, isTrue);
    expect(game.walkTransition, isNotNull);
    expect(game.winPulseEpoch, greaterThan(0));

    // Pump partway through perimeter slide + victory shimmer pulse and to completion
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.textContaining('SOLVED'), findsOneWidget);

    // Verify drawer toggle switches cleanly to classic center-walk view and back
    game.reset();
    await tester.pump();
    game.setWalkPerimeterView(false);
    await tester.pump();
    expect(game.usePerimeterWalk, isFalse);
    expect(find.textContaining('open centres'), findsOneWidget);
  });

  testWidgets('desktop mouse clicks with jitter on connectors advance and never snap back',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1320, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    GameState game = GameState()..rebuild(); // Starts on PSPACE
    addTearDown(game.dispose);

    await tester.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await tester.pump();

    Finder boardFinder = find.byType(BoardWidget);
    Rect boardRect = tester.getRect(boardFinder);
    GridBoard b0 = game.board!;
    BoardGeometry geom = BoardGeometry(
      canvasWidth: boardRect.width,
      canvasHeight: boardRect.height,
      gridN: b0.gridN,
      showTileLegend: game.switches.coded || b0.initialBoxes > 0,
    );

    // Find a legal connector action on PSPACE
    Connector? legalConn;
    ConnectorAction? act;
    for (final Connector e in b0.edges) {
      List<ConnectorAction> acts = Rules.connectorActionsOf(b0, game.switches, e);
      if (acts.isNotEmpty && acts.first.pieceId != null && acts.first.from != acts.first.to) {
        legalConn = e;
        act = acts.first;
        break;
      }
    }
    expect(legalConn, isNotNull);
    expect(act, isNotNull);

    // Click at 44% along connector (origin half) with 7px mouse jitter (exceeds 2px pan slop!)
    EndAnchor srcA = BoardGeometry.endOf(b0, legalConn!, act!.from);
    EndAnchor dstA = BoardGeometry.endOf(b0, legalConn, act.to);
    Offset clickLocal = geom.toScreen(
      srcA.x + (dstA.x - srcA.x) * 0.44,
      srcA.y + (dstA.y - srcA.y) * 0.44,
    );
    Offset clickGlobal = boardRect.topLeft + clickLocal;

    TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: clickGlobal);
    await mouse.down(clickGlobal);
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.moveBy(const Offset(5.0, 5.0)); // ~7.07px jitter > 2px mouse pan slop & old 5px threshold
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.up();
    await tester.pump();

    expect(game.moves, equals(1));
    expect(game.pieceSlide, isNotNull);
    expect(game.board!.pieceOf(act.pieceId!)!.at, equals(act.to));

    // Pump well past animation duration and verify it stays at destination node
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.board!.pieceOf(act.pieceId!)!.at, equals(act.to));

    // Also verify coupled-perimeter walk rung (L) with mouse click jitter directly on token
    game.setRung(rungs[0]); // L
    await tester.pump();
    boardRect = tester.getRect(boardFinder);
    GridBoard bWalk = game.board!;
    Meeple star0 = bWalk.starMeeple(0)!;
    Connector walkConn = Rules.exitsFrom(bWalk, game.switches, star0.at, star0.from).first;
    String expectedDest = walkConn.farOf(star0.at);
    BoardGeometry geomWalk = BoardGeometry(
      canvasWidth: boardRect.width,
      canvasHeight: boardRect.height,
      gridN: bWalk.gridN,
      showTileLegend: false,
    );
    Vec2 tokBoardPt = BoardGeometry.perimPos(bWalk, star0.at, walkConn);
    Offset tokGlobal = boardRect.topLeft + geomWalk.toScreen(tokBoardPt.x, tokBoardPt.y);

    await mouse.down(tokGlobal);
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.moveBy(const Offset(-6.0, 4.0)); // ~7.2px mouse click jitter
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.up();
    await tester.pump();

    expect(game.moves, equals(1));
    expect(game.walkTransition, isNotNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.board!.starMeeple(0)!.at, equals(expectedDest));

    // Verify on NP/PSPACE that the winning ★ slides all the way into the Goal socket center
    game.setRung(rungs[3]); // NP-complete
    await tester.pump();
    int guard = 0;
    while (!game.solved && guard++ < 50) {
      game.hintStep();
      game.hintStep();
      await tester.pump();
    }
    expect(game.solved, isTrue);
    expect(game.pieceSlide, isNotNull);
    GridBoard solvedNp = game.board!;
    Meeple wonStar = solvedNp.starMeeple(0)!;
    CellNode goalNode = solvedNp.verts[wonStar.at]!;
    Vec2 finalSeat = BoardGeometry.seatOf(solvedNp, wonStar);
    expect(finalSeat.x, equals(goalNode.x));
    expect(finalSeat.y, equals(goalNode.y));
    await tester.pump(const Duration(milliseconds: 1800));
  });
}
