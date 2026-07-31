import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';

/// The role stored for a worker who has none. Migration phase 11 replaced
/// every empty role with this, and the server coerces ''/NULL to it on write,
/// so it is a real value rather than a display placeholder — it appears in
/// GET /worker-roles like any other and must not be special-cased out.
const String kUnassignedRole = 'SIN ASIGNAR';

/// Distinct roles for the worker-form dropdown and the personnel filter.
///
/// Shared so both screens parse one shape. GET /worker-roles returns a bare
/// JSON array of strings, already sorted server-side.
Future<List<String>> fetchWorkerRoles() async {
  final resp = await http.get(
    u('/worker-roles'),
    headers: await authHeaders(json: false),
  );
  if (resp.statusCode != 200) return const [];
  final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  return data.map((e) => e.toString()).toList();
}

/// Uppercase, trim, and collapse internal whitespace runs to a single space.
///
/// This is the ONLY defence against role drift. The stored data is clean —
/// the 2026-07-30 audit found no case, accent or spacing variants — and the
/// free-text "add a role" field is exactly where the next `'Oficial
/// Soldador '` would come from. Same bug class as the double-space name
/// crash already fixed in the worker form.
///
/// Always normalize BEFORE comparing against the existing list, or `'oficial '`
/// becomes a second OFICIAL.
String normalizeRole(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
