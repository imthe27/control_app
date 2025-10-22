import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/main.dart' show baseUrl;

Uri u(String path) => Uri.parse('$baseUrl$path');

class AttendanceRecordScreen extends StatefulWidget {
  final int projectId;

  const AttendanceRecordScreen({super.key, required this.projectId});

  @override
  State<AttendanceRecordScreen> createState() => _AttendanceRecordScreenState();
}

class _AttendanceRecordScreenState extends State<AttendanceRecordScreen> {
  DateTime selectedDate = DateTime.now();
  final Map<String, Map<String, String>> allAttendance = {};
//  date => { workerName: "2.5" }
  final Map<String, Map<String, String>> allExtras = {};
  List<Map<String, dynamic>> selectedWorkers = [];
  List<Map<String, dynamic>> allWorkers = [];
  int get currentProjectId => widget.projectId;
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    refreshWorkers();
    loadAttendanceForDate();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project ID: $currentProjectId'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> refreshWorkers() async {
    try {
      final resp = await http.get(u('/workers'));
      if (resp.statusCode == 200) {
        final contentType = resp.headers['content-type'] ?? '';
        if (!contentType.contains('application/json')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Respuesta no válida del servidor (no JSON).')),
          );
          return;
        }
        final data = jsonDecode(resp.body);
        setState(() {
          allWorkers = List<Map<String, dynamic>>.from(data);
          selectedWorkers = allWorkers
              .where((w) => w['project_id'] == currentProjectId)
              .toList()
            ..sort((a, b) => (a['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase()));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ${resp.statusCode} al cargar workers')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red: $e')),
      );
    }
  }

  Future<void> loadAttendanceForDate() async {
    final formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    final resp = await http.get(u('/attendance/$currentProjectId/$formattedDate'));

    if (resp.statusCode == 200 && (resp.headers['content-type'] ?? '').contains('application/json')) {
      final data = jsonDecode(resp.body);
      final Map<String, String> daily = {
        for (var entry in data) entry['name']: (entry['status'] ?? '0').toString()
      };
      setState(() {
        allAttendance[_formatDate(selectedDate)] = daily;
        allExtras[_formatDate(selectedDate)] ??= {
          for (var w in selectedWorkers) w['name']: '0'
        };
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Asistencia no disponible (${resp.statusCode})')),
      );
    }
  }

  Map<String, String> get currentDayAttendance {
    final key = _formatDate(selectedDate);
    return allAttendance[key] ?? {};
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      await loadAttendanceForDate();
    }
  }

  void _saveAttendance() async {
    final key = _formatDate(selectedDate);
    allAttendance[key] = {
      for (var w in selectedWorkers)
        w['name']: currentDayAttendance[w['name']] ?? '0'
    };

    final extrasMap = allExtras[key] ??= { for (var w in selectedWorkers) w['name']: '0' };

    final attendancePayload = selectedWorkers.map((worker) {
      final name = worker['name'] as String;
      final extraTxt = extrasMap[name] ?? '0';
      final extra = double.tryParse(extraTxt.replaceAll(',', '.')) ?? 0.0;
      return {
        'worker_id': worker['id'],
        'project_id': currentProjectId,
        'date': selectedDate.toIso8601String().split('T').first,
        'status': allAttendance[key]![worker['name']],
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
        const SnackBar(content: Text('Asistencia guardada')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar asistencia: ${response.body}')),
      );
    }
  }

  String _formatDate(DateTime date) => "${date.day}/${date.month}/${date.year}";

  void _showWorkerPickDialog() {
    showDialog(
      context: context,
      builder: (_) {
        final Map<String, bool> tempSelection = {
          for (var w in allWorkers)
            if ((w['project_id'] == null || w['project_id'] == 0) &&
                !selectedWorkers.any((e) => e['id'] == w['id']))
              w['id'].toString(): false,
        };

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Seleccionar personal'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: tempSelection.entries.map((entry) {
                    final worker = allWorkers.firstWhere((w) => w['id'].toString() == entry.key);
                    return CheckboxListTile(
                      title: Text(worker['name']),
                      value: entry.value,
                      onChanged: (val) {
                        setState(() {
                          tempSelection[entry.key] = val ?? false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final selectedToAdd = tempSelection.entries
                        .where((e) => e.value)
                        .map((e) => allWorkers.firstWhere((w) => w['id'].toString() == e.key))
                        .toList();

                    for (var worker in selectedToAdd) {
                      await http.put(
                        u('/worker/${worker['id']}/assign-project'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'project_id': currentProjectId}),
                      );
                    }

                    Navigator.pop(context);

                    if (mounted) {
                      await refreshWorkers();

                      setState(() {
                        selectedWorkers.addAll(selectedToAdd);
                        final todayKey = _formatDate(selectedDate);
                        allAttendance[todayKey] ??= {};
                        allExtras[todayKey] ??= {};
                        for (var worker in selectedToAdd) {
                          allAttendance[todayKey]![worker['name']] = '0';
                          allExtras[todayKey]![worker['name']] = '0';
                        }
                      });
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> deleteWorkersFromProject(List<int> ids) async {
    for (int id in ids) {
      final response = await http.put(
        u('/worker/$id/remove-project'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 200) {
        print('Error al eliminar trabajador $id: ${response.body}');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trabajadores eliminados')));
  }

  void _confirmDeleteSelected() {
    String password = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa la contraseña para eliminar los trabajadores seleccionados:'),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (password == 'Mony1705') {
                final idsToDelete = selectedIndexes.map((i) => selectedWorkers[i]['id'] as int).toList();
                await deleteWorkersFromProject(idsToDelete);
                await refreshWorkers();
                setState(() => selectedIndexes.clear());
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña incorrecta')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _formatDate(selectedDate);
    allAttendance[todayKey] ??= {
      for (var w in selectedWorkers) w['name']: '0'
    };
    allExtras[todayKey] ??= {
      for (var w in selectedWorkers) w['name']: '0'
    };

    final attendanceMap = allAttendance[todayKey]!;
    final extrasMap = allExtras[todayKey]!;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Asistencia'),
        actions: [
          if (selectedIndexes.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _confirmDeleteSelected,
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.calendar_today),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _pickDate,
                  child: Text(
                    _formatDate(selectedDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _saveAttendance,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
          if (selectedWorkers.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Por favor agregue personal',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: selectedWorkers.length,
                itemBuilder: (context, index) {
                  final worker = selectedWorkers[index];
                  return GestureDetector(
                    onLongPress: () {
                      setState(() {
                        if (selectedIndexes.contains(index)) {
                          selectedIndexes.remove(index);
                        } else {
                          selectedIndexes.add(index);
                        }
                      });
                    },
                    child: ListTile(
                      title: Text(worker['name']),
                      trailing: SizedBox(
                        width: 160,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: attendanceMap[worker['name']] == '1',
                              onChanged: (val) {
                                setState(() {
                                  allAttendance[todayKey]![worker['name']] = val == true ? '1' : '0';
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'HE',
                                  border: OutlineInputBorder(),
                                ),
                                controller: TextEditingController(
                                  text: extrasMap[worker['name']] ?? '0',
                                ),
                                onChanged: (txt) {
                                  setState(() {
                                    allExtras[todayKey]![worker['name']] = txt;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      tileColor: selectedIndexes.contains(index) ? Colors.red.shade100 : null,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showWorkerPickDialog,
        tooltip: 'Agregar personal desde la lista',
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
