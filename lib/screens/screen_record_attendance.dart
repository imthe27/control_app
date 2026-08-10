import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'package:control_app/screens/widgets/attendance_card.dart';

class RecordAttendanceScreen extends StatefulWidget {
  final int projectId;

  const RecordAttendanceScreen({super.key, required this.projectId});

  @override
  State<RecordAttendanceScreen> createState() => _RecordAttendanceScreenState();
}

class _RecordAttendanceScreenState extends State<RecordAttendanceScreen> {
  DateTime selectedDate = DateTime.now();
  final Map<String, Map<String, String>> allAttendance = {};
  final Map<String, Map<String, String>> allExtras = {};
  List<Map<String, dynamic>> selectedWorkers = [];
  List<Map<String, dynamic>> allWorkers = [];
  int get currentProjectId => widget.projectId;
  bool isSaving = false;
  bool isLoading = true;

  /// Past days are read-only: this screen becomes an attendance viewer.
  /// Editing history goes through REGISTRO PASADO (backfill), which warns
  /// about cross-obra overwrites; this one does not.
  bool get _isPastDay {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    return sel.isBefore(today);
  }

  @override
  void initState() {
    super.initState();
    refreshWorkers();
    loadAttendanceForDate();
  }

  Future<void> refreshWorkers() async {
    try {
      final resp = await http.get(
        u('/workers'),
        headers: await authHeaders(json: false),
      );

      final ct = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200) {
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workers HTTP ${resp.statusCode}')),
        );
        return;
      }
      if (!ct.contains('application/json')) {
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Respuesta no JSON (¿HTML/login?)')),
        );
        return;
      }

      final List<dynamic> raw = jsonDecode(resp.body);
      final List<Map<String, dynamic>> list =
      raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();

      for (final w in list) {
        final v = w['project_id'];
        int? pid;
        if (v == null) {
          pid = null;
        } else if (v is num) {
          pid = v.toInt();
        } else if (v is String) {
          pid = int.tryParse(v);
        }
        w['project_id'] = pid;
      }

      final int pidCurrent = currentProjectId;
      final filtered = list.where((w) => (w['project_id'] as int?) == pidCurrent).toList()
        ..sort((a, b) => (a['name'] ?? '').toString().toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));

      if (!mounted) return;
      setState(() {
        allWorkers = list;
        selectedWorkers = filtered;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red/parseo: $e')),
      );
    }
  }

  Future<void> loadAttendanceForDate() async {
    final formattedDate =
        "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    final resp = await http.get(
      u('/attendance/$currentProjectId/$formattedDate'),
      headers: await authHeaders(json: false),
    );

    if (resp.statusCode == 200 && (resp.headers['content-type'] ?? '').contains('application/json')) {
      final List<dynamic> data = jsonDecode(resp.body);
      final Map<String, String> daily = {
        for (final row in data) (row['name'] ?? '').toString(): (row['status'] ?? '0').toString()
      };
      setState(() {
        allAttendance[_formatDate(selectedDate)] = daily;
        allExtras[_formatDate(selectedDate)] ??= {
          for (final w in selectedWorkers) w['name']: '0'
        };
      });
    }
  }

  Future<void> _saveAttendance() async {
    final todayKey = _formatDate(selectedDate);

    setState(() => isSaving = true);

    try {
      // Workers on vacaciones/incapacidad are dropped from the payload
      // entirely — not sent with their current status, not sent at all.
      //
      // This screen builds its payload from EVERY worker on the obra with
      // `?? '0'` as the fallback, not just the ones that were tapped. A worker
      // whose status came back 'V' from the server's merge only round-tripped
      // because loadAttendanceForDate happened to populate the map; if a
      // worker joins the roster after that load, SAVE would post '0' over
      // their absence.
      //
      // isSpecialAttendanceStatus is the test on purpose — it is the single
      // definition of "not editable", already used by the card to lock the
      // tap. The save path simply never consulted it.
      //
      // NOTE this does not cover a FAILED load: build() then fills the map
      // with '0' for everyone, so there is no 'V' here to detect. That case is
      // covered server-side, where save_attendance skips writes that would
      // shadow an absence and reports how many in `skipped_absence`.
      final attendancePayload = selectedWorkers
          .where((worker) => !isSpecialAttendanceStatus(
              allAttendance[todayKey]?[worker['name']]))
          .map((worker) {
        final name = worker['name'] as String;
        final status =
            _effectiveStatus(allAttendance[todayKey]![worker['name']] ?? '0');
        final extraTxt = (allExtras[todayKey]![name] ?? '0').replaceAll(',', '.');
        final extra = double.tryParse(extraTxt) ?? 0.0;

        return {
          'worker_id': worker['id'],
          'project_id': currentProjectId,
          'date': selectedDate.toIso8601String().split('T').first,
          'status': status,
          'extra_hours': extra,
        };
      }).toList();

      final response = await http.post(
        u('/attendance/'),
        headers: await authHeaders(),
        body: jsonEncode(attendancePayload),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Asistencia guardada'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  /// The status to SHOW and to SEND for a worker, after the non-working-day
  /// rule. Display and payload go through this one method so the card cannot
  /// show one thing and the save write another.
  ///
  /// On a Sunday there is no "presente", so a stored '1' or '0.5' collapses to
  /// '0'. Two things are deliberately exempt:
  ///
  ///  - **Absences.** V/INC are the server's record of an approved absence,
  ///    not this screen's to rewrite.
  ///  - **Past days.** This screen doubles as a read-only viewer for them, and
  ///    a viewer that rewrites what it displays is lying about the database.
  ///    Past Sundays are corrected from REGISTRO PASADO, which enforces the
  ///    same rule on a path that is actually editable.
  String _effectiveStatus(String stored) {
    if (_isPastDay) return stored;
    if (!isNonWorkingDay(selectedDate)) return stored;
    if (isSpecialAttendanceStatus(stored)) return stored;
    return kNonWorkingDayStatuses.contains(stored)
        ? stored
        : kNonWorkingDayStatuses.first;
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      await loadAttendanceForDate();
      if (!mounted) return;
      if (_isPastDay) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DÍA ANTERIOR: SÓLO CONSULTA'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) => "${date.day}/${date.month}/${date.year}";

  /// Transfer workers from another obra into this one.
  /// Since every worker always belongs to some obra, adding personnel here
  /// means MOVING them; their attendance history stays with the old obra.
  void _showWorkerPickDialog() {
    final candidates = allWorkers
        .where((w) => (w['project_id'] as int?) != currentProjectId)
        .toList()
      ..sort((a, b) {
        final pa = (a['project'] ?? '').toString();
        final pb = (b['project'] ?? '').toString();
        final c = pa.compareTo(pb);
        return c != 0 ? c : (a['name'] ?? '').toString()
            .compareTo((b['name'] ?? '').toString());
      });

    final selected = <int>{};
    String query = '';
    bool sending = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModal) {
          final visible = query.trim().isEmpty
              ? candidates
              : candidates.where((w) {
            final q = query.toLowerCase();
            return (w['name'] ?? '').toString().toLowerCase().contains(q) ||
                (w['project'] ?? '').toString().toLowerCase().contains(q);
          }).toList();

          // Build grouped tiles: a small header per source obra
          final tiles = <Widget>[];
          String? lastProject;
          for (final w in visible) {
            final proj = (w['project'] ?? 'SIN OBRA').toString();
            if (proj != lastProject) {
              lastProject = proj;
              tiles.add(Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(
                  proj.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                    letterSpacing: 0.6,
                  ),
                ),
              ));
            }
            final id = w['id'] as int;
            tiles.add(CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: selected.contains(id),
              title: Text((w['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 14)),
              onChanged: sending
                  ? null
                  : (v) => setModal(() =>
              v == true ? selected.add(id) : selected.remove(id)),
            ));
          }

          return AlertDialog(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('AGREGAR PERSONAL'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre u obra',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setModal(() => query = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Se moverán a esta obra desde la suya.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const Divider(),
                  Expanded(
                    child: candidates.isEmpty
                        ? const Center(
                      child: Text(
                        'No hay personal en otras obras',
                        style: TextStyle(fontSize: 13),
                      ),
                    )
                        : ListView(children: tiles),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                sending ? null : () => Navigator.pop(dialogCtx),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: (selected.isEmpty || sending)
                    ? null
                    : () async {
                  setModal(() => sending = true);
                  final ids = selected.toList();
                  final names = allWorkers
                      .where((w) => ids.contains(w['id']))
                      .map((w) => (w['name'] ?? '').toString())
                      .toList();
                  try {
                    final resp = await http.post(
                      u('/workers/transfer'),
                      headers: await authHeaders(),
                      body: jsonEncode({
                        'ids': ids,
                        'project_id': currentProjectId,
                      }),
                    );
                    if (!mounted) return;
                    Navigator.pop(dialogCtx);
                    if (resp.statusCode != 200) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'No se pudo mover (HTTP ${resp.statusCode})'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    await refreshWorkers();
                    if (!mounted) return;
                    setState(() {
                      final todayKey = _formatDate(selectedDate);
                      allExtras[todayKey] ??= {};
                      for (final n in names) {
                        allExtras[todayKey]![n] = '0';
                      }
                    });
                    // Re-read instead of stamping '0' over the moved workers.
                    // Seeding them locally was the same clobber as the save
                    // payload: a transferred worker on vacaciones had their
                    // merged 'V' overwritten with '0', so the card came back
                    // unmarked and tappable. Re-fetching gets the merge back
                    // rather than merely not making it worse.
                    await loadAttendanceForDate();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              '${ids.length} trabajador(es) movidos')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                },
                child: Text(sending
                    ? 'MOVIENDO...'
                    : 'MOVER${selected.isEmpty ? '' : ' (${selected.length})'}'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _formatDate(selectedDate);
    allAttendance[todayKey] ??= {for (var w in selectedWorkers) w['name']: '0'};
    allExtras[todayKey] ??= {for (var w in selectedWorkers) w['name']: '0'};
    if (isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow),
                ),
                SizedBox(height: 16),
                Text(
                  'CARGANDO PERSONAL . . .',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('REGISTRAR ASISTENCIA'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: const Color(0xFF1C1CF0),
        elevation: 1,
        actions: [
          if (!_isPastDay)
            IconButton(
              tooltip: 'AGREGAR PERSONAL',
              icon: const Icon(Icons.person_add),
              onPressed: _showWorkerPickDialog,
            ),
        ],
        iconTheme: IconThemeData(
          color: Colors.white,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
          ),
        ),
        child: selectedWorkers.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'NO HAY PERSONAL ASIGNADO',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        )
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(selectedDate),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                      if (isNonWorkingDay(selectedDate)) ...[
                        const SizedBox(height: 6),
                        Text(
                          kNonWorkingDayNotice,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // CustomScrollView rather than GridView.builder so the save
            // control can scroll with the crew instead of floating over it.
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final worker = selectedWorkers[index];
                          final name = worker['name'] as String;
                          final status = _effectiveStatus(
                              allAttendance[todayKey]![name] ?? '0');

                          return _AttendanceCard(
                            worker: worker,
                            status: status,
                            extraHours: allExtras[todayKey]![name] ?? '0',
                            initials: attendanceInitials(name),
                            readOnly: _isPastDay,
                            nonWorkingDay: isNonWorkingDay(selectedDate),
                            onStatusChanged: (newStatus) {
                              setState(() {
                                allAttendance[todayKey]![name] = newStatus;
                                if (newStatus != '1') {
                                  allExtras[todayKey]![name] = '0';
                                }
                              });
                            },
                            onExtraHoursChanged: (hours) {
                              setState(() {
                                allExtras[todayKey]![name] = hours;
                              });
                            },
                          );
                        },
                        childCount: selectedWorkers.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildListFooter()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sits at the end of the scrolling list, below the crew — the user scrolls
  /// past everyone to reach it, which is the point: you see who you are about
  /// to save for. On a past day it becomes a plain notice instead, because
  /// letting someone edit and only then discover they cannot save is worse
  /// than not letting them edit.
  Widget _buildListFooter() {
    if (_isPastDay) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Text(
          'PARA DÍAS ANTERIORES USA REGISTRO PASADO',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: isSaving ? null : _saveAttendance,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1C1CF0),
            disabledBackgroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1C1CF0)),
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            isSaving ? 'GUARDANDO...' : 'GUARDAR',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String status;
  final String extraHours;
  final String initials;

  /// Past day: the card still renders its status, but nothing responds.
  final bool readOnly;

  /// Sunday: the status is fixed at ausente, but the hours stay enterable.
  final bool nonWorkingDay;

  final Function(String) onStatusChanged;
  final Function(String) onExtraHoursChanged;

  const _AttendanceCard({
    required this.worker,
    required this.status,
    required this.extraHours,
    required this.initials,
    required this.readOnly,
    required this.nonWorkingDay,
    required this.onStatusChanged,
    required this.onExtraHoursChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSpecial = isSpecialAttendanceStatus(status);
    final isPresent = status == '1';
    // A past day disables interaction without changing how the card looks —
    // the screen doubles as an attendance viewer. Only V/INC grey out.
    final locked = readOnly || isSpecial;
    // Deliberately NOT folded into `locked`: that also gates the hours strip,
    // and hours are the entire point of a non-working day. Only the status
    // toggle is frozen.
    final statusLocked = locked || nonWorkingDay;

    return GestureDetector(
      onTap: statusLocked ? null : () => onStatusChanged(isPresent ? '0' : '1'),
      child: Container(
        decoration: attendanceCardDecoration(isSpecial),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 2,
                  child: AttendancePhotoHeader(
                    photoUrl: worker['photo_url']?.toString(),
                    initials: initials,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: AttendanceNameBlock(
                    name: (worker['name'] ?? '').toString(),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: AttendanceHoursStrip(
                    value: extraHours,
                    enabled: !locked,
                    isSpecial: isSpecial,
                    onChanged: onExtraHoursChanged,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              child: nonWorkingDay
                  ? const AttendanceNonWorkingBadge()
                  : AttendancePresentBadge(isPresent: isPresent),
            ),
            if (isSpecial) AttendanceStatusWatermark(status: status),
          ],
        ),
      ),
    );
  }
}
