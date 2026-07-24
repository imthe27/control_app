import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:control_app/main.dart' show baseUrl;
import 'package:control_app/screens/models/worker.dart';
import 'screen_worker_form.dart';

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
  bool _isAdmin = false;

  static Future<Map<String, String>> _auth() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    return {
      if (token != null && token != 'guest') 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final headers = await _auth();
      final results = await Future.wait([
        http.get(_u('/workers?active_only=false'), headers: headers),
        http.get(_u('/me'), headers: headers),
      ]);
      if (!mounted) return;
      final resp = results[0];
      if (results[1].statusCode == 200) {
        final me = jsonDecode(results[1].body) as Map<String, dynamic>;
        _isAdmin = me['is_admin'] == true;
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
        builder: (_) => WorkerFormScreen(worker: _data),
      ),
    );
    if (saved == true) _load();
  }

  String _maskCard(dynamic n) {
    final s = (n ?? '').toString();
    if (s.length < 4) return '';
    return '•••• •••• •••• ${s.substring(s.length - 4)}';
  }

  String _money(dynamic v) {
    if (v == null) return '';
    final d = (v as num).toDouble();
    return '\$${d.toStringAsFixed(2)}';
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
                        d['emergency_contact_phone']),
                    _row(Icons.receipt_long, 'RFC', d['rfc'], last: true),
                  ],
                ),
              ),
            ),

            // ---------- Bank & payroll (admins only) ----------
            if (_isAdmin) ...[
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 2),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'NOMINA Y BANCO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[600],
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _row(Icons.credit_card, 'TARJETA',
                          _maskCard(d['card_number']),
                          copyValue: d['card_number']),
                      _row(Icons.account_balance, 'CLABE', d['clabe'],
                          copyValue: d['clabe']),
                      _row(Icons.payments, 'SDI', _money(d['sdi'])),
                      _row(Icons.more_time, 'COSTO HORA EXTRA',
                          _money(d['extra_hour_cost'])),
                      _row(Icons.card_giftcard, 'COMPENSACION',
                          _money(d['compensation'])),
                      _row(Icons.request_quote, 'PRESTAMO PERSONAL',
                          _money(d['personal_loan'])),
                      _row(Icons.house, 'PRESTAMO INFONAVIT', d['infonavit']),
                      _row(Icons.store, 'PRESTAMO FONACOT', d['fonacot'], last: true),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, dynamic value,
      {bool last = false, dynamic copyValue}) {
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
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }
}