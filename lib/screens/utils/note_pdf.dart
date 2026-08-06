import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a printable PDF for a single bitácora note.
///
/// Deliberately NOT using PdfGoogleFonts: it fetches over the network, and this
/// runs on job sites. The built-in Helvetica is WinAnsi-encoded, which covers
/// every character Spanish needs — á é í ó ú ñ ¿ ¡ — so no TTF asset is
/// bundled. If a glyph ever turns up missing, bundle a font rather than
/// reaching for the Google fonts helper.

/// Where the letterhead logo is expected.
///
/// Drop a file at this path and the next build picks it up: `assets/` is
/// declared as a *directory* in pubspec.yaml precisely so that needs no
/// pubspec edit. Until the file exists the letterhead falls back to a text
/// wordmark, so nothing here depends on it being present — a missing asset
/// must never break the build or the print.
const String kLetterheadLogoAsset = 'assets/logo_cotelsa.png';

Future<Uint8List?> _loadLetterheadLogo() async {
  try {
    final data = await rootBundle.load(kLetterheadLogoAsset);
    return data.buffer.asUint8List();
  } catch (_) {
    // Not supplied yet, or not bundled. Text wordmark instead.
    return null;
  }
}

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

/// Trims a trailing `.0` so quantities read `12` rather than `12.0`, matching
/// how the logbook renders them on screen.
String _fmtQty(dynamic q) {
  if (q == null) return '';
  final d = q is num ? q.toDouble() : double.tryParse(q.toString());
  if (d == null) return q.toString();
  return d == d.roundToDouble()
      ? d.toStringAsFixed(0)
      : d.toString();
}

/// Renders one note to PDF bytes, ready for [Printing.layoutPdf].
///
/// Every optional block is genuinely optional — the note JSON makes
/// `partida_code`/`partida_name` null via a LEFT JOIN, and `avance` null when
/// the note recorded no progress, with `code` and `unit` nullable inside it.
/// `folio` is NOT NULL in the database since migration 12, but is guarded
/// anyway because it costs nothing.
Future<Uint8List> buildNotePdf({
  required Map<String, dynamic> note,
  required String projectName,
}) async {
  final logo = await _loadLetterheadLogo();

  final folio = note['folio'];
  final author = (note['author'] ?? '').toString();
  final body = (note['note_text'] ?? '').toString();
  final partidaCode = note['partida_code'];
  final partidaName = note['partida_name'];
  final avance = note['avance'] as Map<String, dynamic>?;
  final date = _fmtDate(note['note_date']?.toString());

  final doc = pw.Document();

  // MultiPage, never Page: a long note on a single Page is clipped silently —
  // no error, no ellipsis, the text simply stops.
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter, // Carta
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
      header: (context) => _letterhead(logo, projectName),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 12),
        _metaRow(folio, date),
        if (partidaName != null) ...[
          pw.SizedBox(height: 10),
          _labelled(
            'PARTIDA',
            partidaCode != null ? '$partidaCode · $partidaName' : '$partidaName',
          ),
        ],
        pw.SizedBox(height: 16),
        _sectionTitle('NOTA'),
        pw.SizedBox(height: 6),
        pw.Text(body, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
        if (avance != null) ...[
          pw.SizedBox(height: 18),
          _sectionTitle('AVANCE REGISTRADO'),
          pw.SizedBox(height: 6),
          _avanceBlock(avance),
        ],
        pw.SizedBox(height: 40),
        _signature(author),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _letterhead(Uint8List? logo, String projectName) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (logo != null)
            pw.Image(pw.MemoryImage(logo), height: 38)
          else
            pw.Text(
              'COTELSA',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'BITÁCORA DE OBRA',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                projectName.toUpperCase(),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Divider(thickness: 1, color: PdfColors.grey400),
    ],
  );
}

pw.Widget _metaRow(dynamic folio, String date) {
  return pw.Row(
    children: [
      pw.Expanded(child: _labelled('NOTA', folio != null ? '$folio' : '—')),
      pw.Expanded(child: _labelled('FECHA', date.isEmpty ? '—' : date)),
    ],
  );
}

pw.Widget _labelled(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey600,
          letterSpacing: 1,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
    ],
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey600,
      letterSpacing: 1,
    ),
  );
}

pw.Widget _avanceBlock(Map<String, dynamic> avance) {
  final code = avance['code'];
  final name = (avance['name'] ?? '').toString();
  final unit = avance['unit'];
  final qty = _fmtQty(avance['quantity']);

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            code != null ? '$code · $name' : name,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          unit != null ? '+$qty $unit' : '+$qty',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

pw.Widget _signature(String author) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(width: 220, child: pw.Divider(thickness: 0.8)),
      pw.SizedBox(height: 3),
      pw.Text(
        'ELABORÓ',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey600,
          letterSpacing: 1,
        ),
      ),
      if (author.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(author, style: const pw.TextStyle(fontSize: 10)),
      ],
    ],
  );
}
