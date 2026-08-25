import 'package:flutter_test/flutter_test.dart';
import 'package:control_app/utils/document_parsers.dart';
import 'package:control_app/utils/document_validators.dart';

/// Tests for document detection and the INE / SAT parsers.
///
/// The OCR text here is synthetic, which is the point: it pins the parsing
/// decisions — label anchoring, block boundaries, CURP-vs-clave disambiguation
/// — without a camera. It does NOT prove the parsers survive a real photograph.
/// That is what the on-device pass in §11 is for, and no amount of synthetic
/// text substitutes for it.

String _curpWithCheck(String body17) =>
    '$body17${curpCheckDigit('${body17}0')!}';

String _rfcWithCheck(String body12) =>
    '$body12${rfcCheckChar('${body12}0')!}';

final String validCurp = _curpWithCheck('HEGG560427MVZRRL0');
final String validRfc = _rfcWithCheck('HEGG560427J1');

void main() {
  group('detection', () {
    test('recognises an INE', () {
      expect(detectDocument('INSTITUTO NACIONAL ELECTORAL\nCREDENCIAL PARA VOTAR'),
          DocumentKind.ine);
    });

    test('recognises a pre-2014 IFE card', () {
      expect(detectDocument('INSTITUTO FEDERAL ELECTORAL'), DocumentKind.ine);
    });

    test('recognises a SAT constancia', () {
      expect(detectDocument('CONSTANCIA DE SITUACIÓN FISCAL'),
          DocumentKind.satConstancia);
    });

    test('survives OCR dropping the accent in SITUACION', () {
      // The failure this guards: a clean scan falling through to the "which
      // document is this?" prompt because OCR lost one accent.
      expect(detectDocument('constancia de situacion fiscal'),
          DocumentKind.satConstancia);
    });

    test('survives collapsed and broken whitespace', () {
      expect(detectDocument('CREDENCIAL   PARA\n VOTAR'), DocumentKind.ine);
    });

    test('returns unknown rather than guessing when nothing matches', () {
      expect(detectDocument('RECIBO DE NOMINA'), DocumentKind.unknown);
      expect(detectDocument(''), DocumentKind.unknown);
    });

    test('returns unknown when both documents match', () {
      // A photo catching two documents at once must ask, not pick — the wrong
      // parser produces plausible values from the wrong fields.
      expect(
        detectDocument('CREDENCIAL PARA VOTAR\nCONSTANCIA DE SITUACION FISCAL'),
        DocumentKind.unknown,
      );
    });
  });

  group('CURP vs CLAVE DE ELECTOR', () {
    // Both are 18 characters. Picking the wrong one yields a value that looks
    // entirely plausible on screen, so this is the parser's sharpest edge.
    const clave = 'PRGRJN85010109H400';

    test('the clave is not mistaken for a CURP when unlabelled', () {
      final text = 'CREDENCIAL PARA VOTAR\n$clave\n$validCurp';
      final found = findCurp(text);
      expect(found, isNotNull);
      expect(found!.value, validCurp);
      expect(found.checkDigitOk, isTrue);
    });

    test('order does not matter — the check digit decides, not position', () {
      final text = 'CREDENCIAL PARA VOTAR\n$validCurp\n$clave';
      expect(findCurp(text)!.value, validCurp);
    });

    test('the CURP label is honoured when present', () {
      final text = 'CLAVE DE ELECTOR $clave\nCURP $validCurp';
      expect(findCurp(text)!.value, validCurp);
    });

    test('a label on the following line still resolves', () {
      final text = 'CURP\n$validCurp';
      expect(findCurp(text)!.value, validCurp);
    });

    test('an unverifiable read is still returned, but never pre-ticked', () {
      // Structurally CURP-shaped, wrong check digit. The user gets something to
      // correct rather than an empty sheet.
      final broken = '${validCurp.substring(0, 17)}'
          '${(int.parse(validCurp[17]) + 1) % 10}';
      final found = findCurp('CURP $broken');
      expect(found, isNotNull);
      expect(found!.checkDigitOk, isFalse);
      expect(found.preTicked, isFalse);
    });

    test('returns null when there is nothing CURP-shaped at all', () {
      expect(findCurp('CREDENCIAL PARA VOTAR\nJUAN PEREZ'), isNull);
    });
  });

  group('INE', () {
    final ineText = '''
INSTITUTO NACIONAL ELECTORAL
CREDENCIAL PARA VOTAR
NOMBRE
HERNANDEZ GARCIA
GLORIA
DOMICILIO
C ORQUIDEA 123 INT 4
COL LAS FLORES 91700
VERACRUZ, VER.
CLAVE DE ELECTOR PRGRJN85010109H400
CURP $validCurp
ANO DE REGISTRO 2018 01
''';

    test('extracts the name block and stops at DOMICILIO', () {
      final r = parseDocument(ineText);
      expect(r.kind, DocumentKind.ine);
      final name =
          r.fields.firstWhere((f) => f.target == WorkerField.name).value;
      expect(name, 'HERNANDEZ GARCIA GLORIA');
      expect(name, isNot(contains('ORQUIDEA')));
    });

    test('extracts the address block and stops at CLAVE DE ELECTOR', () {
      final r = parseDocument(ineText);
      final addr =
          r.fields.firstWhere((f) => f.target == WorkerField.address).value;
      expect(addr, contains('ORQUIDEA'));
      expect(addr, contains('LAS FLORES'));
      expect(addr, isNot(contains('PRGRJN')));
      expect(addr, isNot(contains('CURP')));
    });

    test('extracts the CURP, pre-ticked', () {
      final r = parseDocument(ineText);
      final curp =
          r.fields.firstWhere((f) => f.target == WorkerField.curp);
      expect(curp.value, validCurp);
      expect(curp.preTicked, isTrue);
    });

    test('never produces an RFC from an INE', () {
      final r = parseDocument(ineText);
      expect(r.fields.any((f) => f.target == WorkerField.rfc), isFalse);
    });

    test('never targets a payroll field', () {
      final r = parseDocument(ineText);
      for (final f in r.fields) {
        expect(
          [WorkerField.name, WorkerField.curp, WorkerField.address, WorkerField.rfc],
          contains(f.target),
        );
      }
    });
  });

  group('SAT constancia', () {
    final satText = '''
SERVICIO DE ADMINISTRACIÓN TRIBUTARIA
CONSTANCIA DE SITUACIÓN FISCAL
RFC: $validRfc
CURP: $validCurp
Nombre (s): GLORIA
Primer Apellido: HERNANDEZ
Segundo Apellido: GARCIA
Nombre de Vialidad: ORQUIDEA
Número Exterior: 123
Nombre de la Colonia: LAS FLORES
Código Postal: 91700
''';

    test('composes the name from three labelled parts', () {
      final r = parseDocument(satText);
      expect(r.kind, DocumentKind.satConstancia);
      final name =
          r.fields.firstWhere((f) => f.target == WorkerField.name).value;
      expect(name, 'GLORIA HERNANDEZ GARCIA');
    });

    test('extracts RFC and CURP, both pre-ticked', () {
      final r = parseDocument(satText);
      final rfc = r.fields.firstWhere((f) => f.target == WorkerField.rfc);
      final curp = r.fields.firstWhere((f) => f.target == WorkerField.curp);
      expect(rfc.value, validRfc);
      expect(rfc.preTicked, isTrue);
      expect(curp.value, validCurp);
      expect(curp.preTicked, isTrue);
    });

    test('does not read the RFC out of the CURP', () {
      // The RFC's first 10 characters are a prefix of the CURP's, so an
      // unanchored scan can match inside the CURP and return a wrong value.
      final r = parseDocument(satText);
      final rfc = r.fields.firstWhere((f) => f.target == WorkerField.rfc);
      expect(rfc.value.length, 13);
      expect(rfc.value, validRfc);
    });

    test('reassembles the domicilio fiscal from its labelled parts', () {
      final r = parseDocument(satText);
      final addr =
          r.fields.firstWhere((f) => f.target == WorkerField.address).value;
      expect(addr, contains('ORQUIDEA'));
      expect(addr, contains('123'));
      expect(addr, contains('LAS FLORES'));
      expect(addr, contains('91700'));
    });

    test('agreeing CURP and RFC produce no cross-check noise', () {
      final r = parseDocument(satText);
      expect(r.notes.any((n) => n.contains('fecha')), isFalse);
    });
  });

  group('unknown document', () {
    test('runs no parser but keeps the raw text', () {
      const junk = 'RECIBO DE LUZ\nTOTAL A PAGAR 432.10';
      final r = parseDocument(junk);
      expect(r.kind, DocumentKind.unknown);
      expect(r.isEmpty, isTrue);
      expect(r.rawText, junk,
          reason: 'the sheet offers the raw text instead of a dead end');
    });

    test('a forced kind bypasses detection', () {
      // How the "which document is this?" answer feeds back in.
      final text = 'NOMBRE\nJUAN PEREZ LOPEZ\nDOMICILIO\nCALLE 5\nCURP $validCurp';
      expect(parseDocument(text).kind, DocumentKind.unknown);
      final forced = parseDocument(text, forced: DocumentKind.ine);
      expect(forced.kind, DocumentKind.ine);
      expect(forced.isEmpty, isFalse);
      expect(forced.fields.firstWhere((f) => f.target == WorkerField.curp).value,
          validCurp);
    });
  });
}
