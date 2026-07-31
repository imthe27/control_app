import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'package:control_app/screens/widgets/attendance_card.dart';

/// Admin-only backfill: pick an obra + a PAST date, then mark a crew's
/// attendance for that day. Each worker's record carries this obra, decoupled
/// from their current assignment, so filling history never triggers transfers.
///
/// Shares the daily screen's card design but NOT its past-day rules. The daily
/// screen is read-only for past days and points people here; writing past days
/// is this screen's entire purpose.
///
/// The roster is also its own: GET /attendance/backfill-roster returns the crew
/// AS OF that date, so a worker who has since been transferred is not silently
/// recorded against the obra they sit on today.
class BackfillAttendanceScreen extends StatefulWidget {
  const BackfillAttendanceScreen({super.key});

  @override
  State<BackfillAttendanceScreen> createState() =>
      _BackfillAttendanceScreenState();
}

class _BackfillAttendanceScreenState extends State<BackfillAttendanceScreen> {
  List<Map<String, dynamic>> _projects = [];
  int? _projectId;
  DateTime? _date;

  // worker_id -> row {name, status, extra_hours, conflict}
  final Map<int, Map<String, dynamic>> _rows = {};
  bool _loadingRoster = false;
  bool _saving = false;

  /// presente / medio día / falta / festivo.
  ///
  /// V (vacaciones) and I (incapacidad) are deliberately absent: nothing in the
  /// app sets them any more. Rows that already carry one still render, greyed
  /// out and inert, the same as on the daily screen.
  static const _statuses = ['1', '0.5', '0', 'F'];

  /// Statuses that can carry extra hours.
  static const _hourlyStatuses = {'1', '0.5'};

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final resp = await http.get(u('/projects'),
          headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      setState(() => _projects = List<Map<String, dynamic>>.from(
          jsonDecode(utf8.decode(resp.bodyBytes))));
    } catch (_) {}
  }

  String get _dateStr {
    final d = _date!;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    final d = _date;
    if (d == null) return 'ELEGIR FECHA';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.subtract(const Duration(days: 1)),
      firstDate: DateTime(now.year - 2),
      lastDate: now, // no future backfill
      helpText: 'FECHA A REGISTRAR',
    );
    if (picked != null) {
      setState(() => _date = picked);
      if (_projectId != null) _loadRoster();
    }
  }

  Future<void> _loadRoster() async {
    if (_projectId == null || _date == null) return;
    setState(() {
      _loadingRoster = true;
      _rows.clear();
    });
    try {
      final resp = await http.get(
          u('/attendance/backfill-roster/$_projectId/$_dateStr'),
          headers: await authHeaders(json: false));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final list = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
        setState(() {
          for (final w in list) {
            _rows[w['id']] = {
              'name': w['name'],
              // Prefill saved status for THIS obra, else blank (untouched)
              'status': w['status'],
              'extra_hours': w['extra_hours'] ?? 0,
              'conflict': w['conflict_project_name'],
            };
          }
          _loadingRoster = false;
        });
      } else {
        setState(() => _loadingRoster = false);
        _snack('No se pudo cargar la lista (HTTP ${resp.statusCode})',
            error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRoster = false);
        _snack('Error: $e', error: true);
      }
    }
  }

  Future<void> _addWorker() async {
    // Search over ALL workers and add anyone not already listed
    List<Map<String, dynamic>> all = [];
    String? loadError;
    try {
      final resp = await http.get(
        u('/workers?active_only=false'),
        headers: await authHeaders(json: false),
      );
      if (resp.statusCode == 200) {
        all = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
      } else {
        loadError = 'No se pudo cargar la lista (HTTP ${resp.statusCode})';
      }
    } catch (e) {
      loadError = 'Error de red al cargar la lista';
    }
    if (!mounted) return;
    // Surface the failure instead of opening an empty picker.
    if (loadError != null) {
      _snack(loadError, error: true);
      return;
    }

    String query = '';
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final visible = all
              .where((w) =>
          !_rows.containsKey(w['id']) &&
              (query.isEmpty ||
                  (w['name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(query.toLowerCase())))
              .toList();
          return AlertDialog(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('AGREGAR TRABAJADOR'),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setModal(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: visible
                          .map((w) => ListTile(
                        dense: true,
                        title: Text((w['name'] ?? '').toString(),
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                            (w['project'] ?? '').toString(),
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, w),
                      ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CERRAR')),
            ],
          );
        },
      ),
    );
    if (picked != null) {
      setState(() {
        _rows[picked['id']] = {
          'name': picked['name'],
          'status': null,
          'extra_hours': 0,
          'conflict': null, // roster endpoint knows conflicts; manual adds re-check on save
        };
      });
    }
  }

  Future<void> _save() async {
    // Only send rows the admin actually marked (status != null)
    final marked = _rows.entries
        .where((e) => e.value['status'] != null)
        .toList();
    if (marked.isEmpty) {
      _snack('No has marcado a nadie');
      return;
    }

    // Warn once if any marked worker has a conflicting record on another obra
    final conflicts = marked.where((e) => e.value['conflict'] != null).toList();
    if (conflicts.isNotEmpty) {
      final names = conflicts
          .map((e) => '• ${e.value['name']} (en ${e.value['conflict']})')
          .join('\n');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('¿SOBRESCRIBIR?'),
          content: Text(
              'Estos trabajadores ya tienen asistencia el $_dateLabel en otra obra. '
                  'Guardar los moverá a esta obra ese día:\n\n$names'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SOBRESCRIBIR'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final records = marked
          .map((e) => {
        'worker_id': e.key,
        'project_id': _projectId,
        'date': _dateStr,
        'status': e.value['status'],
        // The hours strip reports strings ('2.0'); the roster returns
        // numbers. Normalise so the endpoint always receives a number.
        'extra_hours':
        double.tryParse((e.value['extra_hours'] ?? 0).toString()) ?? 0.0,
      })
          .toList();
      final resp = await http.post(
        u('/attendance/'),
        headers: await authHeaders(),
        body: jsonEncode(records),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _snack('${records.length} registro(s) guardados');
        _loadRoster(); // refresh: conflicts clear, statuses now saved here
      } else {
        setState(() => _saving = false);
        _snack('Error al guardar (HTTP ${resp.statusCode})', error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Error: $e', error: true);
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  /// One worker, in the daily screen's card design. The roster carries no
  /// photo, so these always show initials.
  Widget _buildCard(int workerId, Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString();
    final status = row['status']?.toString();
    final special = isSpecialAttendanceStatus(status);
    final hours = (row['extra_hours'] ?? 0).toString();
    final conflict = row['conflict'];

    return Container(
      // Keyed by worker so the hours strip's scroll position follows its own
      // worker when the roster changes, instead of being matched by position.
      key: ValueKey(workerId),
      decoration: attendanceCardDecoration(special),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 2,
                child: AttendancePhotoHeader(
                  photoUrl: null,
                  initials: attendanceInitials(name),
                ),
              ),
              Expanded(
                flex: 1,
                child: AttendanceNameBlock(name: name),
              ),
              Expanded(
                flex: 1,
                child: _StatusSegments(
                  value: status,
                  options: _statuses,
                  enabled: !special,
                  onChanged: (v) => setState(() {
                    row['status'] = v;
                    if (!_hourlyStatuses.contains(v)) row['extra_hours'] = 0;
                  }),
                ),
              ),
              Expanded(
                flex: 1,
                child: AttendanceHoursStrip(
                  value: hours,
                  enabled: !special && _hourlyStatuses.contains(status),
                  isSpecial: special,
                  onChanged: (h) => setState(() => row['extra_hours'] = h),
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            child: AttendancePresentBadge(isPresent: status == '1'),
          ),
          if (conflict != null)
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Ya registrado en $conflict',
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange[800],
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.warning_amber,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          if (special) AttendanceStatusWatermark(status: status!),
        ],
      ),
    );
  }

  /// Sits at the end of the scrolling list, below the crew — the user scrolls
  /// past everyone to reach it, which is the point: you see who you are about
  /// to save for.
  Widget _buildSaveFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: kAttendanceBlue,
            disabledBackgroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(kAttendanceBlue),
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            _saving ? 'GUARDANDO...' : 'GUARDAR',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildRoster() {
    final entries = _rows.entries.toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              // Taller than the daily card: this one carries a status row the
              // daily screen does not have.
              childAspectRatio: 0.56,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final e = entries[index];
                return _buildCard(e.key, e.value);
              },
              childCount: entries.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildSaveFooter()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _projectId != null && _date != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('REGISTRO PASADO'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: kAttendanceBlue,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (ready && _rows.isNotEmpty)
            IconButton(
              tooltip: 'AGREGAR TRABAJADOR',
              icon: const Icon(Icons.person_add, color: Colors.white),
              onPressed: _addWorker,
            ),
        ],
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
            // ---------- Obra + date pickers ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _projectId,
                          isExpanded: true,
                          hint: const Text('OBRA'),
                          items: _projects
                              .map((p) => DropdownMenuItem<int>(
                            value: p['id'],
                            child: Text((p['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _projectId = v);
                            if (_date != null) _loadRoster();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: kAttendanceBlue),
                        const SizedBox(width: 6),
                        Text(_dateLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kAttendanceBlue)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Roster ----------
            Expanded(
              child: !ready
                  ? const Center(
                      child: Text('Elige una obra y una fecha',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16)))
                  : _loadingRoster
                      ? const Center(
                          child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.yellow)))
                      : _rows.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.people_outline,
                                      size: 64, color: Colors.white70),
                                  const SizedBox(height: 16),
                                  const Text(
                                      'NADIE EN ESTA OBRA PARA ESA FECHA',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16)),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                          color: Colors.white70),
                                    ),
                                    onPressed: _addWorker,
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('AGREGAR TRABAJADOR'),
                                  ),
                                ],
                              ),
                            )
                          : _buildRoster(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact status picker sized for a grid card.
///
/// The daily screen toggles between two states on tap; backfill needs four,
/// plus "not marked at all" — no segment selected. That null is what keeps an
/// untouched worker out of the save, so tapping the selected segment clears it
/// rather than leaving the row stuck on a value nobody chose.
class _StatusSegments extends StatelessWidget {
  final String? value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _StatusSegments({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: options.map((opt) {
          final selected = value == opt;
          return Expanded(
            child: GestureDetector(
              onTap: enabled ? () => onChanged(selected ? null : opt) : null,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: selected ? kAttendanceBlue : Colors.white,
                  border: Border.all(
                    color: selected ? Colors.yellow : Colors.grey[300]!,
                    width: selected ? 1.5 : 0.5,
                  ),
                ),
                child: Center(
                  // Keeps '0.5' legible when the system font scale is large,
                  // instead of overflowing a fixed-width segment.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        opt,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
