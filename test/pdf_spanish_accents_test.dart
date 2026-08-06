import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// Does the built-in Helvetica actually carry the accented characters the
/// bitácora prints?
///
/// The PDF deliberately bundles no TTF and never calls PdfGoogleFonts, which
/// fetches over the network — bad on a job site. That rests entirely on the
/// claim that Helvetica's WinAnsi encoding covers Spanish. The package prints
/// "Helvetica has no Unicode support" whenever a Type1 font is constructed,
/// which looks alarming but is an unconditional debug notice from inside an
/// assert, not a statement about the text being rendered.
///
/// So: render the exact strings the document uses, save UNCOMPRESSED, and look
/// for the WinAnsi byte for each accented character in the output.
void main() {
  test('Spanish accents survive into the PDF with the built-in font', () async {
    final doc = pw.Document(compress: false);
    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          children: [
            // Every accented string the real document contains.
            pw.Text('BITÁCORA DE OBRA'),
            pw.Text('ELABORÓ'),
            pw.Text('FOTOGRAFÍAS'),
            pw.Text('Página 1 de 2'),
            pw.Text('No se pudieron incluir 2 fotografías.'),
            pw.Text('AÑO ¿QUÉ? ¡SÍ!'),
          ],
        ),
      ),
    );

    final bytes = await doc.save();

    // WinAnsi code points. If a glyph were unsupported the encoder could not
    // emit these, and the character would be dropped or substituted.
    const winAnsi = <String, int>{
      'Á': 0xC1,
      'Ó': 0xD3,
      'Í': 0xCD,
      'á': 0xE1,
      'í': 0xED,
      'Ñ': 0xD1,
      'É': 0xC9,
      'Í(acute)': 0xCD,
      '¿': 0xBF,
      '¡': 0xA1,
    };

    final missing = <String>[];
    for (final entry in winAnsi.entries) {
      if (!bytes.contains(entry.value)) missing.add(entry.key);
    }

    expect(
      missing,
      isEmpty,
      reason: 'these accented glyphs never reached the PDF: $missing — if this '
          'fails, bundle a TTF asset (NOT PdfGoogleFonts, which fetches over '
          'the network) and set it as the document theme',
    );
  });
}
