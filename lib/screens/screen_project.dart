import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'screen_logbook.dart';
import 'screen_catalog.dart';
import 'screen_record_attendance.dart';
import 'utils/launchers.dart';

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
  bool _canWrite = false;
  bool _uploadingPdf = false;

  @override
  void initState() {
    super.initState();
    project = widget.project;
    _refreshProject();
    _loadMe();
  }

  /// Admin or the obra's encargado — gates the add-PDF affordance, same
  /// rule the catalog and logbook tabs already apply. Fetched once: the
  /// role doesn't change mid-session.
  Future<void> _loadMe() async {
    try {
      final resp =
          await http.get(u('/me'), headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() {
        // Admin, full stop. Its one consumer is _InfoTab's catalog-PDF
        // affordance, which does PUT /projects/{id} — admin-only since
        // 2026-08-17. The `|| username == encargado_username` half that used to
        // be here mirrored a backend tier that no longer exists, and matched
        // nobody only because no obra has an encargado assigned.
        _canWrite = me['is_admin'] == true;
      });
    } catch (_) {}
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

  /// Uploads a catalog PDF and writes it onto the project, in place.
  ///
  /// ⚠ **There are TWO writers of `catalog_pdf` in this client.** This one is
  /// the quick path for the empty case — one tap, no navigation. The other is
  /// `_payload()` in `screen_project_form.dart`, which handles add *and*
  /// replace. **Change the PUT payload in one and check the other**: both
  /// carry the same full-replace echo, so a field dropped here and not there
  /// wipes a column from one entry point and not the other, which is a
  /// miserable bug to track down.
  ///
  /// The form's picker was historically declared but never wired up
  /// (`_pickedCatalog` assigned nowhere), so this card used to navigate to a
  /// screen that could not add a PDF. If you ever reduce this back to one
  /// writer, delete the loser rather than leaving it inert.
  Future<void> _addCatalogPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = picked?.files.single.path;
    if (path == null) return; // cancelled, or no readable path

    if (!mounted) return;
    setState(() => _uploadingPdf = true);
    try {
      // Trailing slash is load-bearing: the route is /upload-catalog/. Without
      // it FastAPI answers 307 and the redirect drops the Authorization
      // header, so the upload 401s.
      final req = http.MultipartRequest('POST', u('/upload-catalog/'));
      req.headers.addAll(await authHeaders(json: false));
      req.files.add(await http.MultipartFile.fromPath('file', path));
      final resp = await req.send();
      if (resp.statusCode != 200) {
        if (!mounted) return;
        setState(() => _uploadingPdf = false);
        _snackError('Error al subir el catálogo');
        return;
      }
      final filename =
          jsonDecode(await resp.stream.bytesToString())['filename'];

      // PUT /projects/{id} is a FULL REPLACE for every column except
      // photo_url and catalog_pdf, which are COALESCE-protected. Everything
      // else must be echoed back or it is wiped.
      //
      //   progress        — GET returns the COMPUTED weighted value, which is
      //                     null when the obra has no priced catalog.
      //                     ProjectUpdate.progress is a required non-nullable
      //                     float, so echoing null is a 422. 0.6 mirrors the
      //                     form's default: a known wart, not fixed here.
      //   contract_amount — the server omits the key entirely for non-admins,
      //                     so this is null for them, and update_project
      //                     preserves the stored value on a non-admin write.
      //                     No client-side guard belongs here.
      //   photo_url       — arrives as a signed absolute URL carrying
      //                     ?exp=&sig=. Echoed verbatim; the server runs
      //                     _normalize_photo_filename() on write, which strips
      //                     host and query. Do not strip anything here.
      final put = await http.put(
        u('/projects/${project['id']}'),
        headers: await authHeaders(),
        body: jsonEncode({
          'catalog_pdf': filename,
          'name': project['name'] ?? '',
          'address': project['address'] ?? '',
          'status': project['status'] ?? 'EN PROCESO',
          'progress': project['progress'] ?? 0.6,
          'photo_url': project['photo_url'],
          'contract_name': project['contract_name'],
          'contract_number': project['contract_number'],
          'client_name': project['client_name'],
          'contract_amount': project['contract_amount'],
          'encargado_username': project['encargado_username'],
          'start_date': project['start_date'],
          'end_date': project['end_date'],
        }),
      );
      if (!mounted) return;
      if (put.statusCode != 200) {
        setState(() => _uploadingPdf = false);
        // Editing an obra is admin-only since 2026-08-17, so a 403 reads
        // `Solo administradores`. That replaces a hardcoded "No tienes
        // permiso para editar esta obra", which also caught 401 — where
        // AuthClient is already redirecting to /login.
        _snackError(serverMessage(put) ??
            'Error al guardar (HTTP ${put.statusCode})');
        return;
      }
      await _refreshProject();
      if (!mounted) return;
      setState(() => _uploadingPdf = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPdf = false);
      _snackError('Error: $e');
    }
  }

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
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
              _InfoTab(
                project: project,
                onRefresh: _refreshProject,
                canWrite: _canWrite,
                uploadingPdf: _uploadingPdf,
                onAddPdf: _addCatalogPdf,
              ),
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
  final Future<void> Function() onRefresh;
  final bool canWrite;
  final bool uploadingPdf;
  final Future<void> Function() onAddPdf;

  const _InfoTab({
    required this.project,
    required this.onRefresh,
    required this.canWrite,
    required this.uploadingPdf,
    required this.onAddPdf,
  });

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
    final pdfUrl = resolvePhotoUrl(project['catalog_pdf']);
    final address = (project['address'] ?? '').toString().trim();

    // Refreshes the project object only (one GET /projects). The other two
    // tabs own their data: CATÁLOGO re-fetches on every visit (no keep-alive),
    // BITÁCORA keeps state deliberately and has its own pull-to-refresh.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                // The server omits the key entirely for non-admins (vs null
                // for "admin, not set"), exactly so the client can hide the
                // row rather than render a misleading SIN REGISTRAR.
                if (project.containsKey('contract_amount'))
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
                  onTap: address.isEmpty
                      ? null
                      : () => openMaps(context, address),
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

        // ---------- Catálogo PDF ----------
        // The card itself does no I/O; download/render failures surface in
        // CatalogPdfScreen's existing error + REINTENTAR state. Read-only
        // users with no PDF see nothing — same philosophy as the monto row.
        if (pdfUrl != null) ...[
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CatalogPdfScreen(
                    url: pdfUrl,
                    title: project['name'] ?? 'CATÁLOGO',
                  ),
                ),
              ),
              leading: const Icon(Icons.picture_as_pdf,
                  color: Color(0xFF1C1CF0), size: 28),
              title: Text(
                'CATÁLOGO PDF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              subtitle: const Text(
                'VER DOCUMENTO',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ] else if (canWrite) ...[
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              // Uploads in place — no navigation. Only shown while
              // catalog_pdf is null; replacing an existing one is done from
              // the edit form, which is the other writer. This used to push
              // ProjectFormScreen back when the form's picker was never wired
              // up, so the "+" opened a screen that could not add a PDF.
              onTap: uploadingPdf ? null : onAddPdf,
              leading: Icon(Icons.picture_as_pdf_outlined,
                  color: Colors.grey[500], size: 28),
              title: Text(
                'CATÁLOGO PDF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              subtitle: Text(
                'SIN PDF — AGREGAR',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[500]),
              ),
              trailing: uploadingPdf
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline,
                      color: Color(0xFF1C1CF0)),
            ),
          ),
        ],
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
      ),
    );
  }
}

/// One labeled row of the info card. Shows 'SIN REGISTRAR' when empty.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  final bool isLast;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = (value == null || value.toString().trim().isEmpty)
        ? null
        : value.toString();

    final row = Padding(
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
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.open_in_new, size: 18, color: Colors.grey[400]),
            ),
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        if (!isLast) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }
}
