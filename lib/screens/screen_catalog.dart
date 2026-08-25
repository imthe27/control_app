import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'screen_project_selection.dart' show resolvePhotoUrl;
import 'package:control_app/api.dart';

/// CATÁLOGO tab: the concept catalog as editable data.
class CatalogTab extends StatefulWidget {
  final Map<String, dynamic> project;
  const CatalogTab({super.key, required this.project});

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _partidas = [];
  bool _loading = true;
  bool _canWrite = false;
  bool _importing = false;

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
        http.get(u('/projects/$_projectId/catalog-items'), headers: headers),
        http.get(u('/me'), headers: headers),
        http.get(u('/projects/$_projectId/partidas'), headers: headers),
      ]);
      if (!mounted) return;
      // Admin, full stop. Every affordance this flag gates — EXCEL import,
      // AGREGAR, the row tap and the ⋯ menu — calls a route that became
      // admin-only on 2026-08-17.
      //
      // It used to read `is_admin || username == encargado_username`, mirroring
      // a backend tier that no longer exists: `_can_write_project` is deleted
      // and `projects.encargado_username` grants nothing. That expression was
      // equivalent to this one only by accident, because no obra has an
      // encargado set — assign one and this screen would have offered that user
      // buttons that 403 on every tap.
      var canWrite = false;
      if (results[1].statusCode == 200) {
        final me = jsonDecode(results[1].body) as Map<String, dynamic>;
        canWrite = me['is_admin'] == true;
      }
      setState(() {
        _items = results[0].statusCode == 200
            ? List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(results[0].bodyBytes)))
            : [];
        _partidas = results[2].statusCode == 200
            ? List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(results[2].bodyBytes)))
            : [];
        _canWrite = canWrite;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : null,
    ));
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (picked == null || picked.files.single.path == null) return;

    bool replace = false;
    if (_items.isNotEmpty) {
      final r = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('IMPORTAR EXCEL'),
          content: const Text('¿Reemplazar el catálogo actual o agregar al final?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('AGREGAR')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('REEMPLAZAR')),
          ],
        ),
      );
      if (r == null) return;
      replace = r;
    }

    setState(() => _importing = true);
    try {
      final headers = await authHeaders(json: false);
      final req = http.MultipartRequest(
          'POST', u('/projects/$_projectId/catalog-import?replace=$replace'))
        ..headers.addAll(headers)
        ..files.add(await http.MultipartFile.fromPath(
            'file', picked.files.single.path!));
      final resp = await http.Response.fromStream(await req.send());
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final n = jsonDecode(resp.body)['imported'];
        _snack('$n conceptos importados');
        _load();
      } else {
        // Was a bare jsonDecode here, which throws on a non-JSON body and
        // turned a failed import into the catch-all 'Error: $e'.
        _snack('Error al importar: ${serverMessage(resp) ?? resp.statusCode}',
            error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _itemDialog({Map<String, dynamic>? item}) async {
    final code = TextEditingController(text: item?['code'] ?? '');
    final name = TextEditingController(text: item?['name'] ?? '');
    final unit = TextEditingController(text: item?['unit'] ?? '');
    final qty = TextEditingController(text: item?['quantity']?.toString() ?? '');
    final price = TextEditingController(text: item?['unit_price']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(item == null ? 'NUEVO CONCEPTO' : 'EDITAR CONCEPTO'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                SizedBox(
                    width: 70,
                    child: TextField(
                        controller: code,
                        decoration: const InputDecoration(
                            labelText: 'CLAVE', isDense: true))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: unit,
                        decoration: const InputDecoration(
                            labelText: 'UNIDAD', isDense: true))),
              ]),
              TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'CONCEPTO / PARTIDA', isDense: true)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: qty,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'CANTIDAD', isDense: true))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'P.U. \$', isDense: true))),
              ]),
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
              child: const Text('GUARDAR')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      _snack('El concepto necesita nombre', error: true);
      return;
    }

    final body = jsonEncode({
      'code': code.text.trim().isEmpty ? null : code.text.trim(),
      'name': name.text.trim(),
      'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
      'quantity': double.tryParse(qty.text.trim().replaceAll(',', '')),
      'unit_price': double.tryParse(price.text.trim().replaceAll(',', '')),
    });

    try {
      final headers = await authHeaders();
      final resp = item == null
          ? await http.post(u('/projects/$_projectId/catalog-items'),
          headers: headers, body: body)
          : await http.put(u('/catalog-items/${item['id']}'),
          headers: headers, body: body);
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _load();
      } else {
        // Catalog writes are admin-only since 2026-08-17: a non-admin gets
        // `Solo administradores`, which beats a bare 403.
        _snack(serverMessage(resp) ??
            'Error al guardar (HTTP ${resp.statusCode})', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }


  double _pct(double executed, double qty) =>
      qty <= 0 ? 0 : (executed / qty).clamp(0.0, 1.0);

  /// Same rule as the logbook: whole quantities without the trailing .0
  /// (0 / 133.1, not 0.0 / 133.1).
  String _fmtQty(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);

  /// Three-dots menu for a concepto: edit or delete.
  void _itemMenu(Map<String, dynamic> it) {
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
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF1C1CF0)),
              title: const Text('EDITAR CONCEPTO'),
              onTap: () {
                Navigator.pop(ctx);
                _itemDialog(item: it);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('BORRAR CONCEPTO'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteItem(it);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('BORRAR CONCEPTO'),
        content: Text(
            '¿Borrar "${item['name']}"? También se borrará su avance registrado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('BORRAR')),
        ],
      ),
    );
    if (ok == true) _deleteItem(item);
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    try {
      final headers = await authHeaders();
      final resp = await http.delete(u('/catalog-items/${item['id']}'),
          headers: headers);
      if (!mounted) return;
      resp.statusCode == 200
          ? _load()
          : _snack(serverMessage(resp) ??
              'No se pudo borrar (HTTP ${resp.statusCode})', error: true);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final hasPdf = resolvePhotoUrl(widget.project['catalog_pdf']) != null;

    return Column(
      children: [
        // ---------- Actions ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              if (_canWrite) ...[
                _ActionChip(
                  icon: Icons.upload_file,
                  label: 'EXCEL',
                  busy: _importing,
                  onTap: _importExcel,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.add,
                  label: 'AGREGAR',
                  onTap: () => _itemDialog(),
                ),
              ],
              const Spacer(),
              if (hasPdf)
                _ActionChip(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CatalogPdfScreen(
                        url: resolvePhotoUrl(widget.project['catalog_pdf'])!,
                        title: widget.project['name'] ?? 'CATÁLOGO',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ---------- Items ----------
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _items.isEmpty
                ? ListView(children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.18),
              const Icon(Icons.menu_book, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _canWrite
                      ? 'SIN CATÁLOGO\nImporta un Excel o agrega conceptos'
                      : 'SIN CATÁLOGO',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                ),
              ),
            ])
                : Builder(builder: (context) {
              // Group items by partida
              final byPartida = <int?, List<Map<String, dynamic>>>{};
              for (final it in _items) {
                byPartida.putIfAbsent(it['partida_id'], () => []).add(it);
              }
              final orderedKeys = <int?>[
                ..._partidas
                    .where((p) => byPartida.containsKey(p['id']))
                    .map((p) => p['id'] as int),
                if (byPartida.containsKey(null)) null,
              ];

              final children = <Widget>[];
              for (final key in orderedKeys) {
                final items = byPartida[key]!;
                final partida = key == null
                    ? null
                    : _partidas.firstWhere((p) => p['id'] == key);
                // Server-computed, from GET /projects/{id}/partidas. It is
                // weighted by unit_price, which non-admins do not receive
                // (questionnaire 6.2) — that is the whole reason this is no
                // longer worked out here.
                //
                // It replaced a local weightedPct() that skipped any item
                // without a price and returned 0 when that left the denominator
                // empty. The moment prices are withheld, that meant every
                // partida drawing a confident 0% — indistinguishable from
                // "nothing built yet", with no error anywhere to notice.
                //
                // null means there is nothing priced to measure: an empty
                // partida, or the SIN PARTIDA bucket, which has no row in
                // /partidas to carry a number. Rendered as an em dash.
                final pct = (partida?['progress'] as num?)?.toDouble();
                children.add(Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        partida == null
                            ? 'SIN PARTIDA'
                            : '${partida['code'] ?? ''} · ${partida['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                        pct == null
                            ? '—'
                            : '${(pct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ]),
                ));
                // No bar when there is nothing to measure. A zero-length bar
                // beside an em dash would put back the same "0% means nothing
                // built" reading the dash exists to avoid.
                if (pct != null) {
                  children.add(ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: Colors.white24,
                        color: Colors.white),
                  ));
                }
                children.add(const SizedBox(height: 8));
                for (final it in items) {
                  final q = (it['quantity'] as num?)?.toDouble();
                  final ex = (it['executed'] as num?)?.toDouble() ?? 0;
                  children.add(Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      dense: true,
                      onTap:
                      _canWrite ? () => _itemDialog(item: it) : null,
                      leading: it['code'] != null
                          ? CircleAvatar(
                          radius: 17,
                          backgroundColor: const Color(0xFF1C1CF0)
                              .withValues(alpha: 0.1),
                          child: Text(it['code'],
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1CF0))))
                          : const Icon(Icons.notes,
                          color: Color(0xFF1C1CF0)),
                      title: Text(it['name'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      subtitle: q == null
                          ? null
                          : Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${_fmtQty(ex)} / ${_fmtQty(q)} ${it['unit'] ?? ''}  ·  ${(_pct(ex, q) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius:
                            BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                                value: _pct(ex, q),
                                minHeight: 4,
                                backgroundColor: Colors.grey[200],
                                color: const Color(0xFF1C1CF0)),
                          ),
                        ],
                      ),
                      trailing: _canWrite
                          ? IconButton(
                        icon: Icon(Icons.more_horiz,
                            size: 20, color: Colors.grey[500]),
                        onPressed: () => _itemMenu(it),
                      )
                          : null,
                    ),
                  ));
                }
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: children,
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            busy
                ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 16, color: const Color(0xFF1C1CF0)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1CF0))),
          ]),
        ),
      ),
    );
  }
}

/// Full-screen cached PDF viewer (moved out of the old catalog tab).
class CatalogPdfScreen extends StatefulWidget {
  final String url;
  final String title;
  const CatalogPdfScreen({super.key, required this.url, required this.title});

  @override
  State<CatalogPdfScreen> createState() => _CatalogPdfScreenState();
}

class _CatalogPdfScreenState extends State<CatalogPdfScreen> {
  String? _path;
  String? _error;
  int _pages = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final filename = Uri.parse(widget.url).pathSegments.last;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/catalogs/$filename');
      if (!await file.exists()) {
        // Signed URL AND session, per questionnaire 8.3 — the signature alone
        // stopped being sufficient. The header is inert against a server that
        // does not yet require it, which is what lets this ship ahead of the
        // backend gate.
        //
        // ⚠ This screen keeps its OWN disk cache, above, independent of
        // CachedNetworkImage's. clearMediaCaches() empties both; a test that
        // only clears the image cache will still open this document from disk
        // and appear to pass.
        final resp = await http.get(Uri.parse(widget.url),
            headers: await authHeaders(json: false));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        await file.create(recursive: true);
        await file.writeAsBytes(resp.bodyBytes);
      }
      if (mounted) setState(() => _path = file.path);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el PDF');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _error != null
          ? Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('REINTENTAR')),
          ]))
          : _path == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
        PDFView(
          filePath: _path!,
          autoSpacing: true,
          onRender: (p) => setState(() => _pages = p ?? 0),
          onPageChanged: (p, _) => setState(() => _page = p ?? 0),
        ),
        if (_pages > 0)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${_page + 1} / $_pages',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}