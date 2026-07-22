import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:control_app/main.dart' show baseUrl;

/// Full-screen form to register a new worker: photo, basic data
/// and (optionally) the personal info shown in their ficha.
class WorkerFormScreen extends StatefulWidget {
  const WorkerFormScreen({super.key});

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _project = TextEditingController();
  final _nss = TextEditingController();
  final _curp = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _blood = TextEditingController();
  final _ecName = TextEditingController();
  final _ecPhone = TextEditingController();

  File? _photo;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name, _role, _project, _nss, _curp,
      _phone, _address, _blood, _ecName, _ecPhone
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  bool get _hasDetails => [
    _nss, _curp, _phone, _address, _blood, _ecName, _ecPhone
  ].any((c) => c.text.trim().isNotEmpty);

  // ---------- Photo ----------
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
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
              leading: const Icon(Icons.photo_camera, color: Color(0xFF1C1CF0)),
              title: const Text('TOMAR FOTO'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF1C1CF0)),
              title: const Text('ELEGIR DE GALERÍA'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('QUITAR FOTO'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked != null && mounted) {
      setState(() => _photo = File(picked.path));
    }
  }

  Future<String?> _uploadPhoto(File file) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/upload-photo/'));
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final resp = await req.send();
    if (resp.statusCode == 200) {
      final body = jsonDecode(await resp.stream.bytesToString());
      return body['filename'];
    }
    return null;
  }

  // ---------- Save ----------
  Future<void> _save() async {
    final name = _name.text.trim();
    final project = _project.text.trim();
    if (name.isEmpty) {
      _showError('El nombre es obligatorio');
      return;
    }

    setState(() => _saving = true);
    try {
      String? photoFilename;
      if (_photo != null) {
        photoFilename = await _uploadPhoto(_photo!);
        if (photoFilename == null) {
          setState(() => _saving = false);
          _showError('No se pudo subir la foto');
          return;
        }
      }

      final resp = await http.post(
        Uri.parse('$baseUrl/workers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'project': project,
          'role': _role.text.trim(),
          'photo_url': photoFilename,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() => _saving = false);
        _showError('Error al guardar (HTTP ${resp.statusCode})');
        return;
      }

      // Personal info, only if something was filled in
      final newId = jsonDecode(resp.body)['id'];
      if (newId != null && _hasDetails) {
        await http.put(
          Uri.parse('$baseUrl/workers/$newId/details'),
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
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Error: $e');
    }
  }

  // ---------- UI helpers ----------
  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
                letterSpacing: 0.8,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? kb, bool caps = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        keyboardType: kb,
        textCapitalization:
        caps ? TextCapitalization.characters : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 14),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NUEVO TRABAJADOR'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
            // ---------- Photo ----------
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _pickPhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: Colors.white24,
                      backgroundImage:
                      _photo != null ? FileImage(_photo!) : null,
                      child: _photo == null
                          ? const Icon(Icons.person,
                          size: 56, color: Colors.white70)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_camera,
                            size: 18, color: Color(0xFF1C1CF0)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _photo == null ? 'AGREGAR FOTO' : 'CAMBIAR FOTO',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Basic data ----------
            _sectionCard('DATOS GENERALES', [
              _field(_name, 'NOMBRE COMPLETO *', caps: true),
              _field(_role, 'PUESTO'),
              _field(_project, 'OBRA ASIGNADA', caps: true),
            ]),
            const SizedBox(height: 12),

            // ---------- Personal info ----------
            _sectionCard('INFORMACIÓN PERSONAL (OPCIONAL)', [
              _field(_nss, 'NSS', kb: TextInputType.number),
              _field(_curp, 'CURP', caps: true),
              _field(_phone, 'TELÉFONO', kb: TextInputType.phone),
              _field(_address, 'DIRECCIÓN'),
              _field(_blood, 'TIPO DE SANGRE (EJ. O+)', caps: true),
            ]),
            const SizedBox(height: 12),

            // ---------- Emergency ----------
            _sectionCard('CONTACTO DE EMERGENCIA (OPCIONAL)', [
              _field(_ecName, 'NOMBRE', caps: true),
              _field(_ecPhone, 'TELÉFONO', kb: TextInputType.phone),
            ]),
            const SizedBox(height: 20),

            // ---------- Save ----------
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
                    : const Icon(Icons.person_add),
                label: Text(
                  _saving ? 'GUARDANDO...' : 'AGREGAR TRABAJADOR',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}