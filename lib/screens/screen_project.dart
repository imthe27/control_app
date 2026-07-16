import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'screen_record_attendance.dart';

/// Project detail hub: INFO | CATÁLOGO | BITÁCORA
/// Phase 1: INFO tab functional, the other two are placeholders.
class ProjectDetailScreen extends StatelessWidget {
  final Map<String, dynamic> project;

  const ProjectDetailScreen({super.key, required this.project});

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
              _CatalogTab(project: project),
              const _ComingSoonTab(
                icon: Icons.edit_note,
                message: 'BITÁCORA DE OBRA',
                subtitle: '',
              ),
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

// ============================================================
// Placeholder for CATÁLOGO and BITÁCORA (phases 2 and 3)
// ============================================================
class _CatalogTab extends StatefulWidget {
  final Map<String, dynamic> project;
  
  const _CatalogTab({required this.project});
  
  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab>
with AutomaticKeepAliveClientMixin {
  String? _localPath;
  bool _loading = false;
  String? _error;
  int _pages = 0;
  int _currentPage = 0;
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  Future<void> _load() async {
    final url = resolvePhotoUrl(widget.project['catalo_pdf']);
    if (url == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // cache by filename: a new catalog gets a new uuid filename,
      // so the cache busts itself automatically.
      final filename = Uri.parse (url).pathSegments.last;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/catalogs/$filename');

      if (!await file.exists()) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        await file.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
      }

      if (!mounted) return;
      setState(() {
        _localPath = file.path;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el catálogo';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasCatalog = resolvePhotoUrl(widget.project['catalog_pdf']) != null;

    if (!hasCatalog) {
      return const _ComingSoonTab(
        icon: Icons.picture_as_pdf,
        message: 'SIN CATÁLOGO',
        subtitle: 'Agrégalo desde EDITAR OBRA',
      );
    }

    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'DESCARGANDO CATÁLOGO...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1C1CF0),
              ),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      );
    }

    if (_localPath == null) return const SizedBox();

    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: PDFView(
            filePath: _localPath!,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: false,
            onRender: (pages) => setState(() => _pages = pages ?? 0),
            onPageChanged: (page, _) =>
                setState(() => _currentPage = page ?? 0),
            onError: (e) => setState(() => _error = 'Error al mostrar el PDF'),
          ),
        ),
        if (_pages > 0)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentPage + 1} / $_pages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
// ============================================================
// Placeholder for CATÁLOGO and BITÁCORA (phases 2 and 3)
// ============================================================
class _ComingSoonTab extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;

  const _ComingSoonTab({
    required this.icon,
    required this.message,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}