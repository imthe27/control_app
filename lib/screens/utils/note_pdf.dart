import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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

/// Longest edge, in pixels, a photo is decoded to before going into the PDF.
///
/// A full-width image on Carta at ~150dpi is about 1125px, so 1200 is already
/// generous. The number matters more for memory than for looks: the decode is
/// the expensive step, and `targetWidth` makes the platform decoder produce a
/// small raster directly instead of a full-resolution one we then shrink.
const int _kPhotoWidth = 1200;

/// Downloads one photo and re-encodes it small enough to embed. Null when the
/// photo cannot be used for any reason — the caller counts those and says so
/// on the page rather than silently printing fewer photos than the note has.
///
/// Three things here are deliberate:
///
/// 1. **The URL is used verbatim.** Since A9 the API hands out *signed* media
///    URLs carrying `?exp=&sig=`, valid 24-48h. Rebuilding one from a bare
///    filename produces a 403. This is also why there is no `authHeaders()`
///    call: the signature *is* the authorisation. It does not contradict
///    "api.dart is the only network entry point" — nothing here builds a URL
///    or a header map, it fetches an absolute one the server supplied, exactly
///    as CachedNetworkImage already does all over the app.
///
/// 2. **Decode is bounded by `targetWidth`.** There is no upload size cap, so
///    a site photo can be 12MP; decoding one at full resolution is ~48MB of
///    raster and a few of those OOM a mid-range phone. `instantiateImageCodec`
///    with `targetWidth` decodes straight to the smaller size.
///
/// 3. **Re-encoded as JPEG, not PNG.** `dart:ui` can only export PNG, and a
///    photo at this size is 1-2MB as PNG versus ~150KB as JPEG. `package:image`
///    supplies the encoder and costs nothing: `pdf` and `printing` both already
///    depend on it.
Future<Uint8List?> _photoForPdf(String url) async {
  ui.Image? decoded;
  ui.Codec? codec;
  try {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return null;

    codec = await ui.instantiateImageCodec(
      resp.bodyBytes,
      targetWidth: _kPhotoWidth,
    );
    final frame = await codec.getNextFrame();
    decoded = frame.image;
    final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;

    final raster = img.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(raster, quality: 80));
  } catch (_) {
    return null;
  } finally {
    // Released even on the failure paths: the raster is the expensive thing,
    // and a note with several photos runs this loop several times.
    decoded?.dispose();
    codec?.dispose();
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

  // Photos are fetched and re-encoded ONE AT A TIME, on purpose: each raster is
  // released before the next download starts, so peak memory is one photo's
  // worth rather than all of them. What is retained is the small JPEG.
  final photoUrls = List<String>.from(note['photos'] ?? const []);
  final photos = <pw.MemoryImage>[];
  var photosFailed = 0;
  for (final url in photoUrls) {
    final bytes = await _photoForPdf(url);
    if (bytes == null) {
      photosFailed++;
      continue;
    }
    photos.add(pw.MemoryImage(bytes));
  }

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
        if (photos.isNotEmpty || photosFailed > 0) ...[
          pw.SizedBox(height: 18),
          _sectionTitle('FOTOGRAFÍAS'),
          pw.SizedBox(height: 6),
          // One per block rather than a grid: site photos are the evidence on
          // a bitácora page, and MultiPage will flow them onto further pages
          // by itself. BoxFit.contain so portrait shots are not cropped.
          for (final photo in photos) ...[
            pw.Container(
              height: 240,
              width: double.infinity,
              alignment: pw.Alignment.center,
              child: pw.Image(photo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 10),
          ],
          // Said out loud rather than silently printing fewer photos than the
          // note holds. The usual cause is an expired media signature — those
          // URLs are good for 24-48h, so a note left open a long time then
          // printed will land here.
          if (photosFailed > 0)
            pw.Text(
              photosFailed == 1
                  ? 'No se pudo incluir 1 fotografía.'
                  : 'No se pudieron incluir $photosFailed fotografías.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
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
