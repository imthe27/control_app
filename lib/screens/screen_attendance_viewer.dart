import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:control_app/main.dart' show baseUrl;

Uri u(String path) => Uri.parse('$baseUrl$path');

class AttendanceViewerScreen extends StatefulWidget {
  const AttendanceViewerScreen({super.key});

  @override
  State<AttendanceViewerScreen> createState() => _AttendanceViewerScreenState();
}

class _AttendanceViewerScreenState extends State<AttendanceViewerScreen> {
  List<Map<String, dynamic>> projects = [];
  String _selectedProjectId = 'all';
  DateTime _anchorDate = DateTime.now();

  bool _isLoading = false;
  Map<String, dynamic>? _attendanceData;

  final List<String> _dayNames = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'];
  final List<String> _monthNames = ['ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO', 'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'];

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  Future<void> _fetchProjects() async {
    try {
      final response = await http.get(u('/projects'));
      if (response.statusCode == 200) {
        setState(() {
          projects = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        });
      }
    } catch (e) {
      _showError('Error loading projects: $e');
    }
  }

  List<DateTime> _getWeekDates(DateTime anchor) {
    int dayOfWeek = anchor.weekday;
    int daysToThursday = (dayOfWeek - 4) % 7;
    DateTime startOfWeek = anchor.subtract(Duration(days: daysToThursday));
    return [for (int i = 0; i < 7; i++) startOfWeek.add(Duration(days: i))];
  }

  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);

    try {
      final weekDates = _getWeekDates(_anchorDate);
      final anchorStr = '${_anchorDate.year}-${_anchorDate.month.toString().padLeft(2, '0')}-${_anchorDate.day.toString().padLeft(2, '0')}';

      final url = u('/attendance/$_selectedProjectId/$anchorStr');
      

      final response = await http.get(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$url'))
      );

      if (response.statusCode == 200) {
        setState(() {
          _attendanceData = {
            'html': response.body,
            'weekDates': weekDates,
            'startDate': weekDates[0],
            'endDate': weekDates[6],
          };
        });
      } else {
        _showError('Failed to load attendance data');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAttendance() async {
    if (_attendanceData == null) {
      _showError('No data to download');
      return;
    }

    try {
      final anchorStr = '${_anchorDate.year}-${_anchorDate.month.toString().padLeft(2, '0')}-${_anchorDate.day.toString().padLeft(2, '0')}';
      final downloadUrl = '$baseUrl/portal/attendance/export.xlsx?project_id=$_selectedProjectId&anchor_date=$anchorStr';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download started: attendance.xlsx'),
          action: SnackBarAction(
            label: 'Copy URL',
            onPressed: () {
            },
          ),
        ),
      );
    } catch (e) {
      _showError('Download error: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _getWeekHeader() {
    if (_attendanceData == null) return '';
    final start = _attendanceData!['startDate'] as DateTime;
    final end = _attendanceData!['endDate'] as DateTime;
    return 'SEMANA DEL ${start.day} DE ${_monthNames[start.month - 1]} AL ${end.day} DE ${_monthNames[end.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VER ASISTENCIA'),
        titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold),
        backgroundColor: Color(0xFF1C1CF0),
        elevation: 0,
        actions: [
          if (_attendanceData != null)
            IconButton(
              icon: const Icon(Icons.download),
              color: Colors.white,
              tooltip: 'Descargar Excel',
              onPressed: _downloadAttendance,
            ),
        ],
      ),
      body: Container(
        constraints: BoxConstraints.expand(),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
          ),
        ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proyecto',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: _selectedProjectId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('Todos los proyectos'),
                          ),
                          ...projects.map((p) => DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text(p['name']),
                          )),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedProjectId = value ?? 'all');
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semana',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _anchorDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _anchorDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('dd/MM/yyyy').format(_anchorDate),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _fetchAttendance,
                  icon: const Icon(Icons.remove_red_eye),
                  label: _isLoading ? const Text('Cargando...') : const Text('Ver Asistencia'),
                ),
              ),
              const SizedBox(height: 16),
              if (_attendanceData != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getWeekHeader(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildDataTable(),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (!_isLoading)
                Center(
                  child: Text(
                    'Selecciona un proyecto y una fecha para ver la asistencia',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildDataTable() {
    if (_attendanceData == null) return const SizedBox();

    final weekDates = _attendanceData!['weekDates'] as List<DateTime>;

    return Table(
      border: TableBorder.all(
        color: Colors.grey[300]!,
        width: 0.5,
      ),
      columnWidths: {
        0: const FixedColumnWidth(120),
        1: const FixedColumnWidth(100),
        ...{for (int i = 0; i < weekDates.length; i++) i + 2: const FixedColumnWidth(50)}
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.blue[50]),
          children: [
            _tableCell('NOMBRE', bold: true),
            _tableCell('PROYECTO', bold: true),
            ...weekDates.map((date) => _tableCell(
              '${_dayNames[date.weekday - 1]}\n${date.day}',
              bold: true,
              center: true,
            )),
          ],
        ),
        TableRow(
          children: [
            _tableCell('Cargando datos...'),
            _tableCell('-'),
            ...weekDates.map((_) => _tableCell('-', center: true)),
          ],
        ),
      ],
    );
  }

  Widget _tableCell(
      String text, {
        bool bold = false,
        bool center = false,
      }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          height: 1.4,
        ),
      ),
    );
  }
}