import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/main.dart' show baseUrl;

/// Builds an absolute API URL from a path like '/workers'.
Uri u(String path) => Uri.parse('$baseUrl$path');

/// Headers for the few endpoints that must NOT carry a token: `POST /login`.
///
/// Login deliberately does not use [authHeaders] — a stale token left over from
/// an expired session would be attached to the login request itself. This const
/// exists so that grepping for hand-rolled header maps comes back clean; it is
/// not a general-purpose alternative to [authHeaders].
const Map<String, String> jsonHeaders = {'Content-Type': 'application/json'};

/// Headers for authenticated API calls: reads the login token from secure
/// storage and adds `Authorization: Bearer <token>`. Pass `json: false` for
/// multipart uploads (leaves out the JSON Content-Type).
///
/// Guest mode was removed. A stored value of 'guest' (left over on devices
/// updated from an older build) is treated as "not logged in": no auth header
/// is sent, so the server replies 401 and the app can send the user to login.
Future<Map<String, String>> authHeaders({bool json = true}) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'auth_token');
  return {
    if (json) 'Content-Type': 'application/json',
    if (token != null && token != 'guest') 'Authorization': 'Bearer $token',
  };
}

/// The server's `detail` string, or null when there isn't a usable one.
///
/// Use it as `serverMessage(resp) ?? '<generic fallback>'`. Without it a denied
/// user sees a bare status code: the backend's 403s all read
/// `Solo administradores` and its 400s carry written reasons (the avance cap,
/// the absence-overlap rules), and every one of those was being thrown away.
///
/// **Always `bodyBytes`, never `resp.body`.** Successful responses carry
/// `charset=utf-8`, but FastAPI builds its own JSONResponse for every
/// HTTPException, so error details go out as bare `application/json` — and
/// Dart's http falls back to latin-1 on that. Details are full of accents
/// (`La nota está vacía`, `El avance excede la cantidad del concepto…`), so
/// reading `.body` renders them as mojibake.
///
/// Returns null unless `detail` is a non-empty String. A 422 from FastAPI puts
/// a *list* of field errors there; stringifying that would show the user a Dart
/// list dump, so it falls through to the caller's generic message instead.
///
/// Lives here, not on a screen. Two private copies had already grown — in
/// `screen_absences` and `screen_logbook` — and per-screen network helpers are
/// the pattern that hid missing auth headers across seven files once before.
String? serverMessage(http.Response resp) {
  try {
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    final detail = decoded is Map ? decoded['detail'] : null;
    if (detail is String) {
      final text = detail.trim();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {
    // Not JSON, or not shaped the way we expect — fall back to the caller's
    // generic message rather than showing the user a parse error.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Expired-session handling
// ---------------------------------------------------------------------------

/// Lets [handleUnauthorized] navigate without a BuildContext. Wired up in
/// `main.dart` via `MaterialApp(navigatorKey: navigatorKey, …)`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Single-flight guard. A screen can fire several requests at once (the
/// logbook fires four through `Future.wait`), and on an expired token every
/// one of them comes back 401 — without this they would each push a login
/// route.
bool _redirectingToLogin = false;

/// Clears the stored token and sends the user to /login.
///
/// The token is **deleted**, not set to `'guest'` — that value is a legacy
/// leftover the codebase is retiring. Leaving a dead token in storage would
/// make the redirect cosmetic: every later request would 401 against a token
/// that can never work again.
///
/// Only safe because the API returns 401 exclusively for a missing or invalid
/// token; insufficient permissions come back as 403. If an endpoint ever
/// starts returning 401 for authorization rather than authentication, this
/// will log people out spuriously.
Future<void> handleUnauthorized() async {
  if (_redirectingToLogin) return;
  final nav = navigatorKey.currentState;
  // No navigator yet (a 401 during splash, before MaterialApp is built).
  // Leave the guard down so a later 401 can still redirect.
  if (nav == null) return;
  _redirectingToLogin = true;
  await const FlutterSecureStorage().delete(key: 'auth_token');
  nav.pushNamedAndRemoveUntil('/login', (_) => false);
}

/// Re-arms the guard. Call after a successful login — never on a timer, which
/// would reopen the window for concurrent redirects.
void resetUnauthorizedGuard() => _redirectingToLogin = false;

/// Intercepts every response so an expired session is handled in one place.
///
/// Installed zone-wide by `runWithClient` in `main.dart`, which is why the
/// ~60 call sites can keep using the top-level `http.get`/`http.post`
/// helpers unchanged — and why a call site added later is covered
/// automatically rather than by remembering to opt in.
///
/// `POST /login` is excluded: a 401 there is a wrong password, which the login
/// screen renders inline. Redirecting would bounce the user to the screen they
/// are already on and wipe what they typed.
class AuthClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode == 401 && request.url.path != '/login') {
      await handleUnauthorized();
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
