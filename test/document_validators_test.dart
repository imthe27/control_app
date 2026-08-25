import 'package:flutter_test/flutter_test.dart';
import 'package:control_app/utils/document_validators.dart';

/// Tests for the document scanner's validators.
///
/// **Values are constructed, not copied.** Hardcoding a "known good" CURP means
/// betting the test on my transcription of someone's real document, and a typo
/// there produces a test that passes against a broken implementation. Instead
/// each case builds a body, derives the check character with the same function
/// under test, and then asserts the property that matters: the derived one
/// verifies and **every other** value in the slot fails. That catches an
/// implementation that returns a constant, ignores position weights, or accepts
/// everything — which a single hardcoded example does not.
///
/// The real documents are exercised separately, on device, per §11.

String _curpWithCheck(String body17) {
  final d = curpCheckDigit('${body17}0')!;
  return '$body17$d';
}

String _rfcWithCheck(String body12) {
  final c = rfcCheckChar('${body12}0')!;
  return '$body12$c';
}

String _luhnComplete(String partial) {
  for (var d = 0; d <= 9; d++) {
    if (luhnOk('$partial$d')) return '$partial$d';
  }
  throw StateError('no Luhn completion for $partial');
}

String _clabeComplete(String body17) {
  for (var d = 0; d <= 9; d++) {
    if (validateClabe('$body17$d').checkDigitOk == true) return '$body17$d';
  }
  throw StateError('no CLABE completion for $body17');
}

void main() {
  group('CURP', () {
    // Born 1956: position 17 is a DIGIT. This is the case a naive
    // ^[A-Z]{18}$ gets wrong, and it covers roughly everyone over 26.
    const pre2000Body = 'HEGG560427MVZRRL0';
    // Born 2004: position 17 is a LETTER. 17 chars —
    // MARJ 040712 H DF RNS A
    const post2000Body = 'MARJ040712HDFRNSA';

    test('accepts a pre-2000 CURP whose 17th character is a digit', () {
      final curp = _curpWithCheck(pre2000Body);
      final r = validateCurp(curp);
      expect(r.structureOk, isTrue);
      expect(r.checkDigitOk, isTrue);
      expect(r.preTicked, isTrue);
    });

    test('accepts a post-2000 CURP whose 17th character is a letter', () {
      final curp = _curpWithCheck(post2000Body);
      final r = validateCurp(curp);
      expect(r.structureOk, isTrue, reason: 'position 17 may be a letter');
      expect(r.checkDigitOk, isTrue);
    });

    test('rejects every check digit except the correct one', () {
      final good = _curpWithCheck(pre2000Body);
      final correct = good[17];
      var rejected = 0;
      for (var d = 0; d <= 9; d++) {
        if ('$d' == correct) continue;
        final r = validateCurp('$pre2000Body$d');
        expect(r.checkDigitOk, isFalse);
        expect(r.preTicked, isFalse);
        rejected++;
      }
      expect(rejected, 9, reason: 'exactly nine wrong digits must be rejected');
    });

    test('a wrong length never pre-ticks', () {
      expect(validateCurp('HEGG560427MVZRRL').preTicked, isFalse);
      expect(validateCurp('').preTicked, isFalse);
      expect(validateCurp('HEGG560427MVZRRL0123').preTicked, isFalse);
    });

    test('an unknown state code is a note, not a rejection', () {
      // ZZ is not a real state code. The check digit must still decide.
      final curp = _curpWithCheck('HEGG560427MZZRRL0');
      final r = validateCurp(curp);
      expect(r.checkDigitOk, isTrue);
      expect(r.notes, isNotEmpty);
      expect(r.notes.first, contains('ZZ'));
      expect(r.preTicked, isTrue,
          reason: 'our state table must never overrule a valid check digit');
    });

    test('coerces letter-shaped digits inside the date block', () {
      final curp = _curpWithCheck(pre2000Body);
      // 560427 misread as S6O427: S->5 and O->0, both in D slots.
      final misread = curp.replaceRange(4, 10, 'S6O427');
      final r = validateCurp(misread);
      expect(r.value.substring(4, 10), '560427');
      expect(r.checkDigitOk, isTrue,
          reason: 'coercion must happen before validation');
    });

    test('does not coerce the differentiator or the check digit', () {
      // Position 17 of this body is '0'. If coercion touched '?' slots it
      // would become 'O' and the check digit arithmetic would change.
      final curp = _curpWithCheck(pre2000Body);
      expect(validateCurp(curp).value[16], '0');
    });
  });

  group('RFC', () {
    const body12 = 'HEGG560427M';

    test('accepts a correctly derived check character', () {
      final rfc = _rfcWithCheck('${body12}J');
      expect(rfc.length, 13);
      final r = validateRfc(rfc);
      expect(r.structureOk, isTrue);
      expect(r.checkDigitOk, isTrue);
      expect(r.preTicked, isTrue);
    });

    test('rejects a tampered check character', () {
      final rfc = _rfcWithCheck('${body12}J');
      final wrong = rfc[12] == 'A' ? '0' : 'A';
      final r = validateRfc('${rfc.substring(0, 12)}$wrong');
      expect(r.checkDigitOk, isFalse);
      expect(r.preTicked, isFalse);
    });

    test('rejects a 12-character persona moral RFC', () {
      // Not supported on purpose: a worker is never a company.
      final r = validateRfc('ABC560427XY1');
      expect(r.structureOk, isFalse);
      expect(r.preTicked, isFalse);
    });

    test('the check character can legitimately be A', () {
      // remainder == 1 maps to 'A', a branch a numeric-only implementation
      // silently gets wrong.
      var foundA = false;
      for (var i = 0; i < 200 && !foundA; i++) {
        final rfc = _rfcWithCheck('HEGG5604${i.toString().padLeft(2, '0')}7M');
        if (rfc[12] == 'A') {
          foundA = true;
          expect(validateRfc(rfc).checkDigitOk, isTrue);
        }
      }
      expect(foundA, isTrue, reason: 'expected an A check character in range');
    });
  });

  group('NSS', () {
    test('accepts a Luhn-valid 11-digit number', () {
      final nss = _luhnComplete('1234567890');
      expect(nss.length, 11);
      final r = validateNss(nss);
      expect(r.checkDigitOk, isTrue);
      expect(r.preTicked, isTrue);
    });

    test('rejects a single-digit transposition', () {
      final nss = _luhnComplete('1234567890');
      final broken = nss.replaceRange(
          3, 4, ((int.parse(nss[3]) + 1) % 10).toString());
      expect(validateNss(broken).checkDigitOk, isFalse);
    });

    test('strips separators and recovers letter-shaped digits', () {
      final nss = _luhnComplete('1234567890');
      final messy = '${nss.substring(0, 2)}-${nss.substring(2, 6)} '
          '${nss.substring(6)}'
          .replaceFirst('0', 'O');
      expect(validateNss(messy).value.length, 11);
    });

    test('wrong length never pre-ticks', () {
      expect(validateNss('123').preTicked, isFalse);
      expect(validateNss('123456789012').preTicked, isFalse);
    });
  });

  group('CLABE', () {
    test('accepts a correctly weighted 18-digit CLABE', () {
      final clabe = _clabeComplete('01234567890123456');
      expect(clabe.length, 18);
      final r = validateClabe(clabe);
      expect(r.checkDigitOk, isTrue);
      expect(r.preTicked, isTrue);
    });

    test('rejects every check digit except the correct one', () {
      const body = '01234567890123456';
      final good = _clabeComplete(body);
      var rejected = 0;
      for (var d = 0; d <= 9; d++) {
        if ('$body$d' == good) continue;
        expect(validateClabe('$body$d').checkDigitOk, isFalse);
        rejected++;
      }
      expect(rejected, 9);
    });

    test('is not satisfied by a plain Luhn check', () {
      // The weighted-mod-10 and Luhn algorithms disagree on most inputs; if
      // this implementation had used Luhn by mistake, this would catch it.
      const body = '01234567890123456';
      final clabe = _clabeComplete(body);
      final luhnVersion = _luhnComplete(body);
      expect(clabe == luhnVersion, isFalse,
          reason: 'CLABE must not be validated as Luhn');
    });
  });

  group('card number', () {
    test('accepts 13 to 19 digits with a valid Luhn', () {
      for (final len in [13, 16, 19]) {
        final card = _luhnComplete('4' * (len - 1));
        final r = validateCard(card);
        expect(r.structureOk, isTrue, reason: 'length $len');
        expect(r.checkDigitOk, isTrue, reason: 'length $len');
      }
    });

    test('flags a card longer than the form field accepts', () {
      final card = _luhnComplete('4' * 18); // 19 digits
      final r = validateCard(card);
      expect(r.checkDigitOk, isTrue);
      expect(r.notes.any((n) => n.contains('16')), isTrue,
          reason: 'the form field is maxLen: 16');
    });

    test('rejects 12 digits and 20 digits', () {
      expect(validateCard(_luhnComplete('4' * 11)).structureOk, isFalse);
      expect(validateCard(_luhnComplete('4' * 19)).structureOk, isFalse);
    });
  });

  group('name derivation (advisory)', () {
    test('derives the standard four characters', () {
      // GLORIA HERNANDEZ GARCIA -> H E G G
      expect(curpPrefixFromName('GLORIA HERNANDEZ GARCIA'), 'HEGG');
    });

    test('uses X when there is no maternal surname', () {
      expect(curpPrefixFromName('GLORIA HERNANDEZ'), 'HEXG');
    });

    test('skips particles when taking the surname initial', () {
      expect(curpPrefixFromName('JUAN DE LA CRUZ PEREZ'), 'CUPJ');
    });

    test('folds accents but keeps N-tilde distinct', () {
      expect(curpPrefixFromName('JOSÉ MUÑOZ ÁVILA'), 'MUAJ');
      expect(normalise('ÑANDÚ'), 'ÑANDU');
    });

    test('applies the inconvenient-words filter', () {
      // BUENO ELIAS IVAN -> B U E I, which is filtered to B X E I.
      expect(curpPrefixFromName('IVAN BUENO ELIAS'), 'BXEI');
    });

    test('returns null rather than guessing on a single token', () {
      expect(curpPrefixFromName('MADONNA'), isNull);
      expect(curpPrefixFromName(''), isNull);
      expect(curpPrefixFromName('   '), isNull);
    });
  });

  group('cross-checks are advisory', () {
    test('agreeing documents produce no notes', () {
      final curp = _curpWithCheck('HEGG560427MVZRRL0');
      final rfc = _rfcWithCheck('HEGG560427J1');
      expect(crossCheck(curp: curp, rfc: rfc), isEmpty);
    });

    test('a mismatched birth date is reported, not thrown', () {
      final curp = _curpWithCheck('HEGG560427MVZRRL0');
      final rfc = _rfcWithCheck('HEGG990101J1');
      final notes = crossCheck(curp: curp, rfc: rfc);
      expect(notes, isNotEmpty);
      expect(notes.any((n) => n.contains('fecha')), isTrue);
    });

    test('a name that does not derive is hedged, never asserted', () {
      final curp = _curpWithCheck('HEGG560427MVZRRL0');
      final notes = crossCheck(curp: curp, name: 'PEDRO LOPEZ SOSA');
      expect(notes, isNotEmpty);
      expect(notes.first.toLowerCase(), contains('puede ser correcta'),
          reason: 'compound surnames make this rule fail on real people');
    });

    test('an unparseable name yields no opinion at all', () {
      final curp = _curpWithCheck('HEGG560427MVZRRL0');
      expect(crossCheck(curp: curp, name: 'MADONNA'), isEmpty);
    });

    test('never throws on partial or empty input', () {
      expect(() => crossCheck(), returnsNormally);
      expect(() => crossCheck(curp: 'X'), returnsNormally);
      expect(() => crossCheck(rfc: '', name: ''), returnsNormally);
    });
  });
}
