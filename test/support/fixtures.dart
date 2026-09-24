import 'dart:io';

/// Reads a fixture file, dropping blank lines and `#` comments.
List<String> fixtureLines(String name) => File('test/fixtures/$name')
    .readAsLinesSync()
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('#'))
    .toList();

/// Reads a module grid fixture (`1` = dark) as rows of bools.
List<List<bool>> fixtureGrid(String name) => fixtureLines(name)
    .map((l) => l.split('').map((c) => c == '1').toList())
    .toList();
