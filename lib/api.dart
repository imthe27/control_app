import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
