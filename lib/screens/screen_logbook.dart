import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'package:control_app/api.dart';
import 'utils/note_pdf.dart';

// ============================================================
// LOGBOOK tab (lives inside ProjectDetailScreen)
// ============================================================
class LogbookTab extends StatefulWidget {
  final Map<String, dynamic> project;

  const LogbookTab({super.key, required this.project});

  @override
  State<LogbookTab> createState() => _LogbookTabState();
}

class _LogbookTabState extends State<LogbookTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _partidas = [];
  List<Map<String, dynamic>> _catalog = [];
  bool _loading = true;
  String _username = '';
  bool _isAdmin = false;
  int? _filterPartidaId; // null = todas, -1 = sin partida

  @override
  bool get wantKeepAlive => true;

  int get _projectId => widget.project['id'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final headers = await authHeaders();
      final results = await Future.wait([
        http.get(u('/projects/$_projectId/notes'), headers: headers),
        http.post(u('/projects/$_projectId/partidas/sync-from-catalog'),
            headers: headers),
        http.get(u('/me'), headers: headers),
        http.get(u('/projects/$_projectId/catalog-items'), headers: headers),
      ]);

      if (!mounted) return;

      final notes = results[0].statusCode == 200
          ? List<Map<String, dynamic>>.from(
          jsonDecode(utf8.decode(results[0].bodyBytes)))
          : <Map<String, dynamic>>[];
      // sync-from-catalog returns the partidas list; if it fails (no write
      // permission), fall back to a plain GET so readers still see them.
      List<Map<String, dynamic>> partidas;
      if (results[1].statusCode == 200) {
        partidas = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(results[1].bodyBytes)));
      } else {
        final pg = await http.get(u('/projects/$_projectId/partidas'),
            headers: await authHeaders(json: false));
        partidas = pg.statusCode == 200
            ? List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(pg.bodyBytes)))
            : <Map<String, dynamic>>[];
      }
      final catalog = results[3].statusCode == 200
          ? List<Map<String, dynamic>>.from(
          jsonDecode(utf8.decode(results[3].bodyBytes)))
          : <Map<String, dynamic>>[];

      // There is no single "can write here" answer for this screen any more.
      // Writing a NOTE is open to any authenticated user in any obra
      // (questionnaire 5.1, requested by the client), while editing PARTIDAS is
      // admin-only (6.3). One flag cannot express both, and the one that used
      // to be here — `isAdmin || username == encargado_username` — expressed
      // neither: it mirrored the encargado tier the backend deleted on
      // 2026-08-17, and since no obra has an encargado set it silently
      // evaluated to `isAdmin`. That hid the add-note button from every
      // non-admin, so 5.1 shipped on the server and never reached the app.
      var username = '';
      var isAdmin = false;
      if (results[2].statusCode == 200) {
        final me = jsonDecode(results[2].body) as Map<String, dynamic>;
        username = (me['username'] ?? '').toString();
        isAdmin = me['is_admin'] == true;
      }

      // A partida deleted in the manager must not strand the feed on a
      // filter that can never match again.
      var filterId = _filterPartidaId;
      if (filterId != null &&
          filterId != -1 &&
          !partidas.any((p) => p['id'] == filterId)) {
        filterId = null;
      }

      setState(() {
        _notes = notes;
        _partidas = partidas;
        _catalog = catalog;
        _username = username;
        _isAdmin = isAdmin;
        _filterPartidaId = filterId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openNoteForm({Map<String, dynamic>? noteToEdit}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NoteFormScreen(
              projectId: _projectId,
              partidas: _partidas,
              catalog: _catalog,
              noteToEdit: noteToEdit,
            ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openNoteDetail(
      Map<String, dynamic> note, bool canManage) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          note: note,
          projectId: _projectId,
          projectName: (widget.project['name'] ?? '').toString(),
          partidas: _partidas,
          catalog: _catalog,
          canManage: canManage,
        ),
      ),
    );
    if (changed == true) _load();
  }

  /// Bottom sheet with note options (edit / delete).
  void _noteMenu(Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Color(0xFF1C1CF0)),
                  title: const Text('EDITAR NOTA'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openNoteForm(noteToEdit: note);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('BORRAR NOTA'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteNote(note);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Future<void> _openPartidasManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartidasManagerScreen(projectId: _projectId),
      ),
    );
    _load(); // partidas may have changed
  }

  Future<void> _deleteNote(Map<String, dynamic> note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('BORRAR NOTA'),
            content: const Text(
                '¿Seguro que quieres borrar esta nota? Sus fotos también se eliminarán.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('BORRAR'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    try {
      final headers = await authHeaders();
      final resp = await http.delete(
          u('/notes/${note['id']}'), headers: headers);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverMessage(resp) ??
                'No se pudo borrar (HTTP ${resp.statusCode})'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// The notes currently on screen, after the partida filter.
  ///
  /// A getter rather than a local in `build` so the print action prints exactly
  /// what the user is looking at. Two copies of this predicate would drift, and
  /// the failure would be quiet: a PDF that silently disagrees with the feed.
  List<Map<String, dynamic>> get _filteredNotes {
    if (_filterPartidaId == null) return _notes;
    return _notes
        .where((n) => _filterPartidaId == -1
            ? n['partida_id'] == null
            : n['partida_id'] == _filterPartidaId)
        .toList();
  }

  String get _filterLabel {
    if (_filterPartidaId == null) return 'TODAS';
    if (_filterPartidaId == -1) return 'SIN PARTIDA';
    final match = _partidas.where((p) => p['id'] == _filterPartidaId);
    if (match.isEmpty) return 'TODAS';
    final p = match.first;
    return p['code'] != null ? '${p['code']} · ${p['name']}' : p['name'];
  }

  /// Prints every note currently on screen as one document.
  ///
  /// Prints `_filteredNotes`, not `_notes`: what you see is what you get, and
  /// the cover sheet names the filter so a printed subset cannot be mistaken
  /// for the whole bitácora.
  ///
  /// No network call for the notes — `_notes` already holds every note for the
  /// obra, because `GET /projects/{id}/notes` is unpaginated.
  Future<void> _printLogbook() async {
    final notes = _filteredNotes;
    if (notes.isEmpty) return;

    final photoCount = notes.fold<int>(
      0,
      (sum, n) => sum + List<dynamic>.from(n['photos'] ?? const []).length,
    );

    var includePhotos = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('IMPRIMIR BITÁCORA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes.length == 1
                  ? '1 nota'
                  : '${notes.length} notas'),
              if (_filterPartidaId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Filtro: $_filterLabel',
                      style: const TextStyle(fontSize: 12)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  photoCount == 1
                      ? '1 fotografía'
                      : '$photoCount fotografías',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('INCLUIR FOTOGRAFÍAS',
                    style: TextStyle(fontSize: 13)),
                value: includePhotos,
                onChanged: (v) => setModal(() => includePhotos = v),
              ),
              // Each photo is downloaded and re-encoded one at a time, so the
              // wait scales with the count rather than being a fixed cost.
              if (includePhotos && photoCount > 50)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Con tantas fotografías puede tardar varios minutos.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('GENERAR')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;

    final progress = ValueNotifier<String>('GENERANDO… 0 / ${notes.length}');
    var dialogUp = false;
    try {
      dialogUp = true;
      // Not dismissible, and the back button is swallowed: cancelling the
      // dialog would not cancel the generation, it would just orphan it.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: progress,
                    builder: (_, text, __) => Text(text),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final bytes = await buildLogbookPdf(
        notes: notes,
        projectName: (widget.project['name'] ?? '').toString(),
        includePhotos: includePhotos,
        filterLabel: _filterPartidaId == null ? null : _filterLabel,
        onProgress: (done, total) =>
            progress.value = 'GENERANDO… $done / $total',
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogUp = false;

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'bitacora_${pdfSlug((widget.project['name'] ?? '').toString())}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      // A throw between showing and popping would otherwise strand a
      // non-dismissible dialog over the screen, with no way out.
      if (dialogUp && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
  }

  void _openFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('FILTRAR POR PARTIDA'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              _filterOption(ctx, 'TODAS', null),
              _filterOption(ctx, 'SIN PARTIDA', -1),
              ..._partidas.map((p) => _filterOption(
                    ctx,
                    p['code'] != null
                        ? '${p['code']} · ${p['name']}'
                        : p['name'],
                    p['id'],
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  Widget _filterOption(BuildContext ctx, String label, int? value) {
    final selected = _filterPartidaId == value;
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: const Color(0xFF1C1CF0),
        size: 20,
      ),
      title: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: () {
        setState(() => _filterPartidaId = value);
        Navigator.pop(ctx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: _notes.isEmpty
              ? ListView(
            // ListView so pull-to-refresh works on the empty state too
            children: [
              // Ungated: see the toolbar button below.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      onPressed: _openPartidasManager,
                      icon: const Icon(Icons.format_list_numbered, size: 18),
                      label: const Text('PARTIDAS'),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery
                  .of(context)
                  .size
                  .height * 0.2),
              const Icon(Icons.edit_note, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'SIN NOTAS AÚN',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Ungated with the FAB it refers to (questionnaire 5.1).
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Usa el botón + para agregar la primera',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          )
              : Builder(builder: (context) {
            final filtered = _filteredNotes;
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: filtered.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // ---------- Partida filter ----------
                          Flexible(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: _filterPartidaId == null
                                    ? Colors.white70
                                    : Colors.yellow,
                              ),
                              onPressed: _openFilterDialog,
                              icon: const Icon(Icons.filter_list, size: 18),
                              label: Text(
                                _filterLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Ungated: the manager is readable by anyone and hides
                          // its own admin-only controls.
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            onPressed: _openPartidasManager,
                            icon: const Icon(Icons.format_list_numbered,
                                size: 18),
                            label: const Text('PARTIDAS'),
                          ),
                          // Compact icon, not a third TextButton.icon: a third
                          // label overflows this row on a narrow phone.
                          //
                          // Deliberately ungated. PARTIDAS is admin-only
                          // because it edits the obra's structure; printing
                          // only reads what is already on screen.
                          if (filtered.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.print,
                                  color: Colors.white70),
                              tooltip: 'IMPRIMIR BITÁCORA',
                              onPressed: _printLogbook,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'SIN NOTAS CON ESTE FILTRO',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                final note = filtered[index - 1];
                final canManage =
                    _isAdmin || note['author'] == _username;
                return _NoteCard(
                  note: note,
                  onMenu: canManage ? () => _noteMenu(note) : null,
                  onTap: () => _openNoteDetail(note, canManage),
                );
              },
            );
          }),
        ),
        // Ungated on purpose: writing a note is open to any authenticated user
        // in any obra (questionnaire 5.1). This used to sit behind _canWrite,
        // which resolved to is_admin, so non-admins could not add a note in the
        // app even though POST /projects/{id}/notes accepts them.
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1C1CF0),
            onPressed: _openNoteForm,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// One note in the feed
// ============================================================
class _NoteCard extends StatelessWidget {
  final Map<String, dynamic> note;
  final VoidCallback? onMenu;
  final VoidCallback? onTap;

  const _NoteCard({required this.note, this.onMenu, this.onTap});

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd/MM/yyyy · HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _fmtQty(dynamic q) {
    final d = (q as num?)?.toDouble() ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  /// The work date the note describes; falls back to the capture timestamp
  /// for responses from a backend that predates phase 12.
  String _cardDate() {
    final nd = note['note_date'];
    if (nd != null) {
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(nd));
      } catch (_) {
        // fall through to created_at
      }
    }
    return _fmtDate(note['created_at']);
  }

  @override
  Widget build(BuildContext context) {
    final photos = List<String>.from(note['photos'] ?? []);
    final partidaName = note['partida_name'];
    final partidaCode = note['partida_code'];
    final text = (note['note_text'] ?? '').toString();
    final avance = note['avance'] as Map<String, dynamic>?;

    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------- Header: folio + partida chip + date + delete ----------
                Row(
                  children: [
                    // Folio: per-obra note number, assigned by the server at
                    // creation and never reused. Null only for responses from
                    // a backend that predates phase 12.
                    if (note['folio'] != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1CF0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'NOTA ${note['folio']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (partidaName != null)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1CF0).withValues(
                                alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            partidaCode != null
                                ? '$partidaCode · $partidaName'
                                : partidaName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1CF0),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _cardDate(),
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    if (onMenu != null)
                      GestureDetector(
                        onTap: onMenu,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.more_vert,
                              size: 18, color: Colors.grey[500]),
                        ),
                      ),
                  ],
                ),

                // ------- avance -------
                if (avance != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_up,
                            size: 15, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 6),
                        Text(
                          '+${_fmtQty(avance['quantity'])}'
                              '${avance['unit'] != null
                              ? ' ${avance['unit']}'
                              : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            avance['code'] != null
                                ? '${avance['code']} · ${avance['name']}'
                                : (avance['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ---------- Text ----------
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
                ],

                // ---------- Photos ----------
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (context, i) {
                      final url = resolvePhotoUrl(photos[i]);
                      if (url == null) return const SizedBox();
                      return GestureDetector(
                        onTap: () =>
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    _GalleryScreen(
                                      photos: photos
                                          .map(resolvePhotoUrl)
                                          .whereType<String>()
                                          .toList(),
                                      initialIndex: i,
                                    ),
                              ),
                            ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            httpHeaders: authHeadersSync(),
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[200]),
                            errorWidget: (context, url, error) =>
                                Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ],

                // ---------- Author ----------
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      (note['author'] ?? '').toString(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}

// ============================================================
// Full-screen photo gallery
// ============================================================
class _GalleryScreen extends StatelessWidget {
  final List<String> photos;
  final int initialIndex;

  const _GalleryScreen({required this.photos, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: photos.length,
        itemBuilder: (context, i) =>
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: photos[i],
                  httpHeaders: authHeadersSync(),
                  fit: BoxFit.contain,
                  placeholder: (context, url) =>
                  const CircularProgressIndicator(
                    color: Colors.white,
                  ),
                  // Was missing. Without it a failed fetch fills the fullscreen
                  // viewer with Flutter's default broken-image glyph and no
                  // explanation — the worst place in the app to leave unhandled.
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image,
                    color: Colors.white38,
                    size: 64,
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

// ============================================================
// photo grid: max 4 tiles in a square, +N overlay
// ============================================================
class _PhotoGrid extends StatelessWidget {
  final List<String> photos;
  final void Function(int index) onTap;

  const _PhotoGrid({required this.photos, required this.onTap});

  static const double _gap = 2;

  Widget _tile(int i, {String? overlay}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(i),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: photos[i],
              httpHeaders: authHeadersSync(),
              fit: BoxFit.cover,
              placeholder: (c, u) => Container(color: Colors.grey[300]),
              errorWidget: (c, u, e) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
            if (overlay != null)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                child: Text(
                  overlay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = photos.length;
    late Widget content;

    if (n == 1) {
      content = Row(children: [_tile(0)]);
    } else if (n == 2) {
      // Two halves, side by side
      content = Row(children: [
        _tile(0),
        const SizedBox(width: _gap),
        _tile(1),
      ]);
    } else if (n == 3) {
      // One tall left + two stacked right
      content = Row(children: [
        _tile(0),
        const SizedBox(width: _gap),
        Expanded(
          child: Column(children: [
            _tile(1),
            const SizedBox(height: _gap),
            _tile(2),
          ]),
        ),
      ]);
    } else {
      // 2x2; the 4th carries "+N" when there are extras
      final extra = n - 4;
      content = Column(children: [
        Expanded(
          child: Row(children: [
            _tile(0),
            const SizedBox(width: _gap),
            _tile(1),
          ]),
        ),
        const SizedBox(height: _gap),
        Expanded(
          child: Row(children: [
            _tile(2),
            const SizedBox(width: _gap),
            _tile(3, overlay: extra > 0 ? '+$extra' : null),
          ]),
        ),
      ]);
    }

    return AspectRatio(aspectRatio: 1, child: content);
  }
}

// ============================================================
// note details and content
// ============================================================
class NoteDetailScreen extends StatefulWidget {
  final Map<String, dynamic> note;
  final int projectId;
  final String projectName;
  final List<Map<String, dynamic>> partidas;
  final List<Map<String, dynamic>> catalog;
  final bool canManage;

  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.projectId,
    required this.projectName,
    required this.partidas,
    required this.catalog,
    required this.canManage,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  bool _busy = false;

  /// Hands the note to the OS print dialog — paper, not share, per the
  /// scoping decision. One note at a time.
  ///
  /// Photos are not in the document yet; that is the second half of this
  /// feature and is deliberately separate, because downscaling full-res site
  /// photos is where the memory risk lives.
  Future<void> _printNote() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildNotePdf(
        note: widget.note,
        projectName: widget.projectName,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'nota_${widget.note['folio'] ?? widget.note['id']}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd/MM/yyyy · HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _fmtQty(dynamic q) {
    final d = (q as num?)?.toDouble() ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  /// The work date the note describes; falls back to the capture timestamp
  /// for responses from a backend that predates phase 12.
  String _noteDateLabel() {
    final nd = widget.note['note_date'];
    if (nd != null) {
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(nd));
      } catch (_) {
        // fall through to created_at
      }
    }
    return _fmtDate(widget.note['created_at']);
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NoteFormScreen(
              projectId: widget.projectId,
              partidas: widget.partidas,
              catalog: widget.catalog,
              noteToEdit: widget.note,
            ),
      ),
    );
    // Data changed: go back to the feed, which reloads
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('BORRAR NOTA'),
            content: const Text(
                '¿Borrar esta nota? También se borrarán sus fotos y el avance que registró.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCELAR')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('BORRAR'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final headers = await authHeaders();
      final resp = await http.delete(
        u('/notes/${widget.note['id']}'),
        headers: headers,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(serverMessage(resp) ??
              'No se pudo borrar (HTTP ${resp.statusCode})'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) =>
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Color(0xFF1C1CF0)),
                  title: const Text('EDITAR NOTA'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _edit();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('BORRAR NOTA'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _delete();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final photos = List<String>.from(note['photos'] ?? []);
    final text = (note['note_text'] ?? '').toString();
    final avance = note['avance'] as Map<String, dynamic>?;
    final partidaName = note['partida_name'];
    final partidaCode = note['partida_code'];
    final author = (note['author'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(note['folio'] != null ? 'NOTA ${note['folio']}' : 'NOTA'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'IMPRIMIR',
            onPressed: _busy ? null : _printNote,
          ),
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _busy ? null : _menu,
            ),
        ],
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ================= POST =================
            Card(
              clipBehavior: Clip.antiAlias, // photos clip to rounded corners
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------- Author header ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF1C1CF0),
                          child: Text(
                            author.isNotEmpty ? author[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                author,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                _noteDateLabel(),
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[600]),
                              ),
                              // Capture timestamp — a semi-formal record
                              // should show "describes the 12th, written on
                              // the 30th" rather than hide it.
                              if (note['note_date'] != null)
                                Text(
                                  'REGISTRADA: ${_fmtDate(note['created_at'])}',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[500]),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---------- Partida tag ----------
                  if (partidaName != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1CF0).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          partidaCode != null
                              ? '$partidaCode · $partidaName'
                              : partidaName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1CF0),
                          ),
                        ),
                      ),
                    ),

                  // ---------- Text ----------
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ),

                  // ---------- Photos (edge to edge) ----------
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _PhotoGrid(
                      photos: photos,
                      onTap: (i) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _GalleryScreen(
                            photos: photos,
                            initialIndex: i,
                          ),
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 10),
                ],
              ),
            ),

            // ================= AVANCE =================
            if (avance != null) ...[
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.trending_up,
                              size: 16, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Text(
                            'AVANCE REGISTRADO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '+${_fmtQty(avance['quantity'])}'
                                  '${avance['unit'] != null ? ' ${avance['unit']}' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      if (avance['code'] != null) ...[
                        Text(
                          avance['code'].toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1CF0),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      // No maxLines: the full concepto is shown
                      Text(
                        (avance['name'] ?? '').toString(),
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// New note form
// ============================================================
class NoteFormScreen extends StatefulWidget {
  final int projectId;
  final List<Map<String, dynamic>> partidas;
  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic>? noteToEdit;

  const NoteFormScreen({
    super.key,
    required this.projectId,
    required this.partidas,
    this.catalog = const [],
    this.noteToEdit,
  });

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  static const double _eps = 1e-9; // float slack: typing exactly the
                                   // remaining quantity must not be rejected

  final _textController = TextEditingController();
  final _avanceController = TextEditingController();
  int? _partidaId;
  int? _conceptoId; // selected catalog item to register progress against
  DateTime _noteDate = DateTime.now(); // work date the note describes
  final List<File> _photos = [];
  bool _isSaving = false;
  late List<Map<String, dynamic>> _partidas;
  late List<Map<String, dynamic>> _catalog;
  final List<String> _existingPhotos = []; // URLs kept from the edited note

  bool get isEditing => widget.noteToEdit != null;

  /// Conceptos belonging to the currently selected partida.
  List<Map<String, dynamic>> get _conceptosForPartida =>
      _partidaId == null
          ? const []
          : _catalog
          .where((c) => c['partida_id'] == _partidaId)
          .toList();

  /// Conceptos offered in the dropdown: those with headroom left. The current
  /// selection is always kept — the dropdown asserts if its value is missing
  /// from the items, and keeping it is what allows downward corrections on
  /// the note that completed a concepto.
  List<Map<String, dynamic>> get _conceptosElegibles =>
      _conceptosForPartida.where((c) {
        if (c['id'] == _conceptoId) return true;
        final h = _headroom(c);
        return h == null || h > _eps;
      }).toList();

  @override
  void initState() {
    super.initState();
    _partidas = List.of(widget.partidas);
    _catalog = List.of(widget.catalog);
    final n = widget.noteToEdit;
    if (n != null) {
      _textController.text = (n['note_text'] ?? '').toString();
      final pid = n['partida_id'];
      if (pid != null && _partidas.any((p) => p['id'] == pid)) {
        _partidaId = pid;
      }
      final nd = DateTime.tryParse((n['note_date'] ?? '').toString()) ??
          DateTime.tryParse((n['created_at'] ?? '').toString());
      if (nd != null) _noteDate = nd;
      _existingPhotos.addAll(List<String>.from(n['photos'] ?? []));
      final av = n['avance'];
      if (av != null && _catalog.any((c) => c['id'] == av['item_id'])) {
        _conceptoId = av['item_id'];
        _avanceController.text = (av['quantity'] ?? '').toString();
      }
    }
    // The passed-in catalog is as old as the last tab load, and until the
    // server cap (step 4b) ships this form's validation is the only thing
    // preventing >100% — refresh `executed` on open.
    _refreshCatalog();
  }

  Future<void> _refreshCatalog() async {
    try {
      final resp = await http.get(
          u('/projects/${widget.projectId}/catalog-items'),
          headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final fresh = List<Map<String, dynamic>>.from(
          jsonDecode(utf8.decode(resp.bodyBytes)));
      setState(() {
        _catalog = fresh;
        // A concepto deleted since the tab loaded must not linger as the
        // dropdown value: value-not-in-items is an assertion failure.
        if (_conceptoId != null &&
            !fresh.any((c) => c['id'] == _conceptoId)) {
          _conceptoId = null;
        }
      });
    } catch (_) {
      // keep the list passed in; validation falls back to it
    }
  }

  /// What this note already contributes to concepto [itemId] on the server
  /// (`this(c)` in the ≤100% rule) — 0 when creating.
  double _thisStored(dynamic itemId) {
    final av = widget.noteToEdit?['avance'];
    if (av == null || av['item_id'] != itemId) return 0;
    return (av['quantity'] as num?)?.toDouble() ?? 0;
  }

  /// Remaining registrable quantity for [c]:
  /// `quantity − (executed − this)`. Null when the concepto has no quantity
  /// to cap against — those are shown and never validated.
  double? _headroom(Map<String, dynamic> c) {
    final q = (c['quantity'] as num?)?.toDouble();
    if (q == null) return null;
    final executed = (c['executed'] as num?)?.toDouble() ?? 0;
    return q - (executed - _thisStored(c['id']));
  }

  Map<String, dynamic>? get _selectedConcepto {
    final match = _catalog.where((c) => c['id'] == _conceptoId);
    return match.isEmpty ? null : match.first;
  }

  double? _enteredQty() =>
      double.tryParse(_avanceController.text.trim().replaceAll(',', ''));

  String _fmtQty(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);

  /// Inline validation for the quantity field; null when the entry fits.
  /// Until the server cap (4b) deploys, this is the only ≤100% guard.
  String? get _avanceError {
    final c = _selectedConcepto;
    if (c == null) return null;
    final h = _headroom(c);
    if (h == null) return null;
    final v = _enteredQty();
    if (v == null || v <= 0) return null; // emptiness is handled on save
    if (v <= h + _eps) return null;
    final q = (c['quantity'] as num).toDouble();
    final others = q - h;
    final unit = (c['unit'] ?? '').toString();
    if (h <= _eps) {
      return 'Concepto completo: ya hay ${_fmtQty(others)} de '
          '${_fmtQty(q)} $unit registrados en otras notas';
    }
    return 'Máximo ${_fmtQty(h)} $unit — ya hay ${_fmtQty(others)} de '
        '${_fmtQty(q)} registrados en otras notas';
  }

  @override
  void dispose() {
    _textController.dispose();
    _avanceController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _addFromCamera() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) {
      setState(() => _photos.add(File(picked.path)));
    }
  }

  Future<void> _addFromGallery() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _photos.addAll(picked.map((x) => File(x.path))));
    }
  }

  Future<String?> _uploadPhoto(File file) async {
    final request = http.MultipartRequest('POST', u('/upload-photo/'));
    request.headers.addAll(await authHeaders(json: false));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final body = jsonDecode(await response.stream.bytesToString());
      return body['filename'];
    }
    return null;
  }


  /// Quick partida creation without leaving the note form.
  /// Main path: pick a concept from the project's catalog.
  /// Fallback: type code + name manually.
  Future<void> _createPartidaDialog() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();

    // Load catalog items so the user can pick instead of typing
    List<Map<String, dynamic>> catalog = [];
    try {
      final resp =
      await http.get(u('/projects/${widget.projectId}/catalog-items'),
          headers: await authHeaders(json: false));
      if (resp.statusCode == 200) {
        catalog = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
      }
    } catch (_) {}
    if (!mounted) return;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('NUEVA PARTIDA'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (catalog.isNotEmpty) ...[
                    Text('DEL CATÁLOGO',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[600])),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: catalog.length,
                        itemBuilder: (lctx, i) {
                          final it = catalog[i];
                          return ListTile(
                            dense: true,
                            contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                            leading: it['code'] != null
                                ? Text(it['code'],
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1C1CF0)))
                                : null,
                            title: Text(it['name'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                            onTap: () {
                              codeController.text = it['code'] ?? '';
                              nameController.text = it['name'] ?? '';
                              Navigator.pop(ctx, true);
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    Text('O ESCRÍBELA MANUAL',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[600])),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: codeController,
                          decoration: const InputDecoration(
                            labelText: 'NO.',
                            labelStyle: TextStyle(fontSize: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'NOMBRE',
                            labelStyle: TextStyle(fontSize: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1CF0),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('CREAR'),
              ),
            ],
          ),
    );

    if (created != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showError('Escribe el nombre de la partida');
      return;
    }

    try {
      final headers = await authHeaders();
      final resp = await http.post(
        u('/projects/${widget.projectId}/partidas'),
        headers: headers,
        body: jsonEncode({
          'code': codeController.text
              .trim()
              .isEmpty
              ? null
              : codeController.text.trim(),
          'name': name,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final nueva = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<
            String,
            dynamic>;
        setState(() {
          _partidas.add(nueva);
          _partidaId = nueva['id']; // select it right away
          _conceptoId = null; // reset concepto on partida change, same as
                              // the dropdown's onChanged
        });
      } else {
        // Partidas are admin-only since 2026-08-17, so a 403 here reads
        // `Solo administradores` — which says who *can* do it, unlike the
        // hardcoded "No tienes permiso para crear partidas" this replaces.
        _showError(serverMessage(resp) ??
            'Error al crear la partida (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Future<void> _save() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _photos.isEmpty && _existingPhotos.isEmpty) {
      _showError('Escribe algo o agrega al menos una foto');
      return;
    }

    // If a concepto is chosen, its quantity must be valid
    double? avanceQty;
    if (_conceptoId != null) {
      avanceQty = _enteredQty();
      if (avanceQty == null || avanceQty <= 0) {
        _showError('La cantidad de avance no es válida');
        return;
      }
      // Re-checked here, not just in the disabled button: until the server
      // cap (4b) deploys, nothing else prevents >100%.
      final err = _avanceError;
      if (err != null) {
        _showError(err);
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // 1. Upload photos
      final filenames = <String>[];
      for (final photo in _photos) {
        final fn = await _uploadPhoto(photo);
        if (fn == null) {
          setState(() => _isSaving = false);
          _showError('Error al subir una de las fotos');
          return;
        }
        filenames.add(fn);
      }

      // 2. Create or update the note
      final headers = await authHeaders();
      final keptFilenames = _existingPhotos
          .map((url) =>
      Uri
          .parse(url)
          .pathSegments
          .isNotEmpty
          ? Uri
          .parse(url)
          .pathSegments
          .last
          : url)
          .toList();
      final body = jsonEncode({
        'partida_id': _partidaId,
        'note_text': text,
        'photos': [...keptFilenames, ...filenames],
        'avance_item_id': _conceptoId,
        'avance_quantity': avanceQty,
        'note_date': DateFormat('yyyy-MM-dd').format(_noteDate),
      });
      final response = isEditing
          ? await http.put(u('/notes/${widget.noteToEdit!['id']}'),
          headers: headers, body: body)
          : await http.post(u('/projects/${widget.projectId}/notes'),
          headers: headers, body: body);

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _isSaving = false);
        // Every non-2xx goes through the server's own `detail`. The avance cap
        // answers 400 with a written reason, and a 403 on the PUT path means
        // `Solo el autor puede editar la nota` — a bare status code would
        // leave either unexplained.
        //
        // There used to be a 401/403 branch here saying "No tienes permiso
        // para escribir en esta bitácora". It was wrong twice over after the
        // encargado tier was removed (2026-08-17): creating a note is open to
        // any authenticated user, so a 403 can no longer come from the POST at
        // all, and on the PUT it hid the real author-or-admin reason. The 401
        // half was wrong from the start — AuthClient already redirects an
        // expired session to /login, so this only flashed a permissions error
        // on the way out.
        _showError(serverMessage(response) ??
            'Error al guardar (HTTP ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Error: $e');
    }
  }

  String? _selectedConceptoUnit() {
    final u = _selectedConcepto?['unit'];
    return (u == null || u
        .toString()
        .trim()
        .isEmpty) ? null : u.toString();
  }

  /// Past days are deliberately writable here — the opposite of
  /// record_attendance, where they are read-only. Future days are not:
  /// a site logbook describes work already done.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _noteDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'FECHA DE LA NOTA',
    );
    if (picked != null) setState(() => _noteDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'EDITAR NOTA' : 'NUEVA NOTA'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- Fecha ----------
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: Color(0xFF1C1CF0)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FECHA DE LA NOTA',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_noteDate),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(Icons.edit, size: 18, color: Colors.grey[500]),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---------- Partida ----------
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SELECCIONAR PARTIDA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[600],
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              value: _partidaId,
                              isExpanded: true,
                              hint: const Text('PARTIDA (OPCIONAL)'),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('SIN PARTIDA'),
                                ),
                                ..._partidas.map(
                                      (p) =>
                                      DropdownMenuItem<int?>(
                                        value: p['id'],
                                        child: Text(
                                          p['code'] != null
                                              ? '${p['code']} · ${p['name']}'
                                              : p['name'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() {
                                    _partidaId = v;
                                    _conceptoId =
                                    null; // reset concepto on partida change
                                  }),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'NUEVA PARTIDA',
                          onPressed: _createPartidaDialog,
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF1C1CF0)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---------- Avance (optional; only conceptos with headroom left,
            // so a finished partida offers nothing to register) ----------
            if (_conceptosElegibles.isNotEmpty) ...[
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.trending_up,
                              size: 18, color: Color(0xFF1C1CF0)),
                          const SizedBox(width: 6),
                          Text(
                            'REGISTRAR AVANCE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _conceptoId,
                          isExpanded: true,
                          hint: const Text('ELIGE UN CONCEPTO'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('SIN AVANCE'),
                            ),
                            ..._conceptosElegibles.map((c) {
                              final q = (c['quantity'] as num?)?.toDouble();
                              final ex =
                                  (c['executed'] as num?)?.toDouble() ?? 0;
                              final label = c['code'] != null
                                  ? '${c['code']} · ${c['name']}'
                                  : (c['name'] ?? '').toString();
                              return DropdownMenuItem<int?>(
                                value: c['id'],
                                child: Text(
                                  q != null
                                      ? '$label  ($ex/$q ${c['unit'] ?? ''})'
                                      : label,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10),
                                ),
                              );
                            }),
                          ],
                          onChanged: (v) => setState(() => _conceptoId = v),
                        ),
                      ),
                      if (_conceptoId != null) ...[
                        const SizedBox(height: 4),
                        TextField(
                          controller: _avanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'CANTIDAD EJECUTADA'
                                '${_selectedConceptoUnit() != null
                                ? ' (${_selectedConceptoUnit()})'
                                : ''}',
                            errorText: _avanceError,
                            errorMaxLines: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ---------- Text ----------
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _textController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'AGREGAR NOTAS...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---------- Photos ----------
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FOTOS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._existingPhotos
                            .asMap()
                            .entries
                            .map(
                              (entry) =>
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: CachedNetworkImage(
                                      imageUrl: entry.value,
                                      httpHeaders: authHeadersSync(),
                                      width: 84,
                                      height: 84,
                                      fit: BoxFit.cover,
                                      // Both were missing here. An existing
                                      // photo that fails to load in the note
                                      // form is the one a user is most likely
                                      // to delete by mistake, thinking it is
                                      // already gone.
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[200]),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            color: Colors.grey[200],
                                            child: const Icon(
                                                Icons.broken_image,
                                                color: Colors.grey),
                                          ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() =>
                                              _existingPhotos.removeAt(
                                                  entry.key)),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close,
                                            size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        ),
                        ..._photos
                            .asMap()
                            .entries
                            .map(
                              (entry) =>
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      entry.value,
                                      width: 84,
                                      height: 84,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(
                                                  () =>
                                                  _photos.removeAt(entry.key)),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close,
                                            size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        ),
                        // Add buttons
                        _AddPhotoButton(
                          icon: Icons.photo_camera,
                          onTap: _addFromCamera,
                        ),
                        _AddPhotoButton(
                          icon: Icons.photo_library,
                          onTap: _addFromGallery,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ---------- Save ----------
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1C1CF0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                onPressed: (_isSaving || _avanceError != null) ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF1C1CF0),
                  ),
                )
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving
                      ? 'GUARDANDO...'
                      : (isEditing ? 'GUARDAR CAMBIOS' : 'GUARDAR NOTA'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AddPhotoButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF1C1CF0)),
      ),
    );
  }
}

// ============================================================
// Partidas manager
// ============================================================
class PartidasManagerScreen extends StatefulWidget {
  final int projectId;

  const PartidasManagerScreen({super.key, required this.projectId});

  @override
  State<PartidasManagerScreen> createState() => _PartidasManagerScreenState();
}

class _PartidasManagerScreenState extends State<PartidasManagerScreen> {
  List<Map<String, dynamic>> _partidas = [];
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = true;
  bool _adding = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadIsAdmin();
    _syncThenLoad();
  }

  /// Who is looking? This screen had no idea until 2026-08-19, because the
  /// button that opens it was gated and only admins ever arrived.
  ///
  /// Now that the PARTIDAS button is open to everyone, this screen serves two
  /// tiers at once: reading the list and ADDING a partida are open to any
  /// authenticated user, while renaming and deleting stay admin-only. The only
  /// thing this flag hides is the per-row ⋯ menu, which holds exactly those
  /// two actions — without it a non-admin would get a sheet whose every entry
  /// answers `Solo administradores`.
  Future<void> _loadIsAdmin() async {
    try {
      final resp =
          await http.get(u('/me'), headers: await authHeaders(json: false));
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _isAdmin = me['is_admin'] == true);
    } catch (_) {
      // Leave _isAdmin false. Hiding a control the user was entitled to is
      // recoverable by reopening the screen; showing one that always fails is
      // the thing worth avoiding.
    }
  }

  /// Auto-create any partidas the catalog implies, then load the list.
  /// Falls back to a plain load if the sync fails (e.g. no permission).
  Future<void> _syncThenLoad() async {
    try {
      final headers = await authHeaders();
      final resp = await http.post(
        u('/projects/${widget.projectId}/partidas/sync-from-catalog'),
        headers: headers,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _partidas = List<Map<String, dynamic>>.from(
              jsonDecode(utf8.decode(resp.bodyBytes)));
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // ignore and fall back
    }
    await _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await http.get(u('/projects/${widget.projectId}/partidas'),
          headers: await authHeaders(json: false));
      if (!mounted) return;
      setState(() {
        _partidas = resp.statusCode == 200
            ? List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)))
            : [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }


  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Escribe el nombre de la partida');
      return;
    }

    setState(() => _adding = true);
    try {
      final headers = await authHeaders();
      final resp = await http.post(
        u('/projects/${widget.projectId}/partidas'),
        headers: headers,
        body: jsonEncode({
          'code': _codeController.text
              .trim()
              .isEmpty
              ? null
              : _codeController.text.trim(),
          'name': name,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _codeController.clear();
        _nameController.clear();
        await _load();
      } else {
        // Admin-only since 2026-08-17; surface the server's `Solo
        // administradores` rather than a hardcoded guess.
        _showError(serverMessage(resp) ??
            'Error al agregar (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Actions sheet for a partida.
  void _partidaMenu(Map<String, dynamic> partida) {
    final label = partida['code'] != null
        ? '${partida['code']} · ${partida['name']}'
        : (partida['name'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF1C1CF0)),
              title: const Text('EDITAR PARTIDA'),
              onTap: () {
                Navigator.pop(ctx);
                _editDialog(partida);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('BORRAR PARTIDA'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(partida);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editDialog(Map<String, dynamic> partida) async {
    final code = TextEditingController(text: partida['code'] ?? '');
    final name = TextEditingController(text: partida['name'] ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('EDITAR PARTIDA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'NO.', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.characters,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'NOMBRE', isDense: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C1CF0),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (name.text.trim().isEmpty) {
      _showError('El nombre no puede estar vacío');
      return;
    }

    try {
      final headers = await authHeaders();
      final resp = await http.put(
        u('/partidas/${partida['id']}'),
        headers: headers,
        body: jsonEncode({
          'code': code.text.trim().isEmpty ? null : code.text.trim(),
          'name': name.text.trim(),
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _load();
      } else {
        // Admin-only since 2026-08-17; surface the server's `Solo
        // administradores` rather than a hardcoded guess.
        _showError(serverMessage(resp) ??
            'Error al guardar (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> partida) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('BORRAR PARTIDA'),
        content: Text(
            '¿Borrar "${partida['name']}"?\n\nLas notas y conceptos ligados a esta partida no se borran, pero quedarán sin partida asignada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('BORRAR'),
          ),
        ],
      ),
    );
    if (ok == true) _delete(partida);
  }

  Future<void> _delete(Map<String, dynamic> partida) async {
    try {
      final headers = await authHeaders();
      final resp =
      await http.delete(u('/partidas/${partida['id']}'), headers: headers);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _load();
      } else {
        _showError(serverMessage(resp) ??
            'No se pudo borrar (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PARTIDAS'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
        child: Column(
          children: [
            // ---------- Add row ---------- (any authenticated user:
            // creating a partida opened up on 2026-08-19; rename and delete
            // stay admin-only, so the per-row ⋯ menu below is still gated)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(
                            labelText: 'NO.',
                            labelStyle: TextStyle(fontSize: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'NOMBRE DE LA PARTIDA',
                            labelStyle: TextStyle(fontSize: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _adding
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : IconButton(
                        onPressed: _add,
                        icon: const Icon(Icons.add_circle,
                            color: Color(0xFF1C1CF0), size: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---------- List ----------
            Expanded(
              child: _loading
                  ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
                  : _partidas.isEmpty
                  ? const Center(
                child: Text(
                  'SIN PARTIDAS\nAgrega la primera arriba',
                  textAlign: TextAlign.center,
                  style:
                  TextStyle(color: Colors.white70, fontSize: 14),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _partidas.length,
                itemBuilder: (context, i) {
                  final p = _partidas[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      dense: true,
                      leading: p['code'] != null
                          ? CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF1C1CF0)
                            .withValues(alpha: 0.1),
                        child: Text(
                          p['code'],
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1CF0),
                          ),
                        ),
                      )
                          : const Icon(Icons.label_outline,
                          color: Color(0xFF1C1CF0)),
                      title: Text(
                        p['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      // EDITAR / BORRAR PARTIDA are admin-only (6.3); the menu
                      // holds nothing else, so a non-admin gets no ⋯ at all.
                      trailing: _isAdmin
                          ? IconButton(
                              icon: Icon(Icons.more_horiz,
                                  color: Colors.grey[500]),
                              onPressed: () => _partidaMenu(p),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}