/// Turns raw OCR text from a Mexican identity document into candidate field
/// values for the worker form.
///
/// **No Flutter import**, for the same reason as `document_validators.dart`:
/// this is testable without a camera, and every parsing decision here is one
/// that can be pinned by feeding synthetic OCR text.
///
/// v1 handles the INE (credencial para votar) and the SAT constancia de
/// situación fiscal. Between them they cover NOMBRE, CURP, DIRECCIÓN and RFC —
/// the four highest-value fields — and both have layouts stable enough to
/// anchor on. IMSS is one field; bank documents vary enormously and statements
/// usually mask the card number, so both are deferred.
///
/// **Everything here is a candidate, never an answer.** Nothing in this file
/// writes to a controller; it produces values for a review sheet where a human
/// confirms each one. Parsers of scanned text are wrong often enough that any
/// other arrangement would eventually put a stranger's CURP on a worker record.
library;

import 'document_validators.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Which form field a scanned value is a candidate for.
///
/// Deliberately not every field on the form. Payroll figures — SDI, extra hour,
/// compensations, loans, INFONAVIT, FONACOT — are negotiated values, not
/// document values, and must never be populated from a scan even when a
/// document happens to show a number that looks like one.
enum WorkerField { name, curp, rfc, address }

enum DocumentKind {
  ine,
  satConstancia,
  unknown;

  String get label => switch (this) {
        DocumentKind.ine => 'INE / Credencial para votar',
        DocumentKind.satConstancia => 'Constancia de situación fiscal (SAT)',
        DocumentKind.unknown => 'Documento no reconocido',
      };
}

/// One candidate value, ready for the review sheet.
class ScannedField {
  final WorkerField target;
  final String label;
  final String value;

  /// Validation result when the field has a check digit; `null` otherwise.
  /// A `null` here means "cannot be verified", never "failed".
  final DocField? check;

  const ScannedField({
    required this.target,
    required this.label,
    required this.value,
    this.check,
  });

  /// Pre-ticked only when a check digit verified. A name or an address has no
  /// check digit, so it always arrives unticked for the user to confirm.
  bool get preTicked => check?.preTicked ?? false;

  List<String> get notes => check?.notes ?? const [];
}

class ScanResult {
  final DocumentKind kind;

  /// The full OCR text. Kept so the sheet can show it when nothing parsed —
  /// a partial read the user can copy from beats a dead end, and an empty
  /// sheet with no explanation is indistinguishable from a broken feature.
  final String rawText;

  final List<ScannedField> fields;

  /// Advisory cross-document notes. Never a reason to withhold a value.
  final List<String> notes;

  const ScanResult({
    required this.kind,
    required this.rawText,
    this.fields = const [],
    this.notes = const [],
  });

  bool get isEmpty => fields.isEmpty;
}

// ---------------------------------------------------------------------------
// Text preparation
// ---------------------------------------------------------------------------

/// Uppercased, accent-folded, whitespace-collapsed — for *matching only*.
///
/// Accent folding is what makes detection survive a real scan: OCR routinely
/// drops the accent in `SITUACIÓN`, and a strict match would fall through to
/// the "which document is this?" prompt on a perfectly good photo.
String _flat(String s) =>
    normalise(s).replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _lines(String text) => text
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

const List<String> _ineMarkers = [
  'CREDENCIAL PARA VOTAR',
  'INSTITUTO NACIONAL ELECTORAL',
  'INSTITUTO FEDERAL ELECTORAL', // pre-2014 cards still in circulation
  'CLAVE DE ELECTOR',
];

const List<String> _satMarkers = [
  'CONSTANCIA DE SITUACION FISCAL',
  'CEDULA DE IDENTIFICACION FISCAL',
  'SERVICIO DE ADMINISTRACION TRIBUTARIA',
  'REGISTRO FEDERAL DE CONTRIBUYENTES',
];

/// Identifies the document from distinctive strings.
///
/// Returns [DocumentKind.unknown] rather than guessing when nothing matches or
/// both match — the caller asks the user instead. A wrong auto-detection is
/// worse than a question, because it silently applies the wrong parser and
/// produces plausible values from the wrong fields.
DocumentKind detectDocument(String text) {
  final flat = _flat(text);
  final ine = _ineMarkers.any(flat.contains);
  final sat = _satMarkers.any(flat.contains);
  if (ine && !sat) return DocumentKind.ine;
  if (sat && !ine) return DocumentKind.satConstancia;
  return DocumentKind.unknown;
}

// ---------------------------------------------------------------------------
// Field location
// ---------------------------------------------------------------------------

/// Text following `label` on the same line, or the next non-empty line.
///
/// OCR puts a label and its value on one line about as often as on two, so both
/// shapes have to work. Returns null rather than an empty string when there is
/// nothing after the label, so callers can tell "absent" from "blank".
String? _afterLabel(List<String> lines, List<String> labels) {
  for (var i = 0; i < lines.length; i++) {
    final flat = _flat(lines[i]);
    for (final label in labels) {
      final at = flat.indexOf(label);
      if (at < 0) continue;
      final tail = flat.substring(at + label.length).replaceFirst(
            RegExp(r'^[:\s.\-]+'),
            '',
          );
      if (tail.isNotEmpty) return tail;
      if (i + 1 < lines.length) return _flat(lines[i + 1]);
      return null;
    }
  }
  return null;
}

final RegExp _curpChars = RegExp(r'^[A-ZÑ0-9]{18}$');
final RegExp _rfcChars = RegExp(r'^[A-ZÑ&0-9]{13}$');

/// Exact-width candidates built from **whole tokens**, one to four consecutive.
///
/// Two wrong approaches this replaces, both of which were written and both of
/// which failed:
///
/// - `RegExp.allMatches` advances by the length of each match, so on
///   separator-stripped text it only tests offsets 0, 18, 36 … and misses any
///   CURP not starting on a multiple of its own length.
/// - A sliding window at every offset finds candidates that straddle unrelated
///   words, and **a straddle passes the check digit about one time in ten**.
///   With fifty windows on a page that is not a risk, it is a certainty:
///   `RAVOTARPRGRJNBSO10`, spanning "CREDENCIAL PARA VOTAR" and a clave de
///   elector, verified cleanly. One decimal digit cannot carry the weight of
///   disambiguating arbitrary substrings.
///
/// Joining up to four consecutive tokens is what still recovers a CURP that OCR
/// split into groups, without inventing candidates that cross a real boundary.
Iterable<String> _tokenCandidates(String text, int width) sync* {
  final tokens = normalise(text)
      .split(RegExp(r'[^A-ZÑ&0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  for (var i = 0; i < tokens.length; i++) {
    final buf = StringBuffer();
    for (var j = i; j < tokens.length && j < i + 4; j++) {
      buf.write(tokens[j]);
      if (buf.length == width) {
        yield buf.toString();
        break;
      }
      if (buf.length > width) break;
    }
  }
}

/// Finds the CURP, preferring a labelled one and falling back to check-digit
/// disambiguation.
///
/// ⚠ **The INE carries a CLAVE DE ELECTOR, which is also 18 characters.**
/// Grabbing the first 18-character run off an INE returns the clave roughly as
/// often as the CURP, and the result looks entirely plausible. Two defences,
/// in order: anchor on the `CURP` label, and if that fails, scan every
/// 18-character candidate and keep only one whose CURP check digit verifies.
/// The clave de elector is built by a different rule and will not verify, so
/// the check digit disambiguates them for free.
DocField? findCurp(String text) {
  final lines = _lines(text);
  DocField? fallback;

  final labelled = _afterLabel(lines, ['CURP']);
  if (labelled != null) {
    final compact = labelled.replaceAll(RegExp(r'[^A-ZÑ0-9]'), '');
    if (compact.length >= 18) {
      final r = validateCurp(compact.substring(0, 18));
      if (r.checkDigitOk == true) return r;
      // A labelled but unverified read still beats anything unlabelled, so it
      // is claimed as the fallback before the scan can overwrite it.
      if (r.structureOk) fallback = r;
    }
  }

  for (final cand in _tokenCandidates(text, 18)) {
    if (!_curpChars.hasMatch(cand)) continue;
    final r = validateCurp(cand);
    // Structure AND check digit — i.e. preTicked. The check digit alone is one
    // decimal digit and accepts a tenth of everything it is shown; the
    // structural mask is what actually rules out a clave de elector, whose
    // date block holds letters.
    if (r.preTicked) return r;
    fallback ??= r.structureOk ? r : null;
  }
  // Nothing verified. Return a structurally plausible read if there was one so
  // the user gets something to correct, unticked, rather than nothing at all.
  return fallback;
}

/// Finds the RFC, same strategy as [findCurp].
///
/// The RFC's first 10 characters are a prefix of the CURP's, so an unlabelled
/// scan of a document carrying both can match inside the CURP. Anchoring on the
/// label first is what avoids that; the check digit catches the rest.
DocField? findRfc(String text) {
  final lines = _lines(text);
  DocField? fallback;

  final labelled = _afterLabel(lines, ['RFC', 'R.F.C']);
  if (labelled != null) {
    final compact = labelled.replaceAll(RegExp(r'[^A-ZÑ&0-9]'), '');
    if (compact.length >= 13) {
      final r = validateRfc(compact.substring(0, 13));
      if (r.checkDigitOk == true) return r;
      if (r.structureOk) fallback = r;
    }
  }

  for (final cand in _tokenCandidates(text, 13)) {
    if (!_rfcChars.hasMatch(cand)) continue;
    final r = validateRfc(cand);
    if (r.preTicked) return r;
    fallback ??= r.structureOk ? r : null;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// INE
// ---------------------------------------------------------------------------

/// Labels that end the NOMBRE block on an INE.
const List<String> _ineNameStops = [
  'DOMICILIO',
  'CLAVE DE ELECTOR',
  'CURP',
  'FECHA DE NACIMIENTO',
  'SEXO',
  'ANO DE REGISTRO',
];

/// Labels that end the DOMICILIO block.
const List<String> _ineAddressStops = [
  'CLAVE DE ELECTOR',
  'CURP',
  'ESTADO',
  'MUNICIPIO',
  'SECCION',
  'LOCALIDAD',
  'EMISION',
  'VIGENCIA',
];

List<String> _blockAfter(
  List<String> lines,
  String startLabel,
  List<String> stops, {
  int maxLines = 4,
}) {
  final out = <String>[];
  var started = false;
  for (final line in lines) {
    final flat = _flat(line);
    if (!started) {
      if (flat.contains(startLabel)) {
        started = true;
        final tail = flat
            .substring(flat.indexOf(startLabel) + startLabel.length)
            .replaceFirst(RegExp(r'^[:\s.\-]+'), '');
        if (tail.isNotEmpty) out.add(tail);
      }
      continue;
    }
    if (stops.any(flat.contains)) break;
    out.add(flat);
    if (out.length >= maxLines) break;
  }
  return out;
}

/// Rebuilds a full name from the INE's name block, **reordering it**.
///
/// The card prints surnames first, given names last, in **exactly three
/// lines**:
///
///     NOMBRE
///     HERNANDEZ         <- apellido paterno, always line 1
///     GARCIA            <- apellido materno, always line 2
///     GLORIA MARIA      <- nombre(s), line 3 — BOTH names when there are two
///
/// Confirmed against a real credencial (2026-08-24). Two given names share the
/// third line rather than spilling onto a fourth, so the whole line is taken;
/// keeping only the first name would drop half of anyone called GLORIA MARIA.
///
/// **Joining them in printed order is wrong**, and was the shipped behaviour
/// until that test. It produced "HERNANDEZ GARCIA GLORIA", which is not how the
/// form or any other screen renders a name — and it silently broke the CURP
/// cross-check as well, because [curpPrefixFromName] reads the last two tokens
/// as the surnames. From the mis-ordered string it derived a prefix from
/// "GARCIA GLORIA" and reported that a perfectly correct CURP did not match the
/// name. One ordering bug, two visible symptoms; the second was not a
/// false-positive in the cross-check and must not be "fixed" by loosening it.
String? _composeIneName(List<String> lines) {
  if (lines.isEmpty) return null;
  if (lines.length == 1) return lines.first;
  if (lines.length == 2) {
    // Both surnames sharing one line, given names on the next — the shape older
    // cards use. Reordered to the same result.
    return '${lines[1]} ${lines[0]}'.trim();
  }
  final paternal = lines[0];
  final maternal = lines[1];
  final given = lines.sublist(2).join(' ');
  return '$given $paternal $maternal'.trim();
}

ScanResult _parseIne(String text) {
  final lines = _lines(text);
  final fields = <ScannedField>[];

  // EXACTLY three lines. Confirmed against a real credencial: the block is
  // apellido paterno, apellido materno, nombre(s) — and the nombre(s) line
  // carries BOTH given names when there are two, so nothing is lost by
  // stopping here.
  //
  // ⚠ Do not raise this to 4. It was 4 briefly and the fourth line picked up
  // the domicilio, which then corrupted the name AND every field derived from
  // it. The stop-list below is only a secondary guard — on a real card the
  // DOMICILIO label does not reliably survive OCR as its own line, so the count
  // is what actually bounds this block.
  final nameLines = _blockAfter(lines, 'NOMBRE', _ineNameStops, maxLines: 3);
  final composedName = _composeIneName(nameLines);
  if (composedName != null && composedName.isNotEmpty) {
    fields.add(ScannedField(
      target: WorkerField.name,
      label: 'NOMBRE COMPLETO',
      value: composedName,
    ));
  }

  final addressLines =
      _blockAfter(lines, 'DOMICILIO', _ineAddressStops, maxLines: 4);
  if (addressLines.isNotEmpty) {
    fields.add(ScannedField(
      target: WorkerField.address,
      label: 'DIRECCIÓN',
      value: addressLines.join(' ').trim(),
    ));
  }

  final curp = findCurp(text);
  if (curp != null) {
    fields.add(ScannedField(
      target: WorkerField.curp,
      label: 'CURP',
      value: curp.value,
      check: curp,
    ));
  }

  return ScanResult(
    kind: DocumentKind.ine,
    rawText: text,
    fields: fields,
    notes: crossCheck(
      curp: curp?.value,
      name: fields
          .where((f) => f.target == WorkerField.name)
          .map((f) => f.value)
          .firstOrNull,
    ),
  );
}

// ---------------------------------------------------------------------------
// SAT constancia
// ---------------------------------------------------------------------------

ScanResult _parseSat(String text) {
  final lines = _lines(text);
  final fields = <ScannedField>[];

  // The constancia prints the name split across three labelled fields. Composed
  // in the order the form expects a full name to read.
  final given = _afterLabel(lines, ['NOMBRE (S)', 'NOMBRE(S)', 'NOMBRE']);
  final paternal = _afterLabel(lines, ['PRIMER APELLIDO', 'APELLIDO PATERNO']);
  final maternal = _afterLabel(lines, ['SEGUNDO APELLIDO', 'APELLIDO MATERNO']);
  final composed =
      [given, paternal, maternal].whereType<String>().join(' ').trim();
  if (composed.isNotEmpty) {
    fields.add(ScannedField(
      target: WorkerField.name,
      label: 'NOMBRE COMPLETO',
      value: composed,
    ));
  }

  final rfc = findRfc(text);
  if (rfc != null) {
    fields.add(ScannedField(
      target: WorkerField.rfc,
      label: 'RFC',
      value: rfc.value,
      check: rfc,
    ));
  }

  final curp = findCurp(text);
  if (curp != null) {
    fields.add(ScannedField(
      target: WorkerField.curp,
      label: 'CURP',
      value: curp.value,
      check: curp,
    ));
  }

  // The domicilio fiscal is a set of labelled parts rather than a block, so it
  // is reassembled from the ones that are present. Missing parts are skipped
  // rather than left as gaps — the user edits the result anyway.
  const addressLabels = [
    ['NOMBRE DE VIALIDAD', 'VIALIDAD', 'CALLE'],
    ['NUMERO EXTERIOR', 'NO EXTERIOR', 'NUM EXTERIOR'],
    ['NUMERO INTERIOR', 'NO INTERIOR', 'NUM INTERIOR'],
    ['NOMBRE DE LA COLONIA', 'COLONIA'],
    ['NOMBRE DEL MUNICIPIO O DEMARCACION TERRITORIAL', 'MUNICIPIO'],
    ['NOMBRE DE LA ENTIDAD FEDERATIVA', 'ENTIDAD FEDERATIVA', 'ESTADO'],
    ['CODIGO POSTAL', 'CP'],
  ];
  final parts = <String>[];
  for (final labels in addressLabels) {
    final v = _afterLabel(lines, labels);
    if (v != null && v.isNotEmpty) parts.add(v);
  }
  if (parts.isNotEmpty) {
    fields.add(ScannedField(
      target: WorkerField.address,
      label: 'DIRECCIÓN',
      value: parts.join(', '),
    ));
  }

  return ScanResult(
    kind: DocumentKind.satConstancia,
    rawText: text,
    fields: fields,
    notes: crossCheck(
      curp: curp?.value,
      rfc: rfc?.value,
      name: composed.isEmpty ? null : composed,
    ),
  );
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Parses OCR text, detecting the document unless [forced] says which it is.
///
/// [forced] is how the "which document is this?" fallback feeds back in: the
/// user answers, and the same parsers run without detection.
ScanResult parseDocument(String text, {DocumentKind? forced}) {
  final kind = forced ?? detectDocument(text);
  return switch (kind) {
    DocumentKind.ine => _parseIne(text),
    DocumentKind.satConstancia => _parseSat(text),
    // Unknown: no parser runs, but the raw text still travels so the sheet can
    // offer it. A read that found no fields is not the same as a failed scan,
    // and the user must be able to tell them apart.
    DocumentKind.unknown => ScanResult(kind: kind, rawText: text),
  };
}
