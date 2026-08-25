/// Structure and check-digit validation for the Mexican identity documents the
/// worker form scans: CURP, RFC, NSS, CLABE and card numbers.
///
/// **No Flutter import, and there must never be one.** This is where the
/// correctness of the document scanner lives, and it is the only part of the
/// feature that can be exercised without a camera. Keeping it UI-free is what
/// makes `test/document_validators_test.dart` possible.
///
/// Two principles run through the whole file:
///
/// 1. **The check digit is authoritative; every structural rule is advisory.**
///    The tables here — state codes, the name-derivation rule, the inconvenient
///    -words filter — are reconstructions of RENAPO/SAT behaviour and are
///    certainly incomplete. A real person whose document disagrees with one of
///    these tables must still be accepted if the check digit verifies. Getting
///    this backwards means rejecting valid workers, which is far worse than
///    accepting a typo the user can see and correct.
///
/// 2. **"Valid" means well-formed, never "belongs to this worker".** A check
///    digit proves a CURP is internally consistent. It proves nothing about
///    whose it is. No function here returns anything the UI may present as
///    "verified".
library;

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// One field read off a document.
class DocField {
  /// Normalised value: uppercased, accent-folded, OCR-coerced by position.
  final String value;

  /// The raw text as OCR produced it, before coercion. Kept so the review sheet
  /// can show what was actually on the page when a value looks surprising.
  final String raw;

  /// Structure matches the document's layout.
  final bool structureOk;

  /// Check digit verifies. `null` when the field has no check digit.
  final bool? checkDigitOk;

  /// Advisory notes — a state code not in our table, a name that does not derive
  /// to the CURP prefix. Never a reason to reject.
  final List<String> notes;

  const DocField({
    required this.value,
    required this.raw,
    required this.structureOk,
    this.checkDigitOk,
    this.notes = const [],
  });

  /// Whether the review sheet may pre-tick this field.
  ///
  /// **Only a verified check digit earns a tick.** A field that is merely
  /// well-shaped arrives unticked and the user confirms it by hand, because
  /// structure alone does not distinguish a correct read from a plausible
  /// misread — `5` and `S` produce equally well-shaped nonsense.
  bool get preTicked => structureOk && checkDigitOk == true;

  @override
  String toString() =>
      'DocField($value, structure=$structureOk, check=$checkDigitOk, '
      'notes=${notes.length})';
}

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

const Map<String, String> _foldAccents = {
  'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A',
  'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
  'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O',
  'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
};

/// Uppercases and strips accents, **keeping `Ñ`**.
///
/// `Ñ` is a distinct letter in both the CURP and RFC alphabets — it has its own
/// value in the RFC check-digit table (38) — so folding it to `N` would corrupt
/// the arithmetic, not just the spelling.
String normalise(String s) {
  final upper = s.toUpperCase();
  final buf = StringBuffer();
  for (final ch in upper.split('')) {
    buf.write(_foldAccents[ch] ?? ch);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Positional OCR coercion
// ---------------------------------------------------------------------------

/// Glyphs OCR reads as a letter when the slot must hold a digit.
const Map<String, String> _asDigit = {
  'O': '0', 'I': '1', 'Z': '2', 'S': '5', 'B': '8',
};

/// The same confusions inverted, for slots that must hold a letter.
const Map<String, String> _asLetter = {
  '0': 'O', '1': 'I', '2': 'Z', '5': 'S', '8': 'B',
};

/// Layout mask for positional coercion. `D` = digit, `L` = letter,
/// `?` = either, leave alone.
///
/// CURP and RFC have fixed letters-then-digits layouts, so a misread is
/// correctable by position: an `O` sitting in a date slot is a `0`, with no
/// ambiguity to resolve. Doing this *before* validating turns most failed reads
/// into successful ones and costs nothing — the check digit still has to pass
/// afterwards, so a wrong coercion cannot smuggle a bad value through.
String coerceByMask(String input, String mask) {
  final s = normalise(input);
  if (s.length != mask.length) return s;
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    switch (mask[i]) {
      case 'D':
        buf.write(_asDigit[ch] ?? ch);
      case 'L':
        buf.write(_asLetter[ch] ?? ch);
      default:
        buf.write(ch);
    }
  }
  return buf.toString();
}

/// Digits only, with letter-shaped digits recovered first.
///
/// For NSS, CLABE and card numbers every character is a digit, so coercion is
/// unconditional and anything still non-numeric afterwards is real noise —
/// spaces, dashes and the label text OCR swept up with the number.
String digitsOnly(String input) {
  final s = normalise(input);
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final c = _asDigit[ch] ?? ch;
    if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) buf.write(c);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// CURP
// ---------------------------------------------------------------------------

/// RENAPO's alphabet for the CURP check digit. Position in this string IS the
/// character's value, so `Ñ` sitting between `N` and `O` is load-bearing.
const String _curpAlphabet = '0123456789ABCDEFGHIJKLMNÑOPQRSTUVWXYZ';

/// `LLLLDDDDDDLLLLLL??` — 4 letters, YYMMDD, sex, 2-letter state, 3 consonants,
/// then the differentiator and check digit, which are deliberately `?`.
///
/// **Position 17 is not always a letter.** It is a digit for births before 2000
/// and a letter from 2000 onward, so a naive `^[A-Z]{18}$` — or coercing that
/// slot to a letter — fails for roughly everyone over 26. Position 18 is always
/// a digit but is left uncoerced too, so that a misread there fails the check
/// digit loudly instead of being silently "repaired" into a different valid-
/// looking CURP.
const String curpMask = 'LLLLDDDDDDLLLLLL??';

/// The 32 state codes plus `NE` (nacido en el extranjero).
const Set<String> _curpStates = {
  'AS', 'BC', 'BS', 'CC', 'CL', 'CM', 'CS', 'CH', 'DF', 'DG', 'GT', 'GR',
  'HG', 'JC', 'MC', 'MN', 'MS', 'NT', 'NL', 'OC', 'PL', 'QT', 'QR', 'SP',
  'SL', 'SR', 'TC', 'TS', 'TL', 'VZ', 'YN', 'ZS', 'NE',
};

bool _isUpperLetter(String c) {
  if (c == 'Ñ') return true;
  final u = c.codeUnitAt(0);
  return u >= 65 && u <= 90;
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

/// Expected check digit for an 18-char CURP, or `null` if a character is
/// outside the alphabet.
int? curpCheckDigit(String curp) {
  if (curp.length != 18) return null;
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    final idx = _curpAlphabet.indexOf(curp[i]);
    if (idx < 0) return null;
    sum += idx * (18 - i);
  }
  final d = 10 - (sum % 10);
  return d == 10 ? 0 : d;
}

/// Validates a scanned CURP, coercing by position first.
DocField validateCurp(String raw) {
  final value = coerceByMask(raw, curpMask);
  final notes = <String>[];

  if (value.length != 18) {
    return DocField(
      value: value,
      raw: raw,
      structureOk: false,
      notes: ['La CURP debe tener 18 caracteres; se leyeron ${value.length}.'],
    );
  }

  var structureOk = true;
  for (var i = 0; i < 4; i++) {
    if (!_isUpperLetter(value[i])) structureOk = false;
  }
  for (var i = 4; i < 10; i++) {
    if (!_isDigit(value[i])) structureOk = false;
  }
  if (value[10] != 'H' && value[10] != 'M') structureOk = false;
  for (var i = 11; i < 16; i++) {
    if (!_isUpperLetter(value[i])) structureOk = false;
  }
  // Position 17 (index 16): digit before 2000, letter from 2000 on. Both are
  // structurally correct; neither is coerced.
  if (!_isUpperLetter(value[16]) && !_isDigit(value[16])) structureOk = false;
  if (!_isDigit(value[17])) structureOk = false;

  // Advisory only: if our table is missing a code, the check digit still
  // decides. A hard rejection here would reject a real person over a table.
  final state = value.substring(11, 13);
  if (!_curpStates.contains(state)) {
    notes.add('Código de estado «$state» no reconocido. Verifica la CURP.');
  }

  final expected = curpCheckDigit(value);
  final checkOk = expected != null && '$expected' == value[17];
  if (!checkOk) {
    notes.add('El dígito verificador no coincide.');
  }

  return DocField(
    value: value,
    raw: raw,
    structureOk: structureOk,
    checkDigitOk: checkOk,
    notes: notes,
  );
}

// ---------------------------------------------------------------------------
// RFC (persona física, 13 characters)
// ---------------------------------------------------------------------------

/// SAT's value table for the RFC check character. Position is the value, so
/// `&` at 24 sits between `N` and `O`; space (37) and `Ñ` (38) are handled
/// separately because they fall outside this string.
const String _rfcAlphabet = '0123456789ABCDEFGHIJKLMN&OPQRSTUVWXYZ';

int _rfcValue(String c) {
  if (c == ' ') return 37;
  if (c == 'Ñ') return 38;
  return _rfcAlphabet.indexOf(c);
}

/// `LLLLDDDDDD???` — 4 letters, YYMMDD, then a 3-character homoclave that is
/// alphanumeric and must not be coerced either way.
const String rfcMask = 'LLLLDDDDDD???';

/// Expected final character of a 13-character RFC, or `null` on a bad input.
///
/// Personas físicas only. A persona moral RFC is 12 characters and is padded
/// with a leading space before the same arithmetic — not implemented, because
/// this scans workers' documents and a worker is never a company.
String? rfcCheckChar(String rfc) {
  if (rfc.length != 13) return null;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final v = _rfcValue(rfc[i]);
    if (v < 0) return null;
    sum += v * (13 - i);
  }
  final rem = sum % 11;
  if (rem == 0) return '0';
  if (rem == 1) return 'A';
  return '${11 - rem}';
}

DocField validateRfc(String raw) {
  final value = coerceByMask(raw, rfcMask);
  final notes = <String>[];

  if (value.length != 13) {
    return DocField(
      value: value,
      raw: raw,
      structureOk: false,
      notes: [
        'El RFC de una persona física tiene 13 caracteres; '
            'se leyeron ${value.length}.'
      ],
    );
  }

  var structureOk = true;
  for (var i = 0; i < 4; i++) {
    if (!_isUpperLetter(value[i])) structureOk = false;
  }
  for (var i = 4; i < 10; i++) {
    if (!_isDigit(value[i])) structureOk = false;
  }

  final expected = rfcCheckChar(value);
  final checkOk = expected != null && expected == value[12];
  if (!checkOk) notes.add('El carácter verificador no coincide.');

  return DocField(
    value: value,
    raw: raw,
    structureOk: structureOk,
    checkDigitOk: checkOk,
    notes: notes,
  );
}

// ---------------------------------------------------------------------------
// Luhn — NSS and card numbers
// ---------------------------------------------------------------------------

bool luhnOk(String digits) {
  if (digits.isEmpty) return false;
  var sum = 0;
  var alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    final u = digits.codeUnitAt(i);
    if (u < 48 || u > 57) return false;
    var d = u - 48;
    if (alt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    alt = !alt;
  }
  return sum % 10 == 0;
}

/// NSS: 11 digits, Luhn over all 11.
DocField validateNss(String raw) {
  final value = digitsOnly(raw);
  if (value.length != 11) {
    return DocField(
      value: value,
      raw: raw,
      structureOk: false,
      notes: ['El NSS tiene 11 dígitos; se leyeron ${value.length}.'],
    );
  }
  final ok = luhnOk(value);
  return DocField(
    value: value,
    raw: raw,
    structureOk: true,
    checkDigitOk: ok,
    notes: ok ? const [] : const ['El dígito verificador no coincide.'],
  );
}

/// Card number: 13–19 digits, Luhn.
///
/// ⚠ The form's `NÚMERO DE TARJETA` field carries `maxLen: 16`, so a valid
/// 17–19 digit card cannot be typed into it and must not be applied to it
/// either. That is a pre-existing limit, not introduced here; card scanning is
/// deferred, and this validator exists so the limit is a deliberate decision
/// when it stops being deferred.
DocField validateCard(String raw) {
  final value = digitsOnly(raw);
  if (value.length < 13 || value.length > 19) {
    return DocField(
      value: value,
      raw: raw,
      structureOk: false,
      notes: [
        'Un número de tarjeta tiene entre 13 y 19 dígitos; '
            'se leyeron ${value.length}.'
      ],
    );
  }
  final ok = luhnOk(value);
  final notes = <String>[];
  if (!ok) notes.add('El dígito verificador no coincide.');
  if (value.length > 16) {
    notes.add('El campo del formulario acepta 16 dígitos como máximo.');
  }
  return DocField(
    value: value,
    raw: raw,
    structureOk: true,
    checkDigitOk: ok,
    notes: notes,
  );
}

// ---------------------------------------------------------------------------
// CLABE
// ---------------------------------------------------------------------------

/// CLABE: 18 digits, weighted mod-10 with the weights 3, 7, 1 repeating.
///
/// Each weighted product is reduced mod 10 *before* summing — that is the part
/// people get wrong, and getting it wrong still validates roughly one CLABE in
/// ten by coincidence, which is worse than failing outright.
DocField validateClabe(String raw) {
  final value = digitsOnly(raw);
  if (value.length != 18) {
    return DocField(
      value: value,
      raw: raw,
      structureOk: false,
      notes: ['La CLABE tiene 18 dígitos; se leyeron ${value.length}.'],
    );
  }
  const weights = [3, 7, 1];
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += ((value.codeUnitAt(i) - 48) * weights[i % 3]) % 10;
  }
  final expected = (10 - (sum % 10)) % 10;
  final ok = expected == value.codeUnitAt(17) - 48;
  return DocField(
    value: value,
    raw: raw,
    structureOk: true,
    checkDigitOk: ok,
    notes: ok ? const [] : const ['El dígito verificador no coincide.'],
  );
}

// ---------------------------------------------------------------------------
// Name derivation — ADVISORY ONLY
// ---------------------------------------------------------------------------

/// Particles skipped when taking the first letter of a surname.
const Set<String> _particles = {
  'DE', 'DEL', 'LA', 'LAS', 'LOS', 'Y', 'MC', 'MAC', 'VON', 'VAN',
};

/// RENAPO replaces position 2 with `X` when the first four letters spell
/// something obscene. This list is the well-known subset and is **certainly
/// incomplete** — which is fine, because everything it feeds is advisory. A
/// missing entry produces a spurious warning, never a rejection.
const Set<String> _inconvenient = {
  'BACA', 'BAKA', 'BUEI', 'BUEY', 'CACA', 'CACO', 'CAGA', 'CAGO', 'CAKA',
  'CAKO', 'COGE', 'COGI', 'COJA', 'COJE', 'COJI', 'COJO', 'COLA', 'CULO',
  'FALO', 'FETO', 'GETA', 'GUEI', 'GUEY', 'JOTO', 'KACA', 'KACO', 'KAGA',
  'KAGO', 'KAKA', 'KAKO', 'KOGE', 'KOGI', 'KOJA', 'KOJE', 'KOJI', 'KOJO',
  'KOLA', 'KULO', 'LILO', 'LOCA', 'LOCO', 'LOKA', 'LOKO', 'MAME', 'MAMO',
  'MEAR', 'MEAS', 'MEON', 'MIAR', 'MION', 'MOCO', 'MOKO', 'MULA', 'MULO',
  'NACA', 'NACO', 'PEDA', 'PEDO', 'PENE', 'PIPI', 'PITO', 'POPO', 'PUTA',
  'PUTO', 'QULO', 'RATA', 'ROBA', 'ROBE', 'ROBO', 'RUIN', 'SENO', 'TETA',
  'VACA', 'VAGA', 'VAGO', 'VAKA', 'VUEI', 'VUEY', 'WUEI', 'WUEY',
};

const Set<String> _vowels = {'A', 'E', 'I', 'O', 'U'};

String _firstInternalVowel(String word) {
  for (var i = 1; i < word.length; i++) {
    if (_vowels.contains(word[i])) return word[i];
  }
  return 'X';
}

List<String> _words(String s) => normalise(s)
    .split(RegExp(r'[^A-ZÑ]+'))
    .where((w) => w.isNotEmpty && !_particles.contains(w))
    .toList();

/// Derives the first four CURP characters from a full name.
///
/// ⚠ **Advisory. This must never block or reject anything.** The rule has real
/// exceptions the code cannot see: compound surnames, a missing maternal
/// surname (position 3 becomes `X`), `Ñ` handling, and RENAPO's inconvenient-
/// words filter. On top of that the form stores one free-text
/// `NOMBRE COMPLETO`, so which tokens are surnames is a guess — this assumes
/// the Mexican convention of given names first, then paternal, then maternal.
/// A person who entered their name in another order will disagree with their
/// own real CURP.
///
/// Returns `null` when the name cannot be split at all, which callers must
/// treat as "no opinion", not as a mismatch.
String? curpPrefixFromName(String fullName) {
  final w = _words(fullName);
  if (w.length < 2) return null;

  final String paternal;
  final String maternal;
  final String given;
  if (w.length == 2) {
    // One surname only — position 3 becomes X, as for a person registered
    // without a maternal surname.
    given = w[0];
    paternal = w[1];
    maternal = '';
  } else {
    given = w[0];
    paternal = w[w.length - 2];
    maternal = w[w.length - 1];
  }

  final p1 = paternal[0];
  final p2 = _firstInternalVowel(paternal);
  final p3 = maternal.isEmpty ? 'X' : maternal[0];
  final p4 = given[0];

  final candidate = '$p1$p2$p3$p4';
  return _inconvenient.contains(candidate) ? '${p1}X$p3$p4' : candidate;
}

// ---------------------------------------------------------------------------
// Cross-checks — ALL ADVISORY
// ---------------------------------------------------------------------------

/// Compares the fields two documents share. Every result is a note for the
/// review sheet to show; none of them may gate applying a value.
///
/// `CURP[0:4]` and `RFC[0:4]` come from the same name rule, and `CURP[4:10]`
/// and `RFC[4:10]` are both YYMMDD, so a disagreement usually means one of the
/// two was misread — useful to surface, never sufficient to reject, since a
/// legitimately unusual registration can differ.
List<String> crossCheck({String? curp, String? rfc, String? name}) {
  final notes = <String>[];

  if (curp != null && rfc != null && curp.length == 18 && rfc.length == 13) {
    if (curp.substring(0, 4) != rfc.substring(0, 4)) {
      notes.add('Las primeras 4 letras de la CURP y el RFC no coinciden.');
    }
    if (curp.substring(4, 10) != rfc.substring(4, 10)) {
      notes.add('La fecha de nacimiento en la CURP y el RFC no coincide.');
    }
  }

  if (name != null && name.trim().isNotEmpty) {
    final derived = curpPrefixFromName(name);
    if (derived != null) {
      if (curp != null && curp.length >= 4 && curp.substring(0, 4) != derived) {
        notes.add('La CURP no coincide con el nombre capturado. '
            'Puede ser correcta: apellidos compuestos y otros casos no siguen '
            'la regla.');
      }
      if (rfc != null && rfc.length >= 4 && rfc.substring(0, 4) != derived) {
        notes.add('El RFC no coincide con el nombre capturado. '
            'Puede ser correcto.');
      }
    }
  }

  return notes;
}
