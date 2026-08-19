import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'package:control_app/screens/widgets/attendance_card.dart'
    show kAttendanceBlue;

/// AUSENCIAS — vacaciones (V) e incapacidades (INC).
///
/// This is the ONLY place in the app that creates them. Everywhere else they
/// arrive already merged into the plain `status` field of an attendance read,
/// where they render greyed out and inert; no attendance screen can set one.
///
/// It is also the only place they can be SEEN ahead of time. The daily screen
/// cannot navigate past today and the weekly viewer's picker is capped at
/// today, so an approved vacation that starts next week is invisible
/// everywhere else in the app.
///
/// Creating an absence DELETES the attendance rows it covers, in one server
/// transaction, and deleting the absence does NOT bring them back. That is
/// deliberate — see `create_absence` in the backend — and it is why the create
/// flow always calls the preview endpoint first and shows the real count.

const List<String> _mesesCortos = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
  'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

/// How wide the list looks by default. Forward is deliberately much larger
/// than back: the point of this screen is upcoming vacaciones.
const int _kDiasAtras = 30;
const int _kDiasAdelante = 90;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _fecha(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day} ${_mesesCortos[d.month - 1]} ${d.year}';
}

String _tipoLabel(String t) => t == 'V' ? 'VACACIONES' : 'INCAPACIDAD';
IconData _tipoIcon(String t) => t == 'V' ? Icons.beach_access : Icons.local_hospital;
Color _tipoColor(String t) =>
    t == 'V' ? const Color(0xFFE65100) : const Color(0xFF1565C0);

// ===========================================================================
// List
// ===========================================================================

class AbsencesScreen extends StatefulWidget {
  const AbsencesScreen({super.key});

  @override
  State<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends State<AbsencesScreen> {
  List<Map<String, dynamic>> _absences = [];
  bool _loading = true;
  bool _isAdmin = false;
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: _kDiasAtras)),
      end: now.add(const Duration(days: _kDiasAdelante)),
    );
    _loadMe();
    _load();
  }

  Future<void> _loadMe() async {
    try {
      final resp =
          await http.get(u('/me'), headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      setState(() => _isAdmin = me['is_admin'] == true);
    } catch (_) {
      // Offline or not admin: create/delete stay hidden. The server enforces
      // both regardless — this only decides what is offered.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(
        u('/absences?start_date=${_iso(_range.start)}'
            '&end_date=${_iso(_range.end)}'),
        headers: await authHeaders(json: false),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
        setState(() {
          _absences = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _snack(
            serverMessage(resp) ??
                'Error al cargar ausencias (HTTP ${resp.statusCode})',
            error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Error de red: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(now.year - 2),
      // NOT DateTime.now(). Every other picker in this app caps at today
      // because every other screen records something that already happened.
      // This one has to reach forward: vacaciones are approved in advance, and
      // a picker that cannot select a future date would leave the screen
      // unable to show the records it exists to show.
      lastDate: DateTime(now.year + 2),
      helpText: 'RANGO A MOSTRAR',
      saveText: 'APLICAR',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _openForm() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AbsenceFormScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> a) async {
    final nombre = (a['worker_name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿BORRAR AUSENCIA?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$nombre · ${_tipoLabel((a['type'] ?? '').toString())}'),
            Text('${_fecha(a['start_date'])} — ${_fecha(a['end_date'])}'),
            const SizedBox(height: 12),
            const Text(
              'Esto NO devuelve los registros de asistencia que se borraron al '
              'crearla. Esos días quedan sin marcar y hay que registrarlos de '
              'nuevo a mano.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('BORRAR'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final resp = await http.delete(
        u('/absences/${a['id']}'),
        headers: await authHeaders(json: false),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _snack('Ausencia borrada');
        _load();
      } else {
        _snack(
            serverMessage(resp) ??
                'No se pudo borrar (HTTP ${resp.statusCode})',
            error: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error de red: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grouped on ISO strings rather than DateTime: 'YYYY-MM-DD' sorts and
    // compares correctly as text, and skips every timezone/DST question that
    // comparing a parsed date against DateTime.now() would raise.
    final hoy = _iso(DateTime.now());
    final activas = <Map<String, dynamic>>[];
    final proximas = <Map<String, dynamic>>[];
    final pasadas = <Map<String, dynamic>>[];
    for (final a in _absences) {
      final ini = (a['start_date'] ?? '').toString();
      final fin = (a['end_date'] ?? '').toString();
      if (fin.compareTo(hoy) < 0) {
        pasadas.add(a);
      } else if (ini.compareTo(hoy) > 0) {
        proximas.add(a);
      } else {
        activas.add(a);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AUSENCIAS'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: kAttendanceBlue,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'RANGO',
            icon: const Icon(Icons.date_range, color: Colors.white),
            onPressed: _pickRange,
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: Colors.white,
              foregroundColor: kAttendanceBlue,
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('NUEVA',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kAttendanceBlue, Color(0xFF0000CD)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: InkWell(
                onTap: _pickRange,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_fecha(_iso(_range.start))} — '
                          '${_fecha(_iso(_range.end))}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        children: [
                          ..._section('ACTIVAS HOY', activas),
                          ..._section('PRÓXIMAS', proximas),
                          ..._section('PASADAS', pasadas),
                          if (_absences.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: Text(
                                'No hay ausencias en este rango.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String titulo, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          '$titulo (${items.length})',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),
      ...items.map(_row),
    ];
  }

  Widget _row(Map<String, dynamic> a) {
    final tipo = (a['type'] ?? '').toString();
    final dias = a['days'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: CircleAvatar(
          backgroundColor: _tipoColor(tipo).withValues(alpha: 0.14),
          child: Icon(_tipoIcon(tipo), color: _tipoColor(tipo)),
        ),
        title: Text(
          (a['worker_name'] ?? '').toString().toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${_fecha(a['start_date'])} — ${_fecha(a['end_date'])}'
              '${dias == null ? '' : '  ·  $dias día(s)'}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              // project_name is the obra SNAPSHOT taken when the absence was
              // created, not where the worker sits today. Labelled plainly so
              // a transferred worker's old obra does not read as a bug.
              (a['project_name'] ?? 'SIN OBRA').toString(),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _tipoColor(tipo).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tipo,
                style: TextStyle(
                  color: _tipoColor(tipo),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            if (_isAdmin)
              IconButton(
                tooltip: 'BORRAR',
                icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                onPressed: () => _confirmDelete(a),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Create
// ===========================================================================

class AbsenceFormScreen extends StatefulWidget {
  const AbsenceFormScreen({super.key});

  @override
  State<AbsenceFormScreen> createState() => _AbsenceFormScreenState();
}

class _AbsenceFormScreenState extends State<AbsenceFormScreen> {
  Map<String, dynamic>? _worker;
  String _tipo = 'V';
  DateTimeRange? _range;
  bool _saving = false;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _pickWorker() async {
    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const _WorkerPickerScreen()),
    );
    if (picked != null && mounted) setState(() => _worker = picked);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(now.year - 2),
      // Same reasoning as the list screen: an absence is normally approved
      // before it starts, so this must reach forward.
      lastDate: DateTime(now.year + 2),
      helpText: 'FECHAS DE LA AUSENCIA',
      saveText: 'APLICAR',
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  /// Ask the server what creating this absence would destroy, and make the
  /// admin confirm it before anything is written.
  ///
  /// A separate idempotent GET rather than a dry-run flag on the POST: FastAPI
  /// drops unknown query parameters without error, so a flag that failed to
  /// arrive would turn this check into a live destructive write.
  ///
  /// Returns true if the caller should go ahead.
  Future<bool> _confirmDestruction(int workerId, String ini, String fin) async {
    final resp = await http.get(
      u('/absences/preview?worker_id=$workerId'
          '&start_date=$ini&end_date=$fin'),
      headers: await authHeaders(json: false),
    );
    if (!mounted) return false;
    if (resp.statusCode != 200) {
      _snack(
          serverMessage(resp) ??
              'No se pudo verificar (HTTP ${resp.statusCode})',
          error: true);
      return false;
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final total = (data['attendance_rows'] ?? 0) as int;
    if (total == 0) return true;

    final rows = (data['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final notables = rows.where((r) => r['notable'] == true).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿CONTINUAR?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crear esta ausencia borrará $total registro(s) de asistencia '
                'de ${(data['worker_name'] ?? '').toString()} en ese rango.',
              ),
              if (notables.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'ATENCIÓN: ${notables.length} de ellos tienen horas '
                  'trabajadas, no son marcas por defecto:',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 6),
                ...notables.map((r) {
                  final extra = (r['extra_hours'] ?? 0);
                  final extraTxt =
                      (extra is num && extra > 0) ? '  (+$extra h)' : '';
                  return Text(
                    '• ${_fecha(r['date'])} — ${r['status']}$extraTxt',
                    style: const TextStyle(fontSize: 13),
                  );
                }),
              ],
              const SizedBox(height: 12),
              const Text(
                'Los registros borrados NO se pueden recuperar borrando la '
                'ausencia después.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONTINUAR'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    final worker = _worker;
    final range = _range;
    if (worker == null || range == null) return;

    final ini = _iso(range.start);
    final fin = _iso(range.end);

    setState(() => _saving = true);
    try {
      if (!await _confirmDestruction(worker['id'] as int, ini, fin)) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      final resp = await http.post(
        u('/absences'),
        headers: await authHeaders(),
        body: jsonEncode({
          'worker_id': worker['id'],
          'type': _tipo,
          'start_date': ini,
          'end_date': fin,
          // No project_id: the server snapshots the worker's obra itself.
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final borrados =
            (data['deleted_attendance']?['attendance_rows'] ?? 0) as int;
        // The messenger is grabbed BEFORE the pop. _snack() checks `mounted`,
        // and this widget is unmounted the moment it pops — so calling it
        // afterwards would silently show nothing and the admin would get no
        // confirmation that a destructive write succeeded. The messenger
        // itself lives above this route and outlives the pop.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(borrados == 0
              ? 'Ausencia registrada'
              : 'Ausencia registrada · $borrados registro(s) de asistencia '
                  'borrados'),
        ));
        return;
      }
      setState(() => _saving = false);
      // 409 is the overlap guard, 403 a non-admin, 400 a bad range or type.
      // All four carry accents, which is why serverMessage reads bodyBytes.
      _snack(
          serverMessage(resp) ?? 'No se pudo guardar (HTTP ${resp.statusCode})',
          error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Error de red: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listo = _worker != null && _range != null && !_saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NUEVA AUSENCIA'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: kAttendanceBlue,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kAttendanceBlue, Color(0xFF0000CD)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _campo(
              icono: Icons.person,
              texto: _worker == null
                  ? 'ELEGIR TRABAJADOR'
                  : (_worker!['name'] ?? '').toString().toUpperCase(),
              onTap: _pickWorker,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: _tipoBoton('V')),
                  const SizedBox(width: 10),
                  Expanded(child: _tipoBoton('INC')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _campo(
              icono: Icons.date_range,
              texto: _range == null
                  ? 'ELEGIR FECHAS'
                  : '${_fecha(_iso(_range!.start))} — '
                      '${_fecha(_iso(_range!.end))}'
                      '  ·  ${_range!.duration.inDays + 1} día(s)',
              onTap: _pickRange,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kAttendanceBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: listo ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(
                _saving ? 'GUARDANDO...' : 'GUARDAR',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo({
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icono, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _tipoBoton(String t) {
    final activo = _tipo == t;
    return InkWell(
      onTap: () => setState(() => _tipo = t),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: activo
              ? _tipoColor(t).withValues(alpha: 0.14)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: activo ? _tipoColor(t) : Colors.grey.shade300,
            width: activo ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(_tipoIcon(t),
                color: activo ? _tipoColor(t) : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text(
              _tipoLabel(t),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: activo ? _tipoColor(t) : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Worker picker
// ===========================================================================

/// Every worker, company-wide, with a search box and obra chips.
///
/// Deliberately NOT scoped to one obra first. An absence is a worker-level
/// record and its obra is a snapshot the SERVER takes at creation — the form
/// never sends a project_id — so making the admin pick an obra first would be a
/// required step that does not correspond to anything being created, and it can
/// hide the worker they are looking for.
class _WorkerPickerScreen extends StatefulWidget {
  const _WorkerPickerScreen();

  @override
  State<_WorkerPickerScreen> createState() => _WorkerPickerScreenState();
}

class _WorkerPickerScreenState extends State<_WorkerPickerScreen> {
  static const String _todas = 'TODAS';

  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;
  String _query = '';
  String _obra = _todas;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp =
          await http.get(u('/workers'), headers: await authHeaders(json: false));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
        setState(() {
          _workers = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar trabajadores '
                  '(HTTP ${resp.statusCode})'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final obras = <String>{
      for (final w in _workers) (w['project'] ?? 'SIN OBRA').toString()
    }.toList()
      ..sort();

    final q = _query.trim().toLowerCase();
    final visibles = _workers.where((w) {
      final nombre = (w['name'] ?? '').toString().toLowerCase();
      final obra = (w['project'] ?? 'SIN OBRA').toString();
      if (_obra != _todas && obra != _obra) return false;
      return q.isEmpty || nombre.contains(q);
    }).toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('TRABAJADOR'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: kAttendanceBlue,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kAttendanceBlue, Color(0xFF0000CD)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'BUSCAR',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (obras.length > 1)
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [_todas, ...obras].map((o) {
                    final activo = _obra == o;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(o,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color:
                                    activo ? Colors.white : kAttendanceBlue)),
                        selected: activo,
                        selectedColor: const Color(0xFF0000CD),
                        backgroundColor: Colors.white,
                        onSelected: (_) => setState(() => _obra = o),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: visibles.length,
                      itemBuilder: (_, i) {
                        final w = visibles[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(
                              (w['name'] ?? '').toString().toUpperCase(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              (w['project'] ?? 'SIN OBRA').toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => Navigator.pop(context, w),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
