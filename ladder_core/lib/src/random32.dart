/// Deterministic 32-bit Mulberry32 generator so seeds produce identical
/// puzzles across machines and platforms.
class Random32 {
  int _state;

  Random32(int seed) : _state = seed & 0xFFFFFFFF;

  static int _imul32(int a, int b) {
    int ah = (a >> 16) & 0xFFFF;
    int al = a & 0xFFFF;
    int bh = (b >> 16) & 0xFFFF;
    int bl = b & 0xFFFF;
    return ((al * bl) + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  /// Next uniform double in [0, 1).
  double nextDouble() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _imul32(_state ^ ((_state & 0xFFFFFFFF) >> 15), 1 | _state);
    t = (t + _imul32(t ^ ((t & 0xFFFFFFFF) >> 7), 61 | t)) ^ t;
    t &= 0xFFFFFFFF;
    int out = (t ^ (t >> 14)) & 0xFFFFFFFF;
    return out / 4294967296.0;
  }

  /// Uniform integer in [lo, hi] inclusive.
  int nextIntRange(int lo, int hi) {
    if (hi <= lo) return lo;
    return lo + (nextDouble() * (hi - lo + 1)).floor();
  }

  bool nextBool([double probTrue = 0.5]) => nextDouble() < probTrue;

  T choice<T>(List<T> items) {
    return items[(nextDouble() * items.length).floor()];
  }

  List<T> shuffled<T>(List<T> items) {
    List<T> out = List<T>.from(items);
    for (int i = out.length - 1; i > 0; i--) {
      int j = (nextDouble() * (i + 1)).floor();
      T tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }
}
