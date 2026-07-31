import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'package:control_app/api.dart';

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
  bool _canWrite = false;
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

      var canWrite = false;
      var username = '';
      var isAdmin = false;
      if (results[2].statusCode == 200) {
        final me = jsonDecode(results[2].body) as Map<String, dynamic>;
        username = (me['username'] ?? '').toString();
        isAdmin = me['is_admin'] == true;
        canWrite = isAdmin ||
            (username.isNotEmpty &&
                username == widget.project['encargado_username']);
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
        _canWrite = canWrite;
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
            content: Text('No se pudo borrar (HTTP ${resp.statusCode})'),
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

  String get _filterLabel {
    if (_filterPartidaId == null) return 'TODAS';
    if (_filterPartidaId == -1) return 'SIN PARTIDA';
    final match = _partidas.where((p) => p['id'] == _filterPartidaId);
    if (match.isEmpty) return 'TODAS';
    final p = match.first;
    return p['code'] != null ? '${p['code']} · ${p['name']}' : p['name'];
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
              if (_canWrite)
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
              if (_canWrite)
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
            final filtered = _filterPartidaId == null
                ? _notes
                : _notes
                .where((n) =>
            _filterPartidaId == -1
                ? n['partida_id'] == null
                : n['partida_id'] == _filterPartidaId)
                .toList();
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
                          if (_canWrite)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                              onPressed: _openPartidasManager,
                              icon: const Icon(Icons.format_list_numbered,
                                  size: 18),
                              label: const Text('PARTIDAS'),
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
        if (_canWrite)
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
                // ---------- Header: partida chip + date + delete ----------
                Row(
                  children: [
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
                      _fmtDate(note['created_at']),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                  fit: BoxFit.contain,
                  placeholder: (context, url) =>
                  const CircularProgressIndicator(
                    color: Colors.white,
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
  final List<Map<String, dynamic>> partidas;
  final List<Map<String, dynamic>> catalog;
  final bool canManage;

  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.projectId,
    required this.partidas,
    required this.catalog,
    required this.canManage,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  bool _busy = false;

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
          content: Text('No se pudo borrar (HTTP ${resp.statusCode})'),
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
        title: const Text('NOTA'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
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
                                _fmtDate(note['created_at']),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
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
  final _textController = TextEditingController();
  final _avanceController = TextEditingController();
  int? _partidaId;
  int? _conceptoId; // selected catalog item to register progress against
  final List<File> _photos = [];
  bool _isSaving = false;
  late List<Map<String, dynamic>> _partidas;
  final List<String> _existingPhotos = []; // URLs kept from the edited note

  bool get isEditing => widget.noteToEdit != null;

  /// Conceptos belonging to the currently selected partida.
  List<Map<String, dynamic>> get _conceptosForPartida =>
      _partidaId == null
          ? const []
          : widget.catalog
          .where((c) => c['partida_id'] == _partidaId)
          .toList();

  @override
  void initState() {
    super.initState();
    _partidas = List.of(widget.partidas);
    final n = widget.noteToEdit;
    if (n != null) {
      _textController.text = (n['note_text'] ?? '').toString();
      final pid = n['partida_id'];
      if (pid != null && _partidas.any((p) => p['id'] == pid)) {
        _partidaId = pid;
      }
      _existingPhotos.addAll(List<String>.from(n['photos'] ?? []));
      final av = n['avance'];
      if (av != null && widget.catalog.any((c) => c['id'] == av['item_id'])) {
        _conceptoId = av['item_id'];
        _avanceController.text = (av['quantity'] ?? '').toString();
      }
    }
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
        });
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        _showError('No tienes permiso para crear partidas');
      } else {
        _showError('Error al crear la partida (HTTP ${resp.statusCode})');
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
      avanceQty =
          double.tryParse(_avanceController.text.trim().replaceAll(',', ''));
      if (avanceQty == null || avanceQty <= 0) {
        _showError('La cantidad de avance no es válida');
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
      });
      final response = isEditing
          ? await http.put(u('/notes/${widget.noteToEdit!['id']}'),
          headers: headers, body: body)
          : await http.post(u('/projects/${widget.projectId}/notes'),
          headers: headers, body: body);

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) Navigator.pop(context, true);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() => _isSaving = false);
        _showError('No tienes permiso para escribir en esta bitácora');
      } else {
        setState(() => _isSaving = false);
        _showError('Error al guardar (HTTP ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Error: $e');
    }
  }

  String? _selectedConceptoUnit() {
    if (_conceptoId == null) return null;
    final match = widget.catalog.where((c) => c['id'] == _conceptoId);
    if (match.isEmpty) return null;
    final u = match.first['unit'];
    return (u == null || u
        .toString()
        .trim()
        .isEmpty) ? null : u.toString();
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

            // ---------- Avance (optional, only when a partida with conceptos is chosen) ----------
            if (_conceptosForPartida.isNotEmpty) ...[
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
                            ..._conceptosForPartida.map((c) {
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
                          decoration: InputDecoration(
                            labelText: 'CANTIDAD EJECUTADA'
                                '${_selectedConceptoUnit() != null
                                ? ' (${_selectedConceptoUnit()})'
                                : ''}',
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
                onPressed: _isSaving ? null : _save,
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

  @override
  void initState() {
    super.initState();
    _syncThenLoad();
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
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        _showError('No tienes permiso para gestionar las partidas');
      } else {
        _showError('Error al agregar (HTTP ${resp.statusCode})');
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
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        _showError('No tienes permiso para editar las partidas');
      } else {
        _showError('Error al guardar (HTTP ${resp.statusCode})');
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
        _showError('No se pudo borrar (HTTP ${resp.statusCode})');
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
            // ---------- Add row ----------
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
                      trailing: IconButton(
                        icon: Icon(Icons.more_horiz,
                            color: Colors.grey[500]),
                        onPressed: () => _partidaMenu(p),
                      ),
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