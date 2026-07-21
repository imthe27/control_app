import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/main.dart' show baseUrl;
import 'package:control_app/screens/models/worker.dart';

Uri _u(String path) => Uri.parse('$baseUrl$path');

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await http.get(_u('/workers?active_only=false'));
      if (!mounted) return;
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
          ],
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
}

// ============================================================
// Edit form for the personal fields
// ============================================================
class _WorkerDetailsForm extends StatefulWidget {
  final int workerId;
  final Map<String, dynamic> data;
  const _WorkerDetailsForm({required this.workerId, required this.data});

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
  bool _saving = false;

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final resp = await http.put(
        _u('/workers/${widget.workerId}/details'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nss': _v(_nss),
          'curp': _v(_curp),
          'phone': _v(_phone),
          'address': _v(_address),
          'blood_type': _v(_blood),
          'emergency_contact_name': _v(_ecName),
          'emergency_contact_phone': _v(_ecPhone),
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al guardar (HTTP ${resp.statusCode})'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
        {TextInputType? kb}) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          keyboardType: kb,
          decoration: InputDecoration(
              labelText: label, labelStyle: const TextStyle(fontSize: 14)),
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