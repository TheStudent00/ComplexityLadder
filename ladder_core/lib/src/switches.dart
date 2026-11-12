/// The eight physics switches of the Complexity Ladder.
///
/// Every level runs the same n x n orthogonal grid physics; lower levels only
/// restrict or enable switches on the same board rules.
class Switches {
  final int thr; // 0 or 2: inflow weight required to stay behind at a cell
  final bool open; // true = centres open (walk), false = centres closed (perimeter slides)
  final bool directed; // false = two-way connectors, true = one-way arrows
  final bool two; // false = one player, true = alternating green & purple turns
  final bool once; // false = free slides, true = each connector slides at most once
  final bool alt; // true = purple picks exit at universal (forall) cells on open walks
  final bool coded; // true = 2x2 sub-grids start folded as boxes of tile A
  final bool cross; // true = crossing cells keep orthogonal bridge exit tables

  const Switches({
    this.thr = 2,
    this.open = false,
    this.directed = false,
    this.two = false,
    this.once = false,
    this.alt = false,
    this.coded = false,
    this.cross = true,
  });

  Switches copyWith({
    int? thr,
    bool? open,
    bool? directed,
    bool? two,
    bool? once,
    bool? alt,
    bool? coded,
    bool? cross,
  }) {
    return Switches(
      thr: thr ?? this.thr,
      open: open ?? this.open,
      directed: directed ?? this.directed,
      two: two ?? this.two,
      once: once ?? this.once,
      alt: alt ?? this.alt,
      coded: coded ?? this.coded,
      cross: cross ?? this.cross,
    );
  }

  /// Compact 8-part signature for caching and equality.
  String get sig => '$thr|$open|$directed|$two|$once|$alt|$coded|$cross';

  /// Compact 8-character switch code for the lattice panel.
  String get code =>
      '${thr == 2 ? 'T' : 't'}'
      '${open ? 'O' : 'o'}'
      '${directed ? 'D' : 'd'}'
      '${two ? 'P' : 'p'}'
      '${once ? '1' : '*'}'
      '${alt ? 'A' : 'a'}'
      '${coded ? 'F' : 'f'}'
      '${cross ? 'X' : 'x'}';

  String get summaryLine {
    List<String> parts = [
      'threshold $thr',
      'centres ${open ? 'open' : 'closed'}',
      directed ? '1-way' : '2-way',
      two ? '2 players' : '1 player',
      once ? 'each once' : 'free slides',
      alt ? '∀ on' : '∀ off',
      coded ? '2×2 tiles folded' : '2×2 tiles open',
      'crossings ${cross ? 'bridge' : 'ordinary cell'}',
    ];
    return parts.join(' · ');
  }

  /// Structural switches change which pieces/boxes exist on a synthesized board;
  /// pure rule switches (`thr`, `directed`, `once`, `alt`, `cross`) can also be
  /// toggled in place on an active position to inspect counterfactual effects.
  bool sameStructureAs(Switches other) {
    return open == other.open && two == other.two && coded == other.coded;
  }

  @override
  bool operator ==(Object other) => other is Switches && other.sig == sig;

  @override
  int get hashCode => sig.hashCode;
}

/// Complexity class readout and proof status for any switch vector.
class Verdict {
  final String className;
  final String colLabel;
  final bool completeOnGrid;
  final String spaceBound;
  final String timeBound;
  final String ruleTitle;
  final String proofStatus;

  const Verdict({
    required this.className,
    required this.colLabel,
    required this.completeOnGrid,
    required this.spaceBound,
    required this.timeBound,
    required this.ruleTitle,
    required this.proofStatus,
  });
}

/// Named rung preset on the nine-rung Complexity Ladder (L -> 2EXPTIME).
class RungPreset {
  final int index;
  final String name;
  final String cls;
  final String colLabel;
  final Switches switches;
  final bool completeOnGrid;
  final String spaceBound;
  final String timeBound;
  final String ruleTitle;
  final String proofStatus;

  const RungPreset({
    required this.index,
    required this.name,
    required this.cls,
    required this.colLabel,
    required this.switches,
    required this.completeOnGrid,
    required this.spaceBound,
    required this.timeBound,
    required this.ruleTitle,
    required this.proofStatus,
  });

  Verdict toVerdict() => Verdict(
        className: cls,
        colLabel: colLabel,
        completeOnGrid: completeOnGrid,
        spaceBound: spaceBound,
        timeBound: timeBound,
        ruleTitle: ruleTitle,
        proofStatus: proofStatus,
      );
}

const List<RungPreset> rungs = [
  RungPreset(
    index: 0,
    name: 'L',
    cls: 'L',
    colLabel: 'L',
    switches: Switches(thr: 0, open: true, once: false, two: false, directed: false, alt: false, coded: false, cross: true),
    completeOnGrid: false,
    spaceBound: 'O(log n) space',
    timeBound: 'poly(n) time',
    ruleTitle: 'Threshold 0 · open centres · 2-way grid connectors (walk ★ to ★)',
    proofStatus: 'Membership in L on grids with symmetric grouped exit tables (Reingold 2005); L-hardness not claimed.',
  ),
  RungPreset(
    index: 1,
    name: 'NL',
    cls: 'NL-complete',
    colLabel: 'NL-complete',
    switches: Switches(thr: 0, open: true, once: false, two: false, directed: true, alt: false, coded: false, cross: true),
    completeOnGrid: true,
    spaceBound: 'O(log n) NSPACE',
    timeBound: 'O(n + m) time',
    ruleTitle: 'Threshold 0 · open centres · 1-way grid connectors · crossing bridges',
    proofStatus: 'NL-complete on 2D grids with crossing cells: directed s–t reachability (Jones 1975).',
  ),
  RungPreset(
    index: 2,
    name: 'P',
    cls: 'P-complete',
    colLabel: 'P-complete',
    switches: Switches(thr: 0, open: true, once: false, two: false, directed: true, alt: true, coded: false, cross: true),
    completeOnGrid: true,
    spaceBound: 'poly(n) space',
    timeBound: 'poly(n) time',
    ruleTitle: 'Threshold 0 · open centres · 1-way · opponent picks exit at ∀',
    proofStatus: 'P-complete on 2D grids with crossing cells: alternating reachability (Immerman 1981; CKS 1981).',
  ),
  RungPreset(
    index: 3,
    name: 'NP',
    cls: 'NP-complete',
    colLabel: 'NP-complete',
    switches: Switches(thr: 2, open: false, once: true, two: false, directed: false, alt: false, coded: false, cross: true),
    completeOnGrid: true,
    spaceBound: 'poly(n) witness',
    timeBound: 'NP (bounded)',
    ruleTitle: 'Threshold 2 · closed centres · 1 player · each meeple slides once',
    proofStatus: 'NP-complete on planar 2D grids: bounded 1-player constraint logic (Hearn & Demaine 2009).',
  ),
  RungPreset(
    index: 4,
    name: 'PSPACE',
    cls: 'PSPACE-complete',
    colLabel: 'PSPACE-complete',
    switches: Switches(thr: 2, open: false, once: false, two: false, directed: false, alt: false, coded: false, cross: true),
    completeOnGrid: true,
    spaceBound: 'poly(n) space',
    timeBound: 'exp(n) time',
    ruleTitle: 'Threshold 2 · closed centres · 1 player · meeples slide freely',
    proofStatus: 'PSPACE-complete on planar 2D grids: unbounded 1-player constraint logic (Hearn & Demaine 2009).',
  ),
  RungPreset(
    index: 5,
    name: 'EXPTIME',
    cls: 'EXPTIME-complete',
    colLabel: 'EXPTIME-complete',
    switches: Switches(thr: 2, open: false, once: false, two: true, directed: false, alt: false, coded: false, cross: true),
    completeOnGrid: false,
    spaceBound: 'poly(n) pos',
    timeBound: 'exp(n) alt',
    ruleTitle: 'Threshold 2 · closed centres · 2 players (green & purple alternate)',
    proofStatus: 'EXPTIME-complete for planar 2-player constraint logic (Hearn & Demaine 2009; grid wire-turn tempo caveat open).',
  ),
  RungPreset(
    index: 6,
    name: 'NEXPTIME',
    cls: 'NEXPTIME-complete ·',
    colLabel: 'NEXPTIME ·',
    switches: Switches(thr: 2, open: false, once: true, two: false, directed: false, alt: false, coded: true, cross: true),
    completeOnGrid: false,
    spaceBound: 'exp(n) unfolded',
    timeBound: 'NEXPTIME',
    ruleTitle: 'Threshold 2 · closed · each once · 2×2 grid tiles handed folded',
    proofStatus: 'Membership in NEXPTIME; succinct NCL projection check (Lengauer & Wagner 1992) and multi-wire tile ports not written.',
  ),
  RungPreset(
    index: 7,
    name: 'EXPSPACE',
    cls: 'EXPSPACE-complete ·',
    colLabel: 'EXPSPACE ·',
    switches: Switches(thr: 2, open: false, once: false, two: false, directed: false, alt: false, coded: true, cross: true),
    completeOnGrid: false,
    spaceBound: 'exp(n) space',
    timeBound: '2-exp(n) time',
    ruleTitle: 'Threshold 2 · closed · free slides · 2×2 grid tiles handed folded',
    proofStatus: 'Membership in EXPSPACE; succinct NCL projection check (Lengauer & Wagner 1992) and multi-wire tile ports not written.',
  ),
  RungPreset(
    index: 8,
    name: '2EXPTIME',
    cls: '2EXPTIME-complete ·',
    colLabel: '2EXPTIME ·',
    switches: Switches(thr: 2, open: false, once: false, two: true, directed: false, alt: false, coded: true, cross: true),
    completeOnGrid: false,
    spaceBound: 'exp(n) pos',
    timeBound: '2-exp(n) alt',
    ruleTitle: 'Threshold 2 · closed · 2 players · 2×2 grid tiles handed folded',
    proofStatus: 'Membership in 2EXPTIME; succinct 2-player NCL lift and multi-wire tile ports not written down.',
  ),
];

RungPreset? rungOf(Switches s) {
  for (final RungPreset r in rungs) {
    if (r.switches == s) return r;
  }
  return null;
}

RungPreset? baseRungIgnoringCross(Switches s) {
  Switches withCross = s.copyWith(cross: true);
  return rungOf(withCross);
}

Verdict verdictOf(Switches s) {
  RungPreset? exact = rungOf(s);
  if (exact != null) return exact.toVerdict();

  RungPreset? base = baseRungIgnoringCross(s);
  if (base != null && !s.cross) {
    return Verdict(
      className: '${base.name} · crossings off',
      colLabel: base.colLabel,
      completeOnGrid: false,
      spaceBound: base.spaceBound,
      timeBound: base.timeBound,
      ruleTitle: '${base.ruleTitle} · crossings ordinary',
      proofStatus: 'Crossing bridge tables turned off: N–S and W–E wires merge at crossing cells.',
    );
  }

  // Classify arbitrary custom switch combinations across the lattice.
  if (s.open && s.thr == 0 && !s.two) {
    if (s.coded) {
      String lifted = s.alt ? 'EXPTIME ·' : 'PSPACE ·';
      return Verdict(
        className: lifted,
        colLabel: lifted,
        completeOnGrid: false,
        spaceBound: 'exp(n) unfolded',
        timeBound: lifted,
        ruleTitle: 'Custom folded walk: open centres · 2×2 tiles folded',
        proofStatus: 'Succinct open-centre reachability lifts logspace/P walk regimes one exponential up (Papadimitriou & Yannakakis 1986).',
      );
    }
    String walkCls = s.alt ? 'P' : (s.directed ? 'NL' : 'L');
    return Verdict(
      className: '$walkCls (custom)',
      colLabel: walkCls,
      completeOnGrid: false,
      spaceBound: s.alt ? 'poly(n) space' : 'O(log n) space',
      timeBound: 'poly(n) time',
      ruleTitle: 'Custom open-centre walk (${s.summaryLine})',
      proofStatus: 'Open-centre walk under custom switch combination.',
    );
  }

  if (!s.open && s.two && s.once) {
    String cls = s.coded ? 'EXPSPACE ·' : 'PSPACE ·';
    return Verdict(
      className: cls,
      colLabel: cls,
      completeOnGrid: false,
      spaceBound: s.coded ? 'exp(n) unfolded' : 'poly(n) horizon',
      timeBound: cls,
      ruleTitle: 'Two players · each meeple once${s.coded ? ' · 2×2 folded' : ''}',
      proofStatus: 'Bounded-move two-player constraint logic sits in alternating polynomial time = PSPACE (or EXPSPACE when folded).',
    );
  }

  return Verdict(
    className: 'custom settings',
    colLabel: 'custom',
    completeOnGrid: false,
    spaceBound: s.coded ? 'exp(n) unfolded' : 'poly(n) state',
    timeBound: 'custom',
    ruleTitle: 'Custom: thr ${s.thr} · ${s.open ? 'open' : 'closed'} · ${s.two ? '2p' : '1p'} · ${s.once ? 'once' : 'free'}${s.directed ? ' · 1-way' : ''}',
    proofStatus: 'Custom switch combination — the same orthogonal grid physics, connector tap, and drag gesture apply.',
  );
}
