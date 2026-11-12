import 'dart:math' as math;

import 'switches.dart';

const double kGridPitch = 110.0;
const double kHalfPitch = kGridPitch / 2.0;
const double kBoxHalf = kHalfPitch + 10.0; // 65.0: 130x130 rounded square around a 2x2 sub-tile

class Vec2 {
  final double x;
  final double y;

  const Vec2(this.x, this.y);

  double distTo(Vec2 other) {
    double dx = x - other.x;
    double dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class TilePortDef {
  final String node; // 'n00', 'n10', 'n01', or 'n11'
  final double dx;
  final double dy;

  const TilePortDef({required this.node, required this.dx, required this.dy});
}

class TilePairSpec {
  final String ka;
  final String kb;
  final int w;
  final String kat;
  final String baseTail; // 'u' or 'v'

  const TilePairSpec({
    required this.ka,
    required this.kb,
    required this.w,
    required this.kat,
    required this.baseTail,
  });
}

/// Reusable 2x2 sub-grid tile definition ('A') unfolded on the top three rungs.
class TileDef {
  static const Map<String, Vec2> baseVerts = {
    'n00': Vec2(-kHalfPitch, -kHalfPitch),
    'n10': Vec2(kHalfPitch, -kHalfPitch),
    'n01': Vec2(-kHalfPitch, kHalfPitch),
    'n11': Vec2(kHalfPitch, kHalfPitch),
  };

  static const Map<String, TilePortDef> basePorts = {
    'p1': TilePortDef(node: 'n10', dx: kBoxHalf, dy: -kHalfPitch),
    'p2': TilePortDef(node: 'n11', dx: kBoxHalf, dy: kHalfPitch),
    'p3': TilePortDef(node: 'n11', dx: kHalfPitch, dy: kBoxHalf),
    'p4': TilePortDef(node: 'n01', dx: -kHalfPitch, dy: kBoxHalf),
  };

  final List<String> usedPorts;
  final List<TilePairSpec> pairs;
  final List<(String, String)> off;
  final bool spawnPieces;

  const TileDef({
    required this.usedPorts,
    required this.pairs,
    required this.off,
    this.spawnPieces = true,
  });

  static const TileDef defaultTile = TileDef(
    usedPorts: ['p1', 'p2', 'p3', 'p4'],
    pairs: [
      TilePairSpec(ka: 'n00', kb: 'n10', w: 1, kat: 'n10', baseTail: 'u'),
      TilePairSpec(ka: 'n10', kb: 'n11', w: 1, kat: 'n11', baseTail: 'u'),
      TilePairSpec(ka: 'n11', kb: 'n01', w: 2, kat: 'n11', baseTail: 'u'),
    ],
    off: [('n00', 'n01')],
  );

  TileDef clone() => TileDef(
        usedPorts: List<String>.from(usedPorts),
        pairs: List<TilePairSpec>.from(pairs),
        off: List<(String, String)>.from(off),
        spawnPieces: spawnPieces,
      );
}

/// Either an ordinary grid cell ('c00'..'c55') or a folded 2x2 tile box ('A1', 'A2').
class CellNode {
  final String id;
  final double x;
  final double y;
  final int? goal; // 0 = player ★ goal, 1 = opponent ★ goal
  final bool alt; // true = purple ∀ cell on open-centre walks
  final Map<String, List<String>>? crossExits; // orthogonal bridge exit table

  // Folded 2x2 box fields (non-null iff isBox == true):
  final String? box; // 'A' when folded, null for ordinary cells
  final int owner; // 0 or 1 for box tint
  final bool rot180;
  final int sym;
  final Map<String, String>? cellMap; // local 'n00'..'n11' -> grid cell id
  final List<String>? altMap;

  const CellNode({
    required this.id,
    required this.x,
    required this.y,
    this.goal,
    this.alt = false,
    this.crossExits,
    this.box,
    this.owner = 0,
    this.rot180 = false,
    this.sym = 0,
    this.cellMap,
    this.altMap,
  });

  bool get isBox => box != null;

  CellNode clone() => CellNode(
        id: id,
        x: x,
        y: y,
        goal: goal,
        alt: alt,
        crossExits: crossExits == null
            ? null
            : {for (final e in crossExits!.entries) e.key: List<String>.from(e.value)},
        box: box,
        owner: owner,
        rot180: rot180,
        sym: sym,
        cellMap: cellMap == null ? null : Map<String, String>.from(cellMap!),
        altMap: altMap == null ? null : List<String>.from(altMap!),
      );
}

/// Active orthogonal connector between two adjacent grid cells (or box ports).
class Connector {
  final String id;
  String u;
  String v;
  final String tail; // 'u' or 'v': arrow tail when directed == true
  String? uport;
  String? vport;

  Connector({
    required this.id,
    required this.u,
    required this.v,
    this.tail = 'u',
    this.uport,
    this.vport,
  });

  String farOf(String vid) => u == vid ? v : u;

  bool touches(String vid) => u == vid || v == vid;

  bool arrowFrom(String vid) => (tail == 'u' ? u : v) == vid;

  Connector clone() => Connector(
        id: id,
        u: u,
        v: v,
        tail: tail,
        uport: uport,
        vport: vport,
      );
}

/// Token / meeple resting either in a cell centre (`on == null`) or on a
/// connector's perimeter end (`on == connector.id`).
class Meeple {
  final String id;
  final int w; // weight 1 or 2
  final int owner; // 0 = green (player), 1 = purple (opponent)
  final int? star; // 0 = green ★ carrier, 1 = purple ★ carrier
  String at; // CellNode id
  String? on; // Connector id when at perimeter, null when in cell centre
  String? from; // Connector id by which a centre meeple entered `at`
  bool moved; // true once slid along a connector

  Meeple({
    required this.id,
    required this.w,
    required this.owner,
    this.star,
    required this.at,
    this.on,
    this.from,
    this.moved = false,
  });

  Meeple clone() => Meeple(
        id: id,
        w: w,
        owner: owner,
        star: star,
        at: at,
        on: on,
        from: from,
        moved: moved,
      );
}

// ---- Grid coordinate & symmetry helpers ----

String cellId(int c, int r) => 'c$c$r';

(int, int) parseCell(String cid) {
  return (int.parse(cid[1]), int.parse(cid[2]));
}

(int, int) canonPairInt(int a, int b) => a < b ? (a, b) : (b, a);

(String, String) canonPair(String a, String b) => a.compareTo(b) < 0 ? (a, b) : (b, a);

(int, int) transformCoord(int c, int r, int n, int sym) {
  int x = c;
  int y = r;
  if ((sym & 4) != 0) {
    int t = x;
    x = y;
    y = t;
  }
  int rot = sym & 3;
  for (int k = 0; k < rot; k++) {
    int nx = n - 1 - y;
    int ny = x;
    x = nx;
    y = ny;
  }
  return (x, y);
}

Vec2 transformVec(double dx, double dy, int sym) {
  double x = dx;
  double y = dy;
  if ((sym & 4) != 0) {
    double t = x;
    x = y;
    y = t;
  }
  int rot = sym & 3;
  for (int k = 0; k < rot; k++) {
    double nx = -y;
    double ny = x;
    x = nx;
    y = ny;
  }
  return Vec2(x, y);
}

Vec2 gadOffset(CellNode bv, double dx, double dy) {
  double lx = bv.rot180 ? -dx : dx;
  double ly = bv.rot180 ? -dy : dy;
  Vec2 tv = transformVec(lx, ly, bv.sym);
  return Vec2(bv.x + tv.x, bv.y + tv.y);
}

String gadCellId(CellNode bv, String boxId, String localKey) {
  Map<String, String>? cm = bv.cellMap;
  if (cm != null && cm.containsKey(localKey)) return cm[localKey]!;
  return '$boxId.$localKey';
}

List<(String, String)> allGridSlots(int n) {
  List<(String, String)> slots = [];
  for (int r = 0; r < n; r++) {
    for (int c = 0; c < n; c++) {
      if (c + 1 < n) slots.add((cellId(c, r), cellId(c + 1, r)));
      if (r + 1 < n) slots.add((cellId(c, r), cellId(c, r + 1)));
    }
  }
  return slots;
}

Map<String, List<String>> makeCrossExits(String cid) {
  var (int c, int r) = parseCell(cid);
  String nE = '${cellId(c, r - 1)}-$cid';
  String sE = '$cid-${cellId(c, r + 1)}';
  String wE = '${cellId(c - 1, r)}-$cid';
  String eE = '$cid-${cellId(c + 1, r)}';
  return {
    nE: [sE, nE],
    sE: [nE, sE],
    wE: [eE, wE],
    eE: [wE, eE],
  };
}

/// Complete live state of an n x n Complexity Ladder board.
class GridBoard {
  final int gridN;
  final bool isWalkBoard;
  final TileDef? tileDef;
  final Map<String, CellNode> verts;
  final List<Connector> edges;
  final List<Meeple> pieces;
  final List<(String, String)> off;

  int turn; // 0 = player (green), 1 = opponent (purple)
  int? winner; // null, 0, or 1
  bool stuck;
  String? last;
  int moves;
  final int initialCells;
  final int initialBoxes;

  GridBoard({
    required this.gridN,
    required this.isWalkBoard,
    required this.tileDef,
    required this.verts,
    required this.edges,
    required this.pieces,
    required this.off,
    this.turn = 0,
    this.winner,
    this.stuck = false,
    this.last,
    this.moves = 0,
    int? initialCells,
    int? initialBoxes,
  })  : initialCells = initialCells ?? verts.values.where((v) => !v.isBox).length,
        initialBoxes = initialBoxes ?? verts.values.where((v) => v.isBox).length;

  GridBoard clone() => GridBoard(
        gridN: gridN,
        isWalkBoard: isWalkBoard,
        tileDef: tileDef?.clone(),
        verts: {for (final e in verts.entries) e.key: e.value.clone()},
        edges: edges.map((e) => e.clone()).toList(),
        pieces: pieces.map((p) => p.clone()).toList(),
        off: List<(String, String)>.from(off),
        turn: turn,
        winner: winner,
        stuck: stuck,
        last: last,
        moves: moves,
        initialCells: initialCells,
        initialBoxes: initialBoxes,
      );

  bool isBox(String? vid) {
    if (vid == null) return false;
    CellNode? v = verts[vid];
    return v != null && v.isBox;
  }

  Connector? edgeOf(String? id) {
    if (id == null) return null;
    for (final Connector e in edges) {
      if (e.id == id) return e;
    }
    return null;
  }

  Meeple? pieceOf(String? id) {
    if (id == null) return null;
    for (final Meeple p in pieces) {
      if (p.id == id) return p;
    }
    return null;
  }

  Meeple? starMeeple([int starOwner = 0]) {
    for (final Meeple p in pieces) {
      if (p.star == starOwner) return p;
    }
    return pieceOf('m');
  }

  int get openCellCount => verts.values.where((v) => !v.isBox).length;

  int get foldedBoxCount => verts.values.where((v) => v.isBox).length;

  List<String> get sortedBoxIds {
    List<String> ids = verts.keys.where((k) => isBox(k)).toList();
    ids.sort();
    return ids;
  }

  String? ownerBoxOfHiddenPiece(String? pieceId) {
    if (pieceId == null) return null;
    int dash = pieceId.indexOf('-');
    String u = dash >= 0 ? pieceId.substring(0, dash) : pieceId;
    for (final entry in verts.entries) {
      CellNode v = entry.value;
      if (v.isBox && v.cellMap != null) {
        for (final String mapped in v.cellMap!.values) {
          if (mapped == u) return entry.key;
        }
      }
    }
    return null;
  }

  /// Unfold a 2x2 tile box ('A1' or 'A2') in place with zero coordinate jump.
  void unfold(String boxId) {
    CellNode? bv = verts[boxId];
    if (bv == null || !bv.isBox) return;
    TileDef gad = tileDef ?? TileDef.defaultTile;
    List<String> altList = bv.altMap ?? const [];

    for (final entry in TileDef.baseVerts.entries) {
      String cid = gadCellId(bv, boxId, entry.key);
      Vec2 pos = gadOffset(bv, entry.value.x, entry.value.y);
      verts[cid] = CellNode(
        id: cid,
        x: pos.x,
        y: pos.y,
        alt: altList.contains(cid),
      );
    }

    for (final (String ka, String kb) in gad.off) {
      var (String ou, String ov) = canonPair(gadCellId(bv, boxId, ka), gadCellId(bv, boxId, kb));
      off.add((ou, ov));
    }

    for (final TilePairSpec pair in gad.pairs) {
      String rawU = gadCellId(bv, boxId, pair.ka);
      String rawV = gadCellId(bv, boxId, pair.kb);
      String cat = gadCellId(bv, boxId, pair.kat);
      var (String cu, String cv) = canonPair(rawU, rawV);
      String id = '$cu-$cv';
      String tailSrc = pair.baseTail == 'v' ? rawV : rawU;
      String tail = tailSrc == cu ? 'u' : 'v';
      edges.add(Connector(id: id, u: cu, v: cv, tail: tail));
      if (gad.spawnPieces) {
        pieces.add(Meeple(id: id, w: pair.w, owner: bv.owner, at: cat, on: id));
      }
    }

    for (final Meeple p in pieces) {
      if (p.at == boxId) {
        if (p.on == null) {
          p.at = gadCellId(bv, boxId, 'n00');
          continue;
        }
        Connector? e = edgeOf(p.on);
        if (e != null) {
          String pName = (e.u == boxId ? e.uport : e.vport) ?? 'p1';
          TilePortDef pt = TileDef.basePorts[pName] ?? TileDef.basePorts['p1']!;
          p.at = gadCellId(bv, boxId, pt.node);
        }
      }
    }

    for (final Connector e in edges) {
      if (e.u == boxId) {
        TilePortDef pt = TileDef.basePorts[e.uport ?? 'p1'] ?? TileDef.basePorts['p1']!;
        e.u = gadCellId(bv, boxId, pt.node);
        e.uport = null;
      }
      if (e.v == boxId) {
        TilePortDef pt = TileDef.basePorts[e.vport ?? 'p1'] ?? TileDef.basePorts['p1']!;
        e.v = gadCellId(bv, boxId, pt.node);
        e.vport = null;
      }
    }

    verts.remove(boxId);
  }

  GridBoard expandAll() {
    GridBoard copy = clone();
    int guard = 0;
    while (guard++ < 20) {
      List<String> boxes = copy.sortedBoxIds;
      if (boxes.isEmpty) break;
      copy.unfold(boxes.first);
    }
    return copy;
  }

  bool isWalkRegime(Switches s) {
    return isWalkBoard && s.open && s.thr == 0 && !s.two && !s.once;
  }

  Map<String, List<String>>? activeExitTable(String vid, Switches s) {
    if (!s.cross) return null;
    CellNode? v = verts[vid];
    return v?.crossExits;
  }

  /// Canonical state key for Combinatorial Move Tree deduplication & cycle trimming.
  String boardKey(Switches s) {
    String boxes = sortedBoxIds.join(',');
    if (isWalkRegime(s)) {
      Meeple? m = starMeeple(0);
      bool hasExits = m != null && activeExitTable(m.at, s) != null;
      return 'O|$boxes|$turn|${m?.at ?? ''}|${m?.on ?? ''}|${hasExits ? (m.from ?? '') : ''}';
    }
    List<Meeple> sorted = List<Meeple>.from(pieces)..sort((a, b) => a.id.compareTo(b.id));
    String ps = sorted.map((p) {
      String mv = s.once && p.moved ? '1' : '0';
      return '${p.id}:${p.at}:${p.on ?? '-'}:$mv';
    }).join(';');
    return 'C|$boxes|$turn|$ps';
  }

  /// Full topology + state signature so `[↻ new]` guarantees a distinct puzzle.
  String topologySig(Switches s) {
    List<String> es = edges.map((e) => '${e.id}:${e.tail}').toList()..sort();
    List<String> gs = verts.entries
        .where((e) => e.value.goal != null)
        .map((e) => '${e.key}:${e.value.goal}')
        .toList()
      ..sort();
    List<String> alts = verts.entries.where((e) => e.value.alt).map((e) => e.key).toList()..sort();
    List<String> crs = verts.entries.where((e) => e.value.crossExits != null).map((e) => e.key).toList()..sort();
    return '${boardKey(s)}||${es.join(',')}|${gs.join(',')}|${alts.join(',')}|${crs.join(',')}';
  }
}
