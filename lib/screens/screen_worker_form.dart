import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:control_app/api.dart';
import 'package:control_app/screens/models/worker_roles.dart';
import 'package:control_app/screens/widgets/worker_card.dart';

/// Full-screen form to register a new worker: photo, basic data
/// and (optionally) the personal info shown in their ficha.
class WorkerFormScreen extends StatefulWidget {
  /// Row from GET /workers. Null = create mode.
  final Map<String, dynamic>? worker;
  const WorkerFormScreen({super.key, this.worker});

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _rfc = TextEditingController();
  final _cardNumber = TextEditingController();
  final _clabe = TextEditingController();
  final _sdi = TextEditingController();
  final _extraHour = TextEditingController();
  final _compensation = TextEditingController();
  final _compensation2 = TextEditingController();
  final _loan = TextEditingController();
  final _infonavit = TextEditingController();
  final _fonacot = TextEditingController();
  final _nss = TextEditingController();
  final _curp = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _blood = TextEditingController();
  final _ecName = TextEditingController();
  final _ecPhone = TextEditingController();

  File? _photo;
  bool _saving = false;
  bool _isAdmin = false;
  String? _existingPhoto;   // absolute URL of the current photo
  bool _photoCleared = false;

  bool get isEditing => widget.worker != null;
  int? get _workerId => widget.worker?['id'];

  // Obra assignment
  List<Map<String, dynamic>> _projects = [];
  int? _projectId;
  bool _loadingProjects = true;

  // Role. _role holds the value that gets saved; the dropdown drives it.
  List<String> _roles = [];
  bool _loadingRoles = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadRoles();
    _loadMe();
    final w = widget.worker;
    if (w != null) {
      _name.text = (w['name'] ?? '').toString();
      _role.text = (w['role'] ?? '').toString();
      _nss.text = (w['nss'] ?? '').toString();
      _curp.text = (w['curp'] ?? '').toString();
      _phone.text = (w['phone'] ?? '').toString();
      _address.text = (w['address'] ?? '').toString();
      _blood.text = (w['blood_type'] ?? '').toString();
      _ecName.text = (w['emergency_contact_name'] ?? '').toString();
      _ecPhone.text = (w['emergency_contact_phone'] ?? '').toString();
      _rfc.text = (w['rfc'] ?? '').toString();
      _cardNumber.text = (w['card_number'] ?? '').toString();
      _clabe.text = (w['clabe'] ?? '').toString();
      _sdi.text = _fmt(w['sdi']);
      _extraHour.text = _fmt(w['extra_hour_cost']);
      _compensation.text = _fmt(w['compensation']);
      _compensation2.text = _fmt(w['compensation_2']);
      _loan.text = _fmt(w['personal_loan']);
      _infonavit.text = _fmt(w['infonavit']);
      _fonacot.text = _fmt(w['fonacot']);
      _existingPhoto = w['photo_url'];
      _projectId = w['project_id'];
    }
  }

  /// Money value -> "1234.50" for the text fields. Tolerates the API sending
  /// a string: a bare `as num` cast would throw and break the whole form.
  static String _fmt(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    return n == null ? '' : n.toStringAsFixed(2);
  }

  Future<void> _loadMe() async {
    try {
      final resp = await http.get(
        u('/me'),
        headers: await authHeaders(json: false),
      );
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _isAdmin = me['is_admin'] == true);
    } catch (_) {}
  }

  Future<void> _loadProjects() async {
    try {
      final resp =
          await http.get(u('/projects'), headers: await authHeaders(json: false));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final list = List<Map<String, dynamic>>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
        setState(() {
          _projects = list;
          // Default to the base project (1) only when creating
          if (!isEditing && list.any((p) => p['id'] == 1)) _projectId = 1;
          // Guard against an obra that no longer exists
          if (_projectId != null && !list.any((p) => p['id'] == _projectId)) {
            _projectId = null;
          }
          _loadingProjects = false;
        });
      } else {
        setState(() => _loadingProjects = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await fetchWorkerRoles();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        final current = normalizeRole(_role.text);
        if (current.isEmpty) {
          // Create mode, or a worker saved before phase 11.
          _role.text = kUnassignedRole;
        } else if (!_roles.contains(current)) {
          // DropdownButton throws if its value is not among its items, so a
          // stored role the endpoint does not know about has to be injected
          // rather than left to blow up the form.
          _roles = [..._roles, current]..sort();
          _role.text = current;
        } else {
          _role.text = current;
        }
        _loadingRoles = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  /// Free-text entry for a role that does not exist yet.
  ///
  /// GET /worker-roles is SELECT DISTINCT, so a new role only exists
  /// server-side once a worker carrying it has been saved. Until then it is
  /// added to the local list optimistically so the dropdown can show it.
  Future<void> _addRole() async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('NUEVO PUESTO'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'PUESTO',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('AGREGAR'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (typed == null) return;

    // Normalize BEFORE comparing, so 'oficial ' selects the existing OFICIAL
    // instead of creating a near-duplicate.
    final role = normalizeRole(typed);
    if (role.isEmpty || !mounted) return;
    setState(() {
      if (!_roles.contains(role)) _roles = [..._roles, role]..sort();
      _role.text = role;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name, _role, _nss, _curp, _phone, _address, _blood,
      _ecName, _ecPhone, _rfc, _cardNumber, _clabe, _sdi,
      _extraHour, _compensation, _compensation2, _loan, _infonavit, _fonacot
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

  double? _money(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', ''));

  bool get _hasPayroll => [
    _sdi, _extraHour, _compensation, _compensation2, _loan, _infonavit, _fonacot
  ].any((c) => c.text.trim().isNotEmpty);

  bool get _hasDetails => [
    _nss, _curp, _phone, _address, _blood, _ecName, _ecPhone,
    _rfc, _cardNumber, _clabe
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
                  setState(() {
                    _photo = null;
                    if (_existingPhoto != null) {
                      _existingPhoto = null;
                      _photoCleared = true;
                    }
                  });
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
      setState(() {
        _photo = File(picked.path);
        _photoCleared = false;
      });
    }
  }

  Future<String?> _uploadPhoto(File file) async {
    final req = http.MultipartRequest(
        'POST', u('/upload-photo/'));
    req.headers.addAll(await authHeaders(json: false));
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
    if (name.isEmpty) {
      _showError('El nombre es obligatorio');
      return;
    }

    final card = _cardNumber.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clabe = _clabe.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (card.isNotEmpty && card.length != 16) {
      _showError('La tarjeta debe tener 16 dígitos');
      return;
    }
    if (clabe.isNotEmpty && clabe.length != 18) {
      _showError('La CLABE debe tener 18 dígitos');
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
      } else if (_photoCleared) {
        photoFilename = ''; // '' clears it server-side
      }

      final basicBody = jsonEncode({
        'name': name,
        'project_id': _projectId,
        // Belt and braces: the dropdown and _addRole both normalize already,
        // but this is the last point before the value reaches the DB and
        // becomes a new SELECT DISTINCT bucket forever.
        'role': normalizeRole(_role.text),
        'photo_url': photoFilename,
      });

      final headers = await authHeaders();
      final resp = isEditing
          ? await http.put(u('/workers/$_workerId'),
          headers: headers, body: basicBody)
          : await http.post(u('/workers'),
          headers: headers, body: basicBody);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() => _saving = false);
        _showError('Error al guardar (HTTP ${resp.statusCode})');
        return;
      }

      final id = isEditing ? _workerId : jsonDecode(resp.body)['id'];

      // Personal info
      if (id != null && (_hasDetails || isEditing)) {
        final dr = await http.put(
          u('/workers/$id/details'),
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
        if (dr.statusCode != 200) {
          setState(() => _saving = false);
          _showError('Se guardaron los datos básicos, pero la ficha no');
          return;
        }
      }

      // Nómina (salary) — admins only
      if (id != null && _isAdmin && (_hasPayroll || isEditing)) {
        final pr = await http.put(
          u('/workers/$id/payroll'),
          headers: await authHeaders(),
          body: jsonEncode({
            'sdi': _money(_sdi),
            'extra_hour_cost': _money(_extraHour),
            'compensation': _money(_compensation),
            'compensation_2': _money(_compensation2),
            'personal_loan': _money(_loan),
            'infonavit': _money(_infonavit),
            'fonacot': _money(_fonacot),
          }),
        );
        if (mounted && pr.statusCode != 200) {
          setState(() => _saving = false);
          _showError('Se guardaron los datos, pero la nómina no');
          return;
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Error: $e');
    }
  }

  // ---------- UI helpers ----------
  Widget _field(TextEditingController c, String label,
      {TextInputType? kb, bool caps = false, bool money = false, int? maxLen}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        keyboardType: kb,
        textCapitalization:
        caps ? TextCapitalization.characters : TextCapitalization.none,
        maxLength: maxLen,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 14),
          prefixText: money ? '\$ ' : null,
          counterText: '',
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'EDITAR TRABAJADOR' : 'NUEVO TRABAJADOR'),
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
                    // Rendering only. The upload itself stays in
                    // _uploadPhoto on the save path, untouched.
                    WorkerAvatar(
                      file: _photo,
                      photoUrl: _existingPhoto,
                      diameter: 112,
                      placeholderColor: Colors.white24,
                      iconColor: Colors.white70,
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
                (_photo == null && _existingPhoto == null)
                    ? 'AGREGAR FOTO'
                    : 'CAMBIAR FOTO',
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
            WorkerSectionCard(title: 'DATOS GENERALES', children: [
              _field(_name, 'NOMBRE COMPLETO *', caps: true),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _loadingRoles
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'PUESTO',
                                labelStyle: TextStyle(fontSize: 14),
                                isDense: true,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _roles.contains(_role.text)
                                      ? _role.text
                                      : null,
                                  isExpanded: true,
                                  hint: const Text(kUnassignedRole),
                                  items: _roles
                                      .map((r) => DropdownMenuItem<String>(
                                            value: r,
                                            child: Text(
                                              r,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setState(
                                      () => _role.text = v ?? kUnassignedRole),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'AGREGAR PUESTO',
                            icon: const Icon(Icons.add_circle_outline,
                                color: Color(0xFF1C1CF0)),
                            onPressed: _saving ? null : _addRole,
                          ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _loadingProjects
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                )
                    : InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'OBRA ASIGNADA',
                    labelStyle: TextStyle(fontSize: 14),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _projectId,
                      isExpanded: true,
                      hint: const Text('SELECCIONA UNA OBRA'),
                      items: _projects
                          .map(
                            (p) => DropdownMenuItem<int?>(
                              value: p['id'],
                              child: Text(
                                (p['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _projectId = v),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // ---------- Personal info ----------
            WorkerSectionCard(title: 'INFORMACIÓN PERSONAL (OPCIONAL)', children: [
              _field(_nss, 'NSS', kb: TextInputType.number),
              _field(_curp, 'CURP', caps: true),
              _field(_phone, 'TELÉFONO', kb: TextInputType.phone),
              _field(_address, 'DIRECCIÓN'),
              _field(_blood, 'TIPO DE SANGRE (EJ. O+)', caps: true),
            ]),
            const SizedBox(height: 12),

            // ---------- Emergency ----------
            WorkerSectionCard(title: 'CONTACTO DE EMERGENCIA (OPCIONAL)', children: [
              _field(_ecName, 'NOMBRE', caps: true),
              _field(_ecPhone, 'TELÉFONO', kb: TextInputType.phone),
            ]),
            const SizedBox(height: 12),

            // ---------- Fiscal & bank (all users) ----------
            WorkerSectionCard(title: 'DATOS FISCALES Y BANCO (OPCIONAL)', children: [
              _field(_rfc, 'RFC', caps: true, maxLen: 13),
              _field(_cardNumber, 'NÚMERO DE TARJETA',
                  kb: TextInputType.number, maxLen: 16),
              _field(_clabe, 'CLABE', kb: TextInputType.number, maxLen: 18),
            ]),
            const SizedBox(height: 12),

            // ---------- Nómina / salary (admins only) ----------
            if (_isAdmin)
              WorkerSectionCard(title: 'NÓMINA', children: [
                _field(_sdi, 'SDI',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_extraHour, 'COSTO HORA EXTRA',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_compensation, 'COMPENSACIÓN',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_compensation2, 'COMPENSACIÓN 2',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_loan, 'PRÉSTAMO PERSONAL',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_infonavit, 'PRÉSTAMO INFONAVIT',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
                _field(_fonacot, 'PRÉSTAMO FONACOT',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    money: true),
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
                    : Icon(isEditing ? Icons.save : Icons.person_add),
                label: Text(
                  _saving
                      ? 'GUARDANDO...'
                      : (isEditing ? 'GUARDAR CAMBIOS' : 'AGREGAR TRABAJADOR'),
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