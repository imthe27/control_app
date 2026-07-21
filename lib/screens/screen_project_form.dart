import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:control_app/main.dart' show baseUrl;
import 'screen_project_selection.dart' show resolvePhotoUrl;

Uri _u(String path) => Uri.parse('$baseUrl$path');

/// Full-screen form to create or edit a project.
/// Pops with `true` when the save succeeded so the caller can refresh.
class ProjectFormScreen extends StatefulWidget {
  final Map<String, dynamic>? projectToEdit;

  const ProjectFormScreen({super.key, this.projectToEdit});

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _clientController = TextEditingController();
  final _contractNameController = TextEditingController();
  final _contractNumberController = TextEditingController();
  final _amountController = TextEditingController();
  final _encargadoController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  File? _pickedImage;
  File? _pickedCatalog;
  bool _isSaving = false;

  bool get isEditing => widget.projectToEdit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.projectToEdit;
    if (p != null) {
      _nameController.text = p['name'] ?? '';
      _addressController.text = p['address'] ?? '';
      _clientController.text = p['client_name'] ?? '';
      _contractNameController.text = p['contract_name'] ?? '';
      _contractNumberController.text = p['contract_number'] ?? '';
      _amountController.text = p['contract_amount']?.toString() ?? '';
      _encargadoController.text = p['encargado_username'] ?? '';
      _startDate = _parseIso(p['start_date']);
      _endDate = _parseIso(p['end_date']);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _clientController.dispose();
    _contractNameController.dispose();
    _contractNumberController.dispose();
    _amountController.dispose();
    _encargadoController.dispose();
    super.dispose();
  }

  // ---------------- helpers ----------------

  DateTime? _parseIso(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);

  String? _isoOrNull(DateTime? d) =>
      d == null ? null : DateFormat('yyyy-MM-dd').format(d);

  String? _textOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  String? _catalogLabel() {
    if (_pickedCatalog != null) {
      return _pickedCatalog!.path.split('/').last.split('\\').last;
    }
    final existing = widget.projectToEdit?['catalog.pdf'];
    if (existing != null && existing.toString().isNotEmpty) {
      final name = Uri.parse(existing.toString()).pathSegments.lastOrNull;
      return name ?? existing.toString();
    }
    return null;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ---------------- HTTP ----------------

  Future<String?> _uploadImage(File imageFile) async {
    final request = http.MultipartRequest('POST', _u('/upload-photo/'));
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final body = jsonDecode(await response.stream.bytesToString());
      return body['filename'];
    }
    return null;
  }

  Future<String?> _uploadCatalog(File pdfFile) async {
    final request = http.MultipartRequest('POST', _u('/upload-catalog'));
    request.files.add(await http.MultipartFile.fromPath('file', pdfFile.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final body = jsonDecode(await response.stream.bytesToString());
      return body['filename'];
    }
    return null;
  }

  Future<void> _deleteOldImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return;
    try {
      final filename = Uri.parse(photoUrl).pathSegments.lastOrNull;
      if (filename == null || filename.isEmpty) return;
      // Trailing slash matters: without it FastAPI answers 307 and
      // Dart's http client does not follow redirects for DELETE.
      await http.delete(
        _u('/delete-photo/?filename=${Uri.encodeQueryComponent(filename)}'),
      );
    } catch (e) {
      debugPrint('Error deleting old image: $e');
    }
  }

  Map<String, dynamic> _payload(String? photoFilename, String? catalogFilename) {
    final p = widget.projectToEdit;
    return {
      'catalog_pdf': catalogFilename ?? p?['catalog_pdf'],
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'status': p?['status'] ?? 'EN PROCESO',
      'progress': p?['progress'] ?? 0.6,
      'photo_url': photoFilename ?? p?['photo_url'],
      'contract_name': _textOrNull(_contractNameController),
      'contract_number': _textOrNull(_contractNumberController),
      'client_name': _textOrNull(_clientController),
      'contract_amount':
      double.tryParse(_amountController.text.trim().replaceAll(',', '')),
      'encargado_username': _textOrNull(_encargadoController),
      'start_date': _isoOrNull(_startDate),
      'end_date': _isoOrNull(_endDate),
    };
  }

  Future<void> _deleteProject() async {
    final p = widget.projectToEdit!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('BORRAR OBRA'),
        content: Text(
            '¿Borrar "${p['name']}"?\n\nSe borrarán su bitácora, catálogo, avance y asistencias. Los trabajadores quedarán sin obra asignada. Esta acción no se puede deshacer.'),
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
    if (ok != true) return;

    setState(() => _isSaving = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      final resp = await http.delete(
        Uri.parse('$baseUrl/projects/${p['id']}'),
        headers: {
          if (token != null && token != 'guest') 'Authorization': 'Bearer $token',
        },
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context, true);
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        setState(() => _isSaving = false);
        _showError('No tienes permiso para borrar esta obra');
      } else {
        setState(() => _isSaving = false);
        _showError('Error al borrar (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Error: $e');
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    if (name.isEmpty || address.isEmpty) {
      _showError('El nombre y la dirección son obligatorios');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Upload the new image first (old one is untouched if this fails)
      String? photoFilename;
      if (_pickedImage != null) {
        photoFilename = await _uploadImage(_pickedImage!);
        if (photoFilename == null) {
          setState(() => _isSaving = false);
          _showError('Error al subir la imagen');
          return;
        }
      }

      String? catalogFilename;
      if (_pickedCatalog != null) {
        catalogFilename = await _uploadCatalog(_pickedCatalog!);
        if (catalogFilename == null) {
          setState(() => _isSaving = false);
          _showError('Error al subir el catálogo');
          return;
        }
      }

      // 2. Create or update
      final http.Response response;
      if (isEditing) {
        response = await http.put(
          _u('/projects/${widget.projectToEdit!['id']}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_payload(photoFilename, catalogFilename)),
        );
      } else {
        response = await http.post(
          _u('/projects'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_payload(photoFilename, catalogFilename)),
        );
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        setState(() => _isSaving = false);
        _showError('Error al guardar: ${response.body}');
        return;
      }

      // 3. Delete the replaced image only after a successful save
      if (isEditing && photoFilename != null) {
        await _deleteOldImage(widget.projectToEdit!['photo_url']);
      }
      if (isEditing && catalogFilename != null) {
        await _deleteOldImage(widget.projectToEdit!['catalog_pdf']);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Error: $e');
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final existingPhoto = resolvePhotoUrl(widget.projectToEdit?['photo_url']);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'EDITAR OBRA' : 'NUEVA OBRA'),
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
            // ---------- Photo picker ----------
            GestureDetector(
              onTap: () async {
                final picked =
                await ImagePicker().pickImage(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() => _pickedImage = File(picked.path));
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_pickedImage != null)
                        Image.file(_pickedImage!, fit: BoxFit.cover)
                      else if (existingPhoto != null)
                        CachedNetworkImage(
                          imageUrl: existingPhoto,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.white24,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                          errorWidget: (context, url, error) =>
                              Container(color: Colors.white24),
                        )
                      else
                        Container(
                          color: Colors.white.withValues(alpha: 0.15),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, color: Colors.white70, size: 40),
                                SizedBox(height: 8),
                                Text(
                                  'AGREGAR FOTO',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Small camera badge when a photo is already shown
                      if (_pickedImage != null || existingPhoto != null)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 20,
                              color: Color(0xFF1C1CF0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---------- General ----------
            _SectionCard(
              title: 'INFORMACIÓN GENERAL',
              children: [
                _Field(controller: _nameController, label: 'NOMBRE DE LA OBRA *'),
                _Field(controller: _addressController, label: 'DIRECCIÓN *'),
              ],
            ),
            const SizedBox(height: 12),

            // ---------- Contract ----------
            _SectionCard(
              title: 'CONTRATO',
              children: [
                _Field(controller: _clientController, label: 'CLIENTE'),
                _Field(controller: _contractNameController, label: 'NOMBRE DEL CONTRATO'),
                _Field(controller: _contractNumberController, label: 'NO. DE CONTRATO'),
                _Field(
                  controller: _amountController,
                  label: 'MONTO',
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  prefixText: '\$ ',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'INICIO',
                        date: _startDate,
                        onPick: (d) => setState(() => _startDate = d),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: 'TÉRMINO',
                        date: _endDate,
                        onPick: (d) => setState(() => _endDate = d),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------- Concept catalog ------
            _SectionCard(
              title: 'CATALÁGO DE CONCEPTOS',
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() =>
                            _pickedCatalog = File(result.files.single.path!));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf,
                          color: _catalogLabel() == null
                          ? Colors.grey[400]
                          : Colors.red[400]),
                          const SizedBox(width:12),
                          Expanded(
                            child: Text(
                              _catalogLabel() ?? 'AGREGAR CATÁLOGO',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: _catalogLabel() == null
                                  ? Colors.grey[500]
                                    : Colors.black87,
                                fontWeight: _catalogLabel() == null
                                  ? FontWeight.normal
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.upload_file,
                            size: 20, color: Colors.grey[500]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------- Responsible ----------
            _SectionCard(
              title: 'RESPONSABLE',
              children: [
                _Field(
                  controller: _encargadoController,
                  label: 'ENCARGADO (USUARIO DE LA APP)',
                ),
              ],
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
                      : (isEditing ? 'GUARDAR CAMBIOS' : 'CREAR OBRA'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            // ------ delete -------
            if (isEditing) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isSaving ? null : _deleteProject,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('BORRAR OBRA',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Small building blocks
// ============================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? prefixText;

  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.prefixText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefixText,
          labelStyle: const TextStyle(fontSize: 14),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF1C1CF0), width: 2),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPick;

  const _DateField({
    required this.label,
    required this.date,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2015),
          lastDate: DateTime(2040),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          labelStyle: const TextStyle(fontSize: 14),
        ),
        child: Text(
          date != null ? DateFormat('dd/MM/yyyy').format(date!) : '—',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}