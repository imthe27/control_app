import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Shared external-app launchers, extracted from screen_worker so screens
// don't grow their own copies (copies silently skip future fixes — same
// lesson as the _authHeaders duplicates removed in the security pass).

/// Launches [uri], telling the user when nothing handled it.
///
/// A failed launch is silent by default — no exception, no visible effect —
/// which is indistinguishable from a dead button. The snackbar is the only
/// thing that makes "no app can open this" legible.
Future<void> launchExternal(
    BuildContext context, Uri uri, String failureMessage) async {
  bool ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(failureMessage)),
  );
}

/// Strips formatting so 'tel:' gets digits only. Keeps a leading + for
/// international numbers.
void dialPhone(BuildContext context, String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) return;
  launchExternal(
      context, Uri(scheme: 'tel', path: digits), 'No se pudo abrir el teléfono');
}

/// Addresses are free text — accents, commas, '#'. Uri.https percent-encodes
/// the query itself, so this must never be built by concatenation.
///
/// The https form is used rather than 'geo:' because it falls back to a
/// browser when no maps app is installed, instead of failing silently.
void openMaps(BuildContext context, String address) {
  final query = address.trim();
  if (query.isEmpty) return;
  launchExternal(
    context,
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    }),
    'No se pudo abrir el mapa',
  );
}
