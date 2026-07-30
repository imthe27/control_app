import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'screen_logbook.dart';
import 'screen_catalog.dart';
import 'screen_record_attendance.dart';

/// Project detail hub: INFO | CATÁLOGO | BITÁCORA
/// Phase 1: INFO tab functional, the other two are placeholders.
class ProjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailScreen> {
  late Map<String, dynamic> project;

  @override
  void initState() {
    super.initState();
    project = widget.project;
    _refreshProject();
  }

  Future<void> _refreshProject() async {
    try {
      final resp = await http.get(u('/projects'),
          headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final all = List<Map<String, dynamic>>.from(
          jsonDecode(utf8.decode(resp.bodyBytes)));
      final fresh = all.where((p) => p['id'] == project['id']);
      if (fresh.isNotEmpty) {
        setState(() => project = fresh.first);
      }
    } catch(_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(project['name'] ?? 'OBRA'),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          backgroundColor: const Color(0xFF1C1CF0),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(text: 'INFO'),
              Tab(text: 'CATÁLOGO'),
              Tab(text: 'BITÁCORA'),
            ],
          ),
        ),
        body: Container(
          constraints: const BoxConstraints.expand(),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
            ),
          ),
          child: TabBarView(
            children: [
              _InfoTab(project: project),
              CatalogTab(project: project),
              LogbookTab(project: project),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// INFO tab
// ============================================================
class _InfoTab extends StatelessWidget {
  final Map<String, dynamic> project;

  const _InfoTab({required this.project});

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _fmtMoney(dynamic amount) {
    if (amount == null) return '';
    final value = (amount as num).toDouble();
    return NumberFormat.currency(locale: 'es_MX', symbol: '\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = resolvePhotoUrl(project['photo_url']);
    final tracked = project['progress'] != null;
    final progress = ((project['progress'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final status = (project['status'] ?? '').toString();
    final isFinished = status.toLowerCase().contains('termin') ||
        status.toLowerCase().contains('finish');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------- Photo header ----------
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 170,
            width: double.infinity,
            child: photoUrl != null
                ? CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator(color: Colors.white)),
              errorWidget: (context, url, error) => Image.asset(
                'assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg',
                fit: BoxFit.cover,
              ),
            )
                : Image.asset(
              'assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Status + progress ----------
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AVANCE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFinished ? Colors.green[50] : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isFinished ? Colors.green[800] : Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!tracked)
                  Text('N/A — Importa el catálogo para calcular el avance',
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[500]))
                else
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: Colors.grey[200],
                            color: const Color(0xFF1C1CF0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1CF0),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ---------- Contract info ----------
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.business,
                  label: 'CLIENTE',
                  value: project['client_name'],
                ),
                _InfoRow(
                  icon: Icons.description,
                  label: 'CONTRATO',
                  value: project['contract_name'],
                ),
                _InfoRow(
                  icon: Icons.tag,
                  label: 'NO. DE CONTRATO',
                  value: project['contract_number'],
                ),
                _InfoRow(
                  icon: Icons.attach_money,
                  label: 'MONTO',
                  value: _fmtMoney(project['contract_amount']),
                ),
                _InfoRow(
                  icon: Icons.event,
                  label: 'INICIO',
                  value: _fmtDate(project['start_date']),
                ),
                _InfoRow(
                  icon: Icons.event_available,
                  label: 'TÉRMINO',
                  value: _fmtDate(project['end_date']),
                ),
                _InfoRow(
                  icon: Icons.location_on,
                  label: 'DIRECCIÓN',
                  value: project['address'],
                ),
                _InfoRow(
                  icon: Icons.engineering,
                  label: 'ENCARGADO',
                  value: project['encargado_username'],
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ---------- Quick action: attendance ----------
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1C1CF0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecordAttendanceScreen(projectId: project['id']),
                ),
              );
            },
            icon: const Icon(Icons.checklist),
            label: const Text(
              'PASE DE LISTA',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One labeled row of the info card. Shows 'SIN REGISTRAR' when empty.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  final bool isLast;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = (value == null || value.toString().trim().isEmpty)
        ? null
        : value.toString();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF1C1CF0)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text ?? 'SIN REGISTRAR',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: text != null ? FontWeight.w500 : FontWeight.normal,
                        fontStyle: text != null ? FontStyle.normal : FontStyle.italic,
                        color: text != null ? Colors.black87 : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }
}
