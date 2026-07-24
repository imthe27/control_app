import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/main.dart' show baseUrl;

Uri u(String path) => Uri.parse('$baseUrl$path');

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
  Set<int> selectedIndexes = {};
  bool isSaving = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshWorkers();
    loadAttendanceForDate();
  }

  Future<void> refreshWorkers() async {
    try {
      final resp = await http.get(u('/workers'));

      final ct = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workers HTTP ${resp.statusCode}')),
        );
        return;
      }
      if (!ct.contains('application/json')) {
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
      isLoading = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red/parseo: $e')),
      );
    }
  }

  Future<void> loadAttendanceForDate() async {
    final formattedDate =
        "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    final resp = await http.get(u('/attendance/$currentProjectId/$formattedDate'));

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
      final attendancePayload = selectedWorkers.map((worker) {
        final name = worker['name'] as String;
        final status = allAttendance[todayKey]![worker['name']] ?? '0';
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
        headers: {'Content-Type': 'application/json'},
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
    }
  }

  void _applyStatusToSelected(String status) {
    final key = _formatDate(selectedDate);
    setState(() {
      for (final idx in selectedIndexes) {
        final name = selectedWorkers[idx]['name'];
        allAttendance[key]![name] = status;
        if (status != '1') {
          allExtras[key]![name] = '0';
        }
      }
    });
  }

  void _clearSpecialStatusForSelected() {
    final key = _formatDate(selectedDate);
    setState(() {
      for (final idx in selectedIndexes) {
        final name = selectedWorkers[idx]['name'];
        allAttendance[key]![name] = '0';
      }
      selectedIndexes.clear();
    });
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
                      headers: {'Content-Type': 'application/json'},
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
                      allAttendance[todayKey] ??= {};
                      allExtras[todayKey] ??= {};
                      for (final n in names) {
                        allAttendance[todayKey]![n] = '0';
                        allExtras[todayKey]![n] = '0';
                      }
                    });
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

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.map((p) => p[0]).take(2).join().toUpperCase();
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
          if (selectedIndexes.isNotEmpty) ...[
            IconButton(
              tooltip: 'VACACIONES',
              icon: const Icon(Icons.beach_access),
              onPressed: () => _applyStatusToSelected('V'),
            ),
            IconButton(
              tooltip: 'INCAPACIDAD',
              icon: const Icon(Icons.local_hospital),
              onPressed: () => _applyStatusToSelected('INC'),
            ),
            IconButton(
              tooltip: 'LIMPIAR',
              icon: const Icon(Icons.refresh),
              onPressed: _clearSpecialStatusForSelected,
            ),
          ],
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDate(selectedDate),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: selectedWorkers.length,
                itemBuilder: (context, index) {
                  final worker = selectedWorkers[index];
                  final name = worker['name'] as String;
                  final status = allAttendance[todayKey]![name] ?? '0';
                  final isSelected = selectedIndexes.contains(index);

                  return _AttendanceCard(
                    worker: worker,
                    status: status,
                    extraHours: allExtras[todayKey]![name] ?? '0',
                    isSelected: isSelected,
                    initials: _getInitials(name),
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
                    onLongPress: () {
                      setState(() {
                        isSelected
                            ? selectedIndexes.remove(index)
                            : selectedIndexes.add(index);
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add_worker',
            onPressed: _showWorkerPickDialog,
            backgroundColor: const Color(0xFF1C1CF0),
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text('AGREGAR', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'save',
            onPressed: isSaving ? null : _saveAttendance,
            backgroundColor: const Color(0xFF1C1CF0),
            icon: isSaving
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow),
              ),
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(isSaving ? 'GUARDANDO...' : 'GUARDAR', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatefulWidget {
  final Map<String, dynamic> worker;
  final String status;
  final String extraHours;
  final bool isSelected;
  final String initials;
  final Function(String) onStatusChanged;
  final Function(String) onExtraHoursChanged;
  final VoidCallback onLongPress;

  const _AttendanceCard({
    required this.worker,
    required this.status,
    required this.extraHours,
    required this.isSelected,
    required this.initials,
    required this.onStatusChanged,
    required this.onExtraHoursChanged,
    required this.onLongPress,
  });

  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard> {
  static const List<double> heOptions = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0];
  late PageController _heController;

  @override
  void initState() {
    super.initState();
    final currentValue = double.tryParse(widget.extraHours) ?? 0.0;
    final initialIndex = heOptions.indexOf(currentValue).clamp(0, heOptions.length - 1);
    _heController = PageController(
      viewportFraction: 0.35,
      initialPage: initialIndex,
    );
  }

  @override
  void dispose() {
    _heController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case '1':
        return Colors.green;
      case 'V':
        return Colors.orange;
      case 'INC':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel() {
    switch (widget.status) {
      case '1':
        return 'PRESENTE';
      case 'V':
        return 'VACACIONES';
      case 'INC':
        return 'INCAPACIDAD';
      default:
        return 'FALTA';
    }
  }

  String _formatHours(double hours) {
    return hours == hours.toInt() ? '${hours.toInt()}' : '$hours';
  }

  @override
  Widget build(BuildContext context) {
    final isSpecial = widget.status == 'V' || widget.status == 'INC';
    final hoursValue = double.tryParse(widget.extraHours) ?? 0.0;
    final isPresent = widget.status == '1';

    return GestureDetector(
      onTap: isSpecial ? null : () => widget.onStatusChanged(isPresent ? '0' : '1'),
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isSelected ? Colors.blue[300]! : Colors.white24,
            width: widget.isSelected ? 2 : 0.5,
          ),
          color: widget.isSelected
              ? Colors.blue[50]
              : Colors.white.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: widget.isSelected
                  ? Colors.blue.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      color: Color(0xFF1C1CF0),
                    ),
                    child: widget.worker['photo_url'] == null
                        ? Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.blue[400]!, Colors.blue[600]!],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                        : ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      child: CachedNetworkImage(
                        imageUrl: widget.worker['photo_url']!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.yellow),
                        ),
                        errorWidget: (context, url, error) =>
                        const Center(child: Icon(Icons.person)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          widget.worker['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _getStatusColor().withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            _getStatusLabel(),
                            style: TextStyle(
                              fontSize: 10,
                              color: _getStatusColor(),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16)),
                      color: isSpecial ? Colors.grey[100] : Colors.blue[50],
                    ),
                    child: IgnorePointer(
                      ignoring: isSpecial,
                      child: PageView.builder(
                        controller: _heController,
                        itemCount: heOptions.length,
                        onPageChanged: (index) {
                          widget.onExtraHoursChanged(heOptions[index].toString());
                        },
                        itemBuilder: (context, index) {
                          final hours = heOptions[index];
                          final isSelectedHours = hoursValue == hours;
                          return Center(
                            child: GestureDetector(
                              onTap: () {
                                _heController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              },
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: isSelectedHours
                                        ? Colors.blue
                                        : Colors.white,
                                    border: Border.all(
                                      color: isSelectedHours
                                          ? Colors.blue
                                          : Colors.grey[300]!,
                                      width: isSelectedHours ? 1.5 : 0.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'HE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: isSelectedHours
                                              ? Colors.white70
                                              : Colors.grey[500],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatHours(hours),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isSelectedHours
                                              ? Colors.white
                                              : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPresent ? Colors.green : Colors.white.withValues(alpha: 0.85),
                  border: Border.all(
                    color: isPresent ? Colors.green : Colors.grey[400]!,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: isPresent ? Colors.white : Colors.grey[400],
                ),
              ),
            ),
            if (widget.isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.3),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}