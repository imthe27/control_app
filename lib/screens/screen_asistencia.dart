import 'package:flutter/material.dart';

class AttendanceRecordScreen extends StatefulWidget {
  const AttendanceRecordScreen({super.key});

  @override
  State<AttendanceRecordScreen> createState() => _AttendanceRecordScreenState();
}

class _AttendanceRecordScreenState extends State<AttendanceRecordScreen> {
  DateTime selectedDate = DateTime.now();

  final Map<String, Map<String, bool>> allAttendance = {}; // date => {worker: present}
  List<Map<String, dynamic>> selectedWorkers = [];
  final List<Map<String, dynamic>> workers = [
    {
      'name': 'LUIS PÉREZ',
      'project': 'Asignado a: Fundación Sur',
      'image': null,
    },
    {
      'name': 'JOSÉ MARTÍNEZ',
      'project': 'Asignado a: Edificio Central',
      'image': null,
    },
  ];
  Map<String, bool> get currentDayAttendance {
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

        // Reset checkboxes if no saved data for this date
        if (!allAttendance.containsKey(_formatDate(picked))) {
          allAttendance[_formatDate(picked)] = {
            for (var w in selectedWorkers) w['name']: false
          };
        }
      });
    }
  }

  void _saveAttendance() {
    final key = _formatDate(selectedDate);
    allAttendance[key] = {
      for (var w in selectedWorkers)
        w['name']: currentDayAttendance[w['name']] ?? false
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asistencia guardada')),
    );
  }

  String _formatDate(DateTime date) =>
      "${date.day}/${date.month}/${date.year}";

  void _showWorkerPickDialog() {
    showDialog(
      context: context,
      builder: (_) {
        final Map<String, bool> tempSelection = {
          for (var w in workers)
            if (!selectedWorkers.any((e) => e['name'] == w['name']))
              w['name']: false
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
                    final worker = workers.firstWhere((w) => w['name'] == entry.key);
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
                  onPressed: () {
                    final selectedToAdd = tempSelection.entries
                        .where((e) => e.value)
                        .map((e) => workers.firstWhere((w) => w['name'] == e.key))
                        .toList();

                    Navigator.pop(context);

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        selectedWorkers.addAll(selectedToAdd);

                        final todayKey = _formatDate(selectedDate);
                        allAttendance[todayKey] ??= {};
                        for (var worker in selectedToAdd) {
                          allAttendance[todayKey]![worker['name']] = false;
                        }
                      });
                    });
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

  @override
  Widget build(BuildContext context) {
    final todayKey = _formatDate(selectedDate);
    allAttendance[todayKey] ??= {
      for (var w in selectedWorkers) w['name']: false
    };

    final attendanceMap = allAttendance[todayKey]!;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Asistencia')),
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
                  return CheckboxListTile(
                    title: Text(worker['name']),
                    subtitle: Text(worker['project']),
                    value: attendanceMap[worker['name']] ?? false,
                    onChanged: (val) {
                      setState(() {
                        allAttendance[todayKey] ??= {};
                        allAttendance[todayKey]![worker['name']] = val ?? false;
                      });
                    },
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
