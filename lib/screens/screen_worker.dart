import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/api.dart';
import 'package:control_app/screens/models/worker.dart';

/// Personal info card of a worker: NSS, CURP, phone, address,
/// blood type and emergency contact — with an edit form.
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
          _data = all.firstWhere(
                (w) => w['id'] == widget.worker.id,
            orElse: () => <String, dynamic>{},
          );
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
    if (_data == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _WorkerDetailsForm(
          workerId: widget.worker.id,
          data: _data!,
          isAdmin: _isAdmin,
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final d = _data ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text(w.name.toUpperCase()),
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
                    ClipOval(
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: w.photoUrl != null
                            ? CachedNetworkImage(
                          imageUrl: w.photoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => const Icon(
                              Icons.person,
                              size: 40),
                        )
                            : Container(
                          color: Colors.blue[400],
                          child: const Icon(Icons.person,
                              size: 40, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(w.role.toUpperCase(),
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
                            child: Text(w.project,
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
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _row(Icons.badge, 'NSS', d['nss']),
                    _row(Icons.fingerprint, 'CURP', d['curp']),
                    _row(Icons.phone, 'TELÉFONO', d['phone']),
                    _row(Icons.home, 'DIRECCIÓN', d['address']),
                    _row(Icons.bloodtype, 'TIPO DE SANGRE',
                        d['blood_type']),
                    _row(Icons.contact_emergency,
                        'CONTACTO DE EMERGENCIA',
                        d['emergency_contact_name']),
                    _row(Icons.phone_in_talk, 'TEL. DE EMERGENCIA',
                        d['emergency_contact_phone'],
                        last: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _infoCard('DATOS FISCALES Y BANCO', [
              _row(Icons.receipt_long, 'RFC', d['rfc']),
              _row(Icons.credit_card, 'NÚMERO DE TARJETA', d['card_number']),
              _row(Icons.account_balance, 'CLABE', d['clabe'], last: true),
            ]),
            if (_isAdmin) ...[
              const SizedBox(height: 12),
              _infoCard('NÓMINA', [
                _row(Icons.attach_money, 'SDI', _money(d['sdi'])),
                _row(Icons.more_time, 'COSTO HORA EXTRA',
                    _money(d['extra_hour_cost'])),
                _row(Icons.add_card, 'COMPENSACIÓN', _money(d['compensation'])),
                _row(Icons.money_off, 'PRÉSTAMO PERSONAL',
                    _money(d['personal_loan'])),
                _row(Icons.home_work, 'PRÉSTAMO INFONAVIT', d['infonavit']),
                _row(Icons.savings, 'PRÉSTAMO FONACOT', d['fonacot'],
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

  Widget _row(IconData icon, String label, dynamic value, {bool last = false}) {
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
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }

  String? _money(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    return n == null ? null : '\$ ${n.toStringAsFixed(2)}';
  }

  Widget _infoCard(String title, List<Widget> rows) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                  letterSpacing: 0.8,
                )),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Edit form for the personal fields
// ============================================================
class _WorkerDetailsForm extends StatefulWidget {
  final int workerId;
  final Map<String, dynamic> data;
  final bool isAdmin;
  const _WorkerDetailsForm(
      {required this.workerId, required this.data, required this.isAdmin});

  @override
  State<_WorkerDetailsForm> createState() => _WorkerDetailsFormState();
}

class _WorkerDetailsFormState extends State<_WorkerDetailsForm> {
  late final _nss =
  TextEditingController(text: widget.data['nss'] ?? '');
  late final _curp =
  TextEditingController(text: widget.data['curp'] ?? '');
  late final _phone =
  TextEditingController(text: widget.data['phone'] ?? '');
  late final _address =
  TextEditingController(text: widget.data['address'] ?? '');
  late final _blood =
  TextEditingController(text: widget.data['blood_type'] ?? '');
  late final _ecName = TextEditingController(
      text: widget.data['emergency_contact_name'] ?? '');
  late final _ecPhone = TextEditingController(
      text: widget.data['emergency_contact_phone'] ?? '');
  // Fiscal & bank (all users)
  late final _rfc = TextEditingController(text: widget.data['rfc'] ?? '');
  late final _card =
      TextEditingController(text: widget.data['card_number'] ?? '');
  late final _clabe = TextEditingController(text: widget.data['clabe'] ?? '');
  // Nómina (admins only)
  late final _sdi = TextEditingController(text: _fmt(widget.data['sdi']));
  late final _extraHour =
      TextEditingController(text: _fmt(widget.data['extra_hour_cost']));
  late final _compensation =
      TextEditingController(text: _fmt(widget.data['compensation']));
  late final _loan =
      TextEditingController(text: _fmt(widget.data['personal_loan']));
  late final _infonavit =
      TextEditingController(text: widget.data['infonavit'] ?? '');
  late final _fonacot =
      TextEditingController(text: widget.data['fonacot'] ?? '');
  bool _saving = false;

  static String _fmt(dynamic v) =>
      v == null ? '' : (v as num).toDouble().toStringAsFixed(2);

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  double? _money(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', ''));

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _save() async {
    final card = _card.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clabe = _clabe.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (card.isNotEmpty && card.length != 16) {
      _err('La tarjeta debe tener 16 dígitos');
      return;
    }
    if (clabe.isNotEmpty && clabe.length != 18) {
      _err('La CLABE debe tener 18 dígitos');
      return;
    }

    setState(() => _saving = true);
    try {
      final resp = await http.put(
        u('/workers/${widget.workerId}/details'),
        headers: await authHeaders(),
        body: jsonEncode({
          'nss': _v(_nss),
          'curp': _v(_curp),
          'phone': _v(_phone),
          'address': _v(_address),
          'blood_type': _v(_blood),
          'emergency_contact_name': _v(_ecName),
          'emergency_contact_phone': _v(_ecPhone),
          'rfc': _v(_rfc),
          'card_number': card.isEmpty ? null : card,
          'clabe': clabe.isEmpty ? null : clabe,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() => _saving = false);
        _err('Error al guardar (HTTP ${resp.statusCode})');
        return;
      }

      // Nómina (salary) — admins only
      if (widget.isAdmin) {
        final pr = await http.put(
          u('/workers/${widget.workerId}/payroll'),
          headers: await authHeaders(),
          body: jsonEncode({
            'sdi': _money(_sdi),
            'extra_hour_cost': _money(_extraHour),
            'compensation': _money(_compensation),
            'personal_loan': _money(_loan),
            'infonavit': _v(_infonavit),
            'fonacot': _v(_fonacot),
          }),
        );
        if (!mounted) return;
        if (pr.statusCode != 200) {
          setState(() => _saving = false);
          _err('Se guardó la ficha, pero la nómina no');
          return;
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _err('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
        {TextInputType? kb, bool money = false, int? maxLen}) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          keyboardType: kb,
          maxLength: maxLen,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 14),
            prefixText: money ? '\$ ' : null,
            counterText: '',
          ),
        ),
      );
    }

    Widget sectionCard(String title, List<Widget> children) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                    letterSpacing: 0.8,
                  )),
              ...children,
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EDITAR FICHA'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        backgroundColor: const Color(0xFF1C1CF0),
        iconTheme: const IconThemeData(color: Colors.white),
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
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    field(_nss, 'NSS', kb: TextInputType.number),
                    field(_curp, 'CURP'),
                    field(_phone, 'TELÉFONO', kb: TextInputType.phone),
                    field(_address, 'DIRECCIÓN'),
                    field(_blood, 'TIPO DE SANGRE (EJ. O+)'),
                    field(_ecName, 'CONTACTO DE EMERGENCIA'),
                    field(_ecPhone, 'TEL. DE EMERGENCIA',
                        kb: TextInputType.phone),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            sectionCard('DATOS FISCALES Y BANCO', [
              field(_rfc, 'RFC'),
              field(_card, 'NÚMERO DE TARJETA',
                  kb: TextInputType.number, maxLen: 19),
              field(_clabe, 'CLABE', kb: TextInputType.number, maxLen: 18),
            ]),
            if (widget.isAdmin) ...[
              const SizedBox(height: 12),
              sectionCard('NÓMINA', [
                field(_sdi, 'SDI',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                field(_extraHour, 'COSTO HORA EXTRA',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                field(_compensation, 'COMPENSACIÓN',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                field(_loan, 'PRÉSTAMO PERSONAL',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                field(_infonavit, 'PRÉSTAMO INFONAVIT'),
                field(_fonacot, 'PRÉSTAMO FONACOT'),
              ]),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1C1CF0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1C1CF0)))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'GUARDANDO...' : 'GUARDAR FICHA',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}