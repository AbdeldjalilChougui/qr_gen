/// Mode segmentation that minimises the bit stream length (ISO/IEC
/// 18004:2015, Annex J describes the trade-offs; this module finds the exact
/// optimum with dynamic programming).
library;

import 'dart:convert';

import 'mode.dart';
import 'segment.dart';

/// ECI assignment number for UTF-8.
const int utf8EciAssignment = 26;

const int _inf = 1 << 40;

// DP states: numeric with count % 3 == 1, 2, 0; alphanumeric with
// count % 2 == 1, 0; byte; kanji.
const int _n1 = 0, _n2 = 1, _n0 = 2, _a1 = 3, _a0 = 4, _b = 5, _k = 6;
const int _states = 7;

QrMode _modeOf(int state) => switch (state) {
      _n1 || _n2 || _n0 => QrMode.numeric,
      _a1 || _a0 => QrMode.alphanumeric,
      _b => QrMode.byte,
      _ => QrMode.kanji,
    };

/// Splits [text] into segments whose total bit length in [version] is as
/// small as possible.
///
/// Byte-mode characters are written as ISO-8859-1 when every such character
/// allows it. Otherwise they are written as UTF-8, preceded by an ECI
/// designator (assignment 26) unless [utf8Eci] is false. Kanji mode is used
/// for Shift JIS characters when [kanji] is true and it saves space.
List<QrSegment> segmentText(String text,
    {required int version, bool kanji = true, bool utf8Eci = true}) {
  final runes = text.runes.toList();
  if (runes.isEmpty) return [];
  final latin = _solve(runes, version, kanji: kanji, utf8: false);
  final utf = _solve(runes, version, kanji: kanji, utf8: true);
  final eciCost = utf8Eci ? 12 : 0;
  final useUtf8 = latin == null || (utf!.cost + eciCost < latin.cost);
  final plan = useUtf8 ? utf! : latin;

  final segments = <QrSegment>[
    if (useUtf8 && utf8Eci) QrSegment.eci(utf8EciAssignment),
  ];
  for (final (mode, start, end) in plan.runs) {
    final part = String.fromCharCodes(runes, start, end);
    segments.add(switch (mode) {
      QrMode.numeric => QrSegment.numeric(part),
      QrMode.alphanumeric => QrSegment.alphanumeric(part),
      QrMode.kanji => QrSegment.kanji(part),
      _ => QrSegment.bytes(
          useUtf8 ? utf8.encode(part) : runes.sublist(start, end)),
    });
  }
  return segments;
}

class _Plan {
  _Plan(this.cost, this.runs);
  final int cost;
  final List<(QrMode, int, int)> runs;
}

int _utf8Length(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
        ? 2
        : rune < 0x10000
            ? 3
            : 4;

_Plan? _solve(List<int> runes, int version,
    {required bool kanji, required bool utf8}) {
  final n = runes.length;
  final hN = 4 + QrMode.numeric.charCountBits(version);
  final hA = 4 + QrMode.alphanumeric.charCountBits(version);
  final hB = 4 + QrMode.byte.charCountBits(version);
  final hK = 4 + QrMode.kanji.charCountBits(version);

  // prev[i * _states + s]: state before character i (or -1 at the start);
  // fresh[i * _states + s]: whether character i starts a new segment.
  final prev = List<int>.filled(n * _states, -1);
  final fresh = List<bool>.filled(n * _states, false);
  var cost = List<int>.filled(_states, _inf);

  for (var i = 0; i < n; i++) {
    final r = runes[i];
    var bestPrev = -1;
    var bestCost = i == 0 ? 0 : _inf;
    if (i > 0) {
      for (var s = 0; s < _states; s++) {
        if (cost[s] < bestCost) {
          bestCost = cost[s];
          bestPrev = s;
        }
      }
    }
    final next = List<int>.filled(_states, _inf);
    final base = i * _states;
    void consider(int state, int value, int from, bool isNew) {
      if (value < next[state]) {
        next[state] = value;
        prev[base + state] = from;
        fresh[base + state] = isNew;
      }
    }

    final isDigit = r >= 0x30 && r <= 0x39;
    if (isDigit) {
      consider(_n1, bestCost + hN + 4, bestPrev, true);
      if (cost[_n0] < _inf) consider(_n1, cost[_n0] + 4, _n0, false);
      if (cost[_n1] < _inf) consider(_n2, cost[_n1] + 3, _n1, false);
      if (cost[_n2] < _inf) consider(_n0, cost[_n2] + 3, _n2, false);
    }
    if (r < 0x80 && QrSegment.alphanumericValue(r) >= 0) {
      consider(_a1, bestCost + hA + 6, bestPrev, true);
      if (cost[_a0] < _inf) consider(_a1, cost[_a0] + 6, _a0, false);
      if (cost[_a1] < _inf) consider(_a0, cost[_a1] + 5, _a1, false);
    }
    if (utf8 || r < 0x100) {
      final bits = 8 * (utf8 ? _utf8Length(r) : 1);
      consider(_b, bestCost + hB + bits, bestPrev, true);
      if (cost[_b] < _inf) consider(_b, cost[_b] + bits, _b, false);
    }
    if (kanji && kanjiValue(r) != null) {
      consider(_k, bestCost + hK + 13, bestPrev, true);
      if (cost[_k] < _inf) consider(_k, cost[_k] + 13, _k, false);
    }
    if (next.every((c) => c >= _inf)) return null; // Character not encodable.
    cost = next;
  }

  var state = 0;
  for (var s = 1; s < _states; s++) {
    if (cost[s] < cost[state]) state = s;
  }
  final total = cost[state];
  final runs = <(QrMode, int, int)>[];
  var end = n;
  for (var i = n - 1; i >= 0; i--) {
    final idx = i * _states + state;
    if (fresh[idx]) {
      runs.add((_modeOf(state), i, end));
      end = i;
    }
    state = prev[idx];
  }
  return _Plan(total, runs.reversed.toList());
}
