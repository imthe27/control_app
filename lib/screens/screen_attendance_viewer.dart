import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:control_app/api.dart';
import 'screen_backfill_attendance.dart';

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
  bool _isDownloading = false;
  bool _isAdmin = false;

  // Parsed response from /attendance-week
  String _weekHeader = '';
  List<String> _dateStrs = [];
  List<String> _dayLabels = [];
  List<Map<String, dynamic>> _weekWorkers = [];
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _fetchProjects();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final resp = await http.get(u('/me'), headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _isAdmin = me ['is_admin'] == true);
    } catch (_) {}
  }

  Future<void> _fetchProjects() async {
    try {
      final response = await http.get(u('/projects'),
          headers: await authHeaders(json: false));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          projects = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        });
      }
    } catch (e) {
      _showError('Error al cargar obras: $e');
    }
  }

  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);

    try {
      final anchorStr = DateFormat('yyyy-MM-dd').format(_anchorDate);
      final url = u(
        '/attendance-week'
            '?project_id=${Uri.encodeQueryComponent(_selectedProjectId)}'
            '&anchor_date=$anchorStr',
      );

      final response = await http.get(url, headers: await authHeaders(json: false));
      if (!mounted) return;

      final ct = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 && ct.contains('application/json')) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _weekHeader = (data['header'] ?? '').toString();
          _dateStrs = List<String>.from(data['date_strs'] ?? []);
          _dayLabels = List<String>.from(data['day_labels'] ?? []);
          _weekWorkers = List<Map<String, dynamic>>.from(data['workers'] ?? []);
          _hasData = true;
        });
      } else {
        _showError('Error al cargar asistencia (HTTP ${response.statusCode})');
      }
    } catch (e) {
      _showError('Error de red: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAttendance() async {
    if (!_hasData) {
      _showError('Primero consulta la asistencia');
      return;
    }

    setState(() => _isDownloading = true);

    try {
      final anchorStr = DateFormat('yyyy-MM-dd').format(_anchorDate);
      final url = u(
        '/portal/attendance/export.xlsx'
            '?project_id=${Uri.encodeQueryComponent(_selectedProjectId)}'
            '&anchor_date=$anchorStr',
      );

      // The export endpoint is behind the portal auth middleware,
      // so we send the login token as a Bearer header.
      final response = await http.get(url, headers: await authHeaders(json: false));
      if (!mounted) return;

      final ct = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 && ct.contains('spreadsheet')) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/asistencia_${_selectedProjectId}_$anchorStr.xlsx',
        );
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        _showError(
          'No se pudo descargar el Excel. Inicia sesión de nuevo e intenta otra vez.',
        );
      }
    } catch (e) {
      _showError('Error al descargar: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VER ASISTENCIA'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue, Color(0xFF1C1CF0)],
            ),
          ),
        ),
        titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold
        ),
        elevation: 0,
        actions: [
          if (_hasData)
            _isDownloading
                ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.yellow,
                  strokeWidth: 2,
                ),
              ),
            )
                : IconButton(
              icon: const Icon(Icons.download),
              color: Colors.white,
              tooltip: 'DESCARGAR EXCEL',
              onPressed: _downloadAttendance,
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1C1CF0),
        icon: const Icon(Icons.history_edu, color: Colors.white),
        label: const Text('REGISTRO PASADO',
            style: TextStyle(color: Colors.white)),
        onPressed: () async {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => const BackfillAttendanceScreen()),
          );
          if (saved == true) _fetchAttendance();
          },
      )
          : null,
      body: Container(
        constraints: const BoxConstraints.expand(),
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
                          'OBRA',
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
                              child: Text('TODAS LAS OBRAS'),
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
                          'SEMANA',
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
                    label: _isLoading
                        ? const Text('CARGANDO...')
                        : const Text('VER ASISTENCIA'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_hasData) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                              _weekHeader,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
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
                  const Center(
                    child: Text(
                      'SELECCIONA OBRA Y FECHA PARA VER LA ASISTENCIA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
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
    if (!_hasData || _dateStrs.isEmpty) return const SizedBox();

    return Table(
      border: TableBorder.all(
        color: Colors.grey[300]!,
        width: 0.5,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(120),
        1: const FixedColumnWidth(100),
        ...{
          for (int i = 0; i < _dateStrs.length; i++)
            i + 2: const FixedColumnWidth(56)
        },
        _dateStrs.length + 2: const FixedColumnWidth(60),
      },
      children: [
        // ---------- Header row ----------
        TableRow(
          decoration: BoxDecoration(color: Colors.blue[50]),
          children: [
            _tableCell('NOMBRE', bold: true),
            _tableCell('OBRA', bold: true),
            ...List.generate(_dateStrs.length, (i) {
              final dayNum = _dateStrs[i].split('-').last;
              return _tableCell(
                '${_dayLabels[i]}\n$dayNum',
                bold: true,
                center: true,
              );
            }),
            _tableCell('TOTAL\nHE', bold: true, center: true),
          ],
        ),
        // ---------- Empty state ----------
        if (_weekWorkers.isEmpty)
          TableRow(
            children: [
              _tableCell('SIN REGISTROS'),
              _tableCell('-'),
              ..._dateStrs.map((_) => _tableCell('-', center: true)),
              _tableCell('-', center: true),
            ],
          )
        // ---------- Data rows ----------
        else
          ..._weekWorkers.map((w) {
            final att = Map<String, dynamic>.from(w['attendance'] ?? {});
            final he = Map<String, dynamic>.from(w['extra_hours'] ?? {});
            final total = (w['total_extra'] ?? 0).toDouble();

            return TableRow(
              children: [
                _tableCell(w['name'] ?? '', bold: true),
                _tableCell(w['project'] ?? 'LA FE'),
                ..._dateStrs.map((d) {
                  final status = (att[d] ?? 'N/A').toString();
                  final extra = (he[d] ?? 0).toDouble();
                  return _statusCell(status, extra);
                }),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    _fmtHours(total),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1CF0),
                    ),
                  ),
                ),
              ],
            );
          }),
      ],
    );
  }

  /// A day cell: colored status badge + extra hours below when > 0
  Widget _statusCell(String status, double extra) {
    Color bg;
    Color fg;
    switch (status) {
      case '1':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case 'X':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        break;
      case 'V':
        bg = Colors.yellow.shade100;
        fg = Colors.orange.shade900;
        break;
      case 'INC':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        break;
      default: // 'N/A'
        bg = Colors.transparent;
        fg = Colors.grey.shade400;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          if (extra > 0)
            Text(
              '+${_fmtHours(extra)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade700,
              ),
            ),
        ],
      ),
    );
  }

  /// 2.0 -> "2", 2.5 -> "2.5"
  String _fmtHours(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  Widget _tableCell(
      String text, {
        bool bold = false,
        bool center = false,
      }) {
    return Padding(
      padding: const EdgeInsets.all(6),
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