import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';

/// Admin-only backfill: pick an obra + a PAST date, then mark a crew's
/// attendance for that day. Each worker's record carries this obra, decoupled
/// from their current assignment, so filling history never triggers transfers.
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

  // worker_id -> row {name, status, extra_hours, conflict_project_name}
  final Map<int, Map<String, dynamic>> _rows = {};
  bool _loadingRoster = false;
  bool _saving = false;

  static const _statuses = ['1', '0.5', '0', 'F', 'V', 'I']; // presente/medio/falta/festivo/vacaciones/incap.

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final resp = await http.get(u('/projects'));
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
        'extra_hours': (e.value['extra_hours'] ?? 0),
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

  @override
  Widget build(BuildContext context) {
    final ready = _projectId != null && _date != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('REGISTRO PASADO'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
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
      body: Column(
        children: [
          // ---------- Obra + date pickers ----------
          Container(
            color: const Color(0xFF1C1CF0),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today,
                          size: 16, color: Color(0xFF1C1CF0)),
                      const SizedBox(width: 6),
                      Text(_dateLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1C1CF0))),
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
                    style: TextStyle(color: Colors.grey)))
                : _loadingRoster
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Nadie en esta obra para esa fecha',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addWorker,
                    icon: const Icon(Icons.person_add),
                    label: const Text('AGREGAR TRABAJADOR'),
                  ),
                ],
              ),
            )
                : ListView(
              padding: const EdgeInsets.all(12),
              children: _rows.entries.map((e) {
                final row = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  (row['name'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                      FontWeight.w600)),
                            ),
                            if (row['conflict'] != null)
                              Tooltip(
                                message:
                                'Ya registrado en ${row['conflict']}',
                                child: Icon(Icons.warning_amber,
                                    size: 18,
                                    color: Colors.orange[800]),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: _statuses.map((st) {
                            final sel = row['status'] == st;
                            return ChoiceChip(
                              label: Text(st,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: sel
                                          ? Colors.white
                                          : Colors.black87)),
                              selected: sel,
                              onSelected: (_) => setState(() =>
                              row['status'] =
                              sel ? null : st),
                              selectedColor:
                              const Color(0xFF1C1CF0),
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: (ready && _rows.isNotEmpty)
          ? FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: const Color(0xFF1C1CF0),
        icon: _saving
            ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save, color: Colors.white),
        label: Text(_saving ? 'GUARDANDO...' : 'GUARDAR',
            style: const TextStyle(color: Colors.white)),
      )
          : null,
    );
  }
}