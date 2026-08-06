import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the whole class of bug that put a ballot box on a printed cover page.
///
/// The PDF deliberately bundles no font and uses the built-in Helvetica, whose
/// support is **Latin-1 and nothing else**:
///
/// ```dart
/// bool isRuneSupported(int charCode) => charCode >= 0x00 && charCode <= 0xff;
/// ```
///
/// Anything above U+00FF gets `_addPlaceholder()` — a box — and the package's
/// "Unable to find a font to draw ..." warning lives inside an `assert`, so it
/// prints in debug and is **silent in a release build**. That is how an em dash
/// (U+2014) reached printed paper: it looked fine in every check that was not
/// an actual print.
///
/// Accented Spanish is safe (á U+00E1, ñ U+00F1, ¿ U+00BF, · U+00B7 are all
/// under 0xFF). The traps are the typographic characters an editor inserts
/// without comment: — – ‘ ’ “ ” … • ½ → ≤.
///
/// This scans the source rather than the rendered output because the strings
/// are built at runtime from note data; the literals are what can be checked
/// statically, and they are where the mistake gets made.
void main() {
  test('note_pdf.dart contains no rune above Latin-1', () {
    final file = File('lib/screens/utils/note_pdf.dart');
    expect(file.existsSync(), isTrue, reason: 'run from the package root');

    final offenders = <String>[];
    final lines = file.readAsStringSync().split(RegExp(r'\r?\n'));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Doc comments and line comments are prose — they may legitimately
      // contain the very characters being banned, including in this file's own
      // explanation of the bug.
      if (RegExp(r'^\s*///').hasMatch(line)) continue;
      final code = line.replaceAll(RegExp(r'//.*$'), '');

      for (final rune in code.runes) {
        if (rune > 0xFF) {
          offenders.add(
            'line ${i + 1}: U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            '"${String.fromCharCode(rune)}"',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These render as a placeholder box in the printed PDF, with no '
          'error in a release build:\n  ${offenders.join('\n  ')}\n'
          'Use an ASCII equivalent, or bundle a TTF and set it as the document '
          'theme (NOT PdfGoogleFonts, which fetches over the network).',
    );
  });
}
