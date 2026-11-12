import 'package:ladder_core/ladder_core.dart';
import 'package:test/test.dart';

void main() {
  test('all nine rungs synthesize full-grid solvable boards across 4x4, 5x5, and 6x6', () {
    for (final int n in [4, 5, 6]) {
      int minExpectedEdges = n == 4 ? 13 : (n == 5 ? 23 : 35);
      for (final RungPreset rung in rungs) {
        Puzzle p = Synthesis.synthesize(SynthRequest(switches: rung.switches, n: n, seed: 1042));
        SolveResult res = Solver.solve(rung.switches, p.board);
        expect(res.dist, isNotNull, reason: 'Rung ${rung.name} on ${n}x$n should be solvable');
        expect(res.dist!, greaterThan(0), reason: 'Rung ${rung.name} should not start already solved');
        expect(res.action, isNotNull, reason: 'Rung ${rung.name} should expose a first optimal action');

        GridBoard exp = p.board.expandAll();
        expect(
          exp.edges.length,
          greaterThanOrEqualTo(minExpectedEdges),
          reason: 'Rung ${rung.name} on ${n}x$n should scale problem size across the grid',
        );
        Set<int> cols = {};
        Set<int> rows = {};
        for (final Connector e in exp.edges) {
          var (int ux, int uy) = parseCell(e.u);
          var (int vx, int vy) = parseCell(e.v);
          cols..add(ux)..add(vx);
          rows..add(uy)..add(vy);
        }
        expect(cols.length, equals(n), reason: 'Rung ${rung.name} on ${n}x$n should span all $n columns');
        expect(rows.length, equals(n), reason: 'Rung ${rung.name} on ${n}x$n should span all $n rows');
      }
    }
  });

  test('different seeds produce genuinely non-isomorphic procedural topologies', () {
    for (final int rIdx in [0, 1, 2, 3, 4, 5, 8]) {
      RungPreset rung = rungs[rIdx];
      Set<String> invariants = {};
      for (final int seed in [1042, 2025, 3141, 4242, 7777, 9001]) {
        GridBoard exp = Synthesis.synthesize(SynthRequest(switches: rung.switches, n: 5, seed: seed)).board.expandAll();
        Map<String, int> deg = {};
        for (final Connector e in exp.edges) {
          deg[e.u] = (deg[e.u] ?? 0) + 1;
          deg[e.v] = (deg[e.v] ?? 0) + 1;
        }
        List<int> degSeq = deg.values.toList()..sort();
        invariants.add('${exp.edges.length}:${degSeq.join(",")}');
      }
      expect(
        invariants.length,
        greaterThanOrEqualTo(3),
        reason: 'Rung ${rung.name} should generate non-isomorphic graphs across seeds (not just rotations/flips)',
      );
    }
  });

  test('PSPACE shuttle requires reversing a connector twice (unsolvable under once)', () {
    Switches pspace = rungs[4].switches;
    Puzzle p = Synthesis.synthesize(SynthRequest(switches: pspace, n: 4, seed: 1042));
    SolveResult freeRes = Solver.solve(pspace, p.board);
    SolveResult onceRes = Solver.solve(pspace.copyWith(once: true), p.board);
    expect(freeRes.dist, isNotNull);
    expect(onceRes.dist, isNull);
  });

  test('P crossing bridge toggle flips winability on the same board', () {
    Switches rungP = rungs[2].switches;
    Puzzle p = Synthesis.synthesize(SynthRequest(switches: rungP, n: 4, seed: 1042));
    SolveResult withBridge = Solver.solve(rungP, p.board);
    SolveResult ordinary = Solver.solve(rungP.copyWith(cross: false), p.board);
    expect(withBridge.dist, isNotNull);
    expect(ordinary.dist, isNull);
  });

  test('connector clicks alone solve L, NP, PSPACE, and 2EXPTIME', () {
    for (final int rIdx in [0, 3, 4, 8]) {
      RungPreset rung = rungs[rIdx];
      GridBoard cur = Synthesis.synthesize(SynthRequest(switches: rung.switches, n: 4, seed: 1042)).board;
      int guard = 0;
      while (cur.winner == null && guard++ < 64) {
        SolveResult sol = Solver.solve(rung.switches, cur);
        TreeAction? act = sol.action;
        expect(act, isNotNull);
        if (cur.turn == 1) {
          cur = Rules.applyAction(cur, rung.switches, act!);
          continue;
        }
        if (act!.kind == 'unfold') {
          cur = cur.clone()..unfold(act.box!);
          continue;
        }
        Connector? e = cur.edgeOf(act.edge);
        expect(e, isNotNull);
        List<ConnectorAction> cActs = Rules.connectorActionsOf(cur, rung.switches, e!);
        expect(cActs, isNotEmpty, reason: 'Optimal connector ${e.id} must have a clickable ConnectorAction on ${rung.name}');
        ConnectorAction chosen = cActs.first;
        if (chosen.kind == 'unfold') {
          cur = cur.clone()..unfold(chosen.box!);
        } else {
          cur = Rules.applySequence(cur, rung.switches, chosen.pieceId!, chosen.seq, 0);
        }
      }
      expect(cur.winner, equals(0), reason: 'Rung ${rung.name} should reach player win via connector actions');
    }
  });

  test('MoveTree builds non-empty brute and trimmed sequences', () {
    RungPreset np = rungs[3];
    GridBoard b = Synthesis.synthesize(SynthRequest(switches: np.switches, n: 4, seed: 1042)).board;
    MoveTree tree = Solver.buildMoveTree(switches: np.switches, initialBoard: b, curBoard: b, history: const []);
    expect(tree.nodes.length, greaterThan(1));
    expect(tree.bruteSeq.length, greaterThanOrEqualTo(tree.trimSeq.length));
    expect(tree.activeNodeId, equals(0));
  });
}
