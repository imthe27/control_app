import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'package:control_app/screens/models/worker.dart';
import 'package:control_app/screens/widgets/worker_card.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screen_worker_form.dart';

/// Read-only ficha of a worker: personal info, fiscal/bank data, nómina
/// (admins) and obra history. Editing is handled by WorkerFormScreen.
class WorkerDetailScreen extends StatefulWidget {
  final Worker worker;
  const WorkerDetailScreen({super.key, required this.worker});

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  Map<String, dynamic>? _data; // fresh row from the API (includes new fields)
  List<Map<String, dynamic>> _transfers = [];
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final headers = await authHeaders(json: false);
      final results = await Future.wait([
        http.get(u('/workers?active_only=false'), headers: headers),
        http.get(u('/workers/${widget.worker.id}/transfers'), headers: headers),
        http.get(u('/me'), headers: headers),
      ]);
      if (!mounted) return;
      final resp = results[0];
      if (results[1].statusCode == 200) {
        _transfers = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(results[1].bodyBytes)));
      }
      if (results[2].statusCode == 200) {
        _isAdmin = (jsonDecode(results[2].body)
            as Map<String, dynamic>)['is_admin'] == true;
      }
      if (resp.statusCode == 200) {
        final all = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
        setState(() {
          final found = all.firstWhere(
                (w) => w['id'] == widget.worker.id,
            orElse: () => <String, dynamic>{},
          );
          // Not found (e.g. deleted elsewhere): keep _data null so the ficha
          // shows "SIN REGISTRAR" and editing is blocked, instead of handing
          // the form an empty row and PUTting to /workers/null.
          _data = found.isEmpty ? null : found;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    if (_data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudieron cargar los datos del trabajador')),
      );
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerFormScreen(worker: _data),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final d = _data ?? {};
    // widget.worker is the row the list handed us; it goes stale after an
    // edit, so prefer the freshly loaded row whenever we have one.
    final name = (d['name'] as String?) ?? w.name;
    final role = (d['role'] as String?) ?? w.role;
    final project = (d['project'] as String?) ?? w.project;
    // Trust a loaded row even when photo_url is null (the photo was cleared).
    final photoUrl = _data != null ? d['photo_url'] as String? : w.photoUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(name.toUpperCase()),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'EDITAR FICHA',
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _edit,
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
        child: _loading
            ? const Center(
            child: CircularProgressIndicator(color: Colors.white))
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- Header ----------
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Values are the ones resolved above, which prefer the
                    // freshly loaded row over the list's stale copy. Passing
                    // resolved values rather than the Worker object keeps a
                    // second source of truth structurally impossible.
                    WorkerAvatar(
                      photoUrl: photoUrl,
                      diameter: 72,
                      placeholderColor: Colors.blue[400]!,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(role.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(project,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---------- Personal info ----------
            // This card was the only untitled one; the shared widget gives it
            // a heading to match every other section.
            WorkerSectionCard(title: 'INFORMACIÓN PERSONAL', children: [
              _row(Icons.badge, 'NSS', d['nss'], copyValue: d['nss']),
              _row(Icons.fingerprint, 'CURP', d['curp'], copyValue: d['curp']),
              _row(Icons.phone, 'TELÉFONO', d['phone'], actions: [
                _action(Icons.call, 'LLAMAR',
                    () => _dial(d['phone'].toString())),
              ]),
              _row(Icons.home, 'DIRECCIÓN', d['address'], actions: [
                _action(Icons.map, 'VER EN MAPA',
                    () => _openMaps(d['address'].toString())),
              ]),
              _row(Icons.bloodtype, 'TIPO DE SANGRE', d['blood_type']),
              _row(Icons.contact_emergency, 'CONTACTO DE EMERGENCIA',
                  d['emergency_contact_name']),
              _row(Icons.phone_in_talk, 'TEL. DE EMERGENCIA',
                  d['emergency_contact_phone'],
                  last: true,
                  actions: [
                    _action(Icons.call, 'LLAMAR',
                        () => _dial(d['emergency_contact_phone'].toString())),
                  ]),
            ]),
            const SizedBox(height: 12),
            WorkerSectionCard(title: 'DATOS FISCALES Y BANCO', children: [
              _row(Icons.receipt_long, 'RFC', d['rfc'], copyValue: d['rfc']),
              _row(Icons.credit_card, 'NÚMERO DE TARJETA',
                  _maskCard(d['card_number']),
                  copyValue: d['card_number']),
              _row(Icons.account_balance, 'CLABE', d['clabe'],
                  copyValue: d['clabe'], last: true),
            ]),
            if (_isAdmin) ...[
              const SizedBox(height: 12),
              WorkerSectionCard(title: 'NÓMINA', children: [
                _row(Icons.attach_money, 'SDI', _money(d['sdi'])),
                _row(Icons.more_time, 'COSTO HORA EXTRA',
                    _money(d['extra_hour_cost'])),
                _row(Icons.add_card, 'COMPENSACIÓN', _money(d['compensation'])),
                _row(Icons.add_card, 'COMPENSACIÓN 2',
                    _money(d['compensation_2'])),
                _row(Icons.money_off, 'PRÉSTAMO PERSONAL',
                    _money(d['personal_loan'])),
                _row(Icons.home_work, 'PRÉSTAMO INFONAVIT', _money(d['infonavit'])),
                _row(Icons.savings, 'PRÉSTAMO FONACOT', _money(d['fonacot']),
                    last: true),
              ]),
            ],
            _buildHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_transfers.isEmpty) return const SizedBox.shrink();
    String fmt(String? iso) {
      if (iso == null) return '';
      try {
        final dt = DateTime.parse(iso);
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {
        return iso;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 15, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text('HISTORIAL DE OBRAS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                        letterSpacing: 0.8,
                      )),
                ],
              ),
              const SizedBox(height: 4),
              ..._transfers.map((t) {
                final from = t['from'] ?? 'SIN OBRA';
                final to = t['to'] ?? 'SIN OBRA';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.arrow_forward,
                            size: 14, color: Colors.grey[400]),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '$from  \u2192  ',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[600])),
                              TextSpan(
                                  text: '$to',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ])),
                            const SizedBox(height: 2),
                            Text(
                              [
                                fmt(t['date']),
                                if (t['reason'] != null) t['reason'],
                                if (t['moved_by'] != null)
                                  'por ${t['moved_by']}',
                              ].join('  \u00b7  '),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// Action icon sitting alongside the copy button, styled to match it.
  Widget _action(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 19, color: const Color(0xFF1C1CF0)),
      onPressed: onPressed,
    );
  }

  Widget _row(IconData icon, String label, dynamic value,
      {bool last = false, dynamic copyValue, List<Widget> actions = const []}) {
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
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      text ?? 'SIN REGISTRAR',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle:
                        text != null ? FontStyle.normal : FontStyle.italic,
                        fontWeight:
                        text != null ? FontWeight.w500 : FontWeight.normal,
                        color: text != null ? Colors.black87 : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              if (copyValue != null &&
                  copyValue.toString().trim().isNotEmpty)
                IconButton(
                  tooltip: 'COPIAR',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy, size: 17, color: Colors.grey[500]),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: copyValue.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copiado')),
                    );
                  },
                ),
              // Only offered when there is actually a value to act on.
              if (text != null) ...actions,
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }

  /// Launches [uri], telling the user when nothing handled it.
  ///
  /// A failed launch is silent by default — no exception, no visible effect —
  /// which is indistinguishable from a dead button. The snackbar is the only
  /// thing that makes "no app can open this" legible.
  Future<void> _launch(Uri uri, String failureMessage) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failureMessage)),
    );
  }

  /// Strips formatting so 'tel:' gets digits only. Keeps a leading + for
  /// international numbers.
  void _dial(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    _launch(Uri(scheme: 'tel', path: digits), 'No se pudo abrir el teléfono');
  }

  /// DIRECCIÓN is free text — accents, commas, '#'. Uri.https percent-encodes
  /// the query itself, so this must never be built by concatenation.
  ///
  /// The https form is used rather than 'geo:' because it falls back to a
  /// browser when no maps app is installed, instead of failing silently.
  void _openMaps(String address) {
    final query = address.trim();
    if (query.isEmpty) return;
    _launch(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      }),
      'No se pudo abrir el mapa',
    );
  }

  String _maskCard(dynamic n) {
    final s = (n ?? '').toString();
    if (s.length < 4) return '';
    return '•••• •••• •••• ${s.substring(s.length - 4)}';
  }

  String? _money(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    return n == null ? null : '\$ ${n.toStringAsFixed(2)}';
  }

}
