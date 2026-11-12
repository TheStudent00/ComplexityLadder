import 'package:ladder_core/ladder_core.dart';

void main() {
  for (final int n in [4, 5, 6]) {
    print('=== Grid ${n}x$n ===');
    for (final RungPreset rung in rungs) {
      Stopwatch sw = Stopwatch()..start();
      Puzzle p = Synthesis.synthesize(SynthRequest(switches: rung.switches, n: n, seed: 1042));
      SolveResult s = Solver.solve(rung.switches, p.board);
      sw.stop();
      print(
        '${rung.name.padRight(10)} | dist=${'${s.dist ?? '-'}'.padLeft(2)} ${s.unit.padRight(10)} '
        '| |V_C|=${'${s.visited}'.padLeft(5)} | ${sw.elapsedMilliseconds} ms',
      );
    }
  }
}
