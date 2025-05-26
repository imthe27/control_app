import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final List<Map<String, dynamic>> workers = [
    {
      'name': 'LUIS PÉREZ',
      'project': 'Asignado a: Fundación Sur',
      'image': const AssetImage('assets/Face.jpeg'),
      'role': 'Electricista',
    },
    {
      'name': 'JOSÉ MARTÍNEZ',
      'project': 'Asignado a: Edificio Central',
      'image': const AssetImage('assets/Face1.jpeg'),
      'role': 'Albañil',
    },
  ];

  final List<String> _roles = ['Electricista', 'Albañil', 'Plomero', 'Herrero', 'Carpintero'];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  File? _pickedImage;
  String _selectedRole = 'Electricista';

  String searchQuery = '';
  String roleFilter = 'Todos';

  void _addWorker() {
    final name = _nameController.text.trim();
    final project = _projectController.text.trim();
    if (name.isNotEmpty && project.isNotEmpty) {
      setState(() {
        workers.add({
          'name': name,
          'project': project,
          'image': _pickedImage,
          'role': _selectedRole,
        });
      });
      _clearInputs();
      Navigator.pop(context);
    }
  }

  void _clearInputs() {
    _nameController.clear();
    _projectController.clear();
    _pickedImage = null;
    _selectedRole = _roles.first;
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pickedImage = File(picked.path);
      });
    }
  }

  void _showAddDialog({int? editIndex}) {
    if (editIndex != null) {
      final existing = workers[editIndex];
      _nameController.text = existing['name'];
      _projectController.text = existing['project'];
      _pickedImage = existing['image'] is File ? existing['image'] : null;
      _selectedRole = existing['role'];
    } else {
      _clearInputs();
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(editIndex != null ? 'Editar trabajador' : 'Nuevo trabajador'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: _pickedImage != null ? FileImage(_pickedImage!) : null,
                  child: _pickedImage == null ? const Icon(Icons.person) : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: _projectController,
                decoration: const InputDecoration(labelText: 'Proyecto asignado'),
              ),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: _roles.map((role) {
                  return DropdownMenuItem(value: role, child: Text(role));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRole = val);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (editIndex != null) {
                setState(() {
                  workers[editIndex] = {
                    'name': _nameController.text,
                    'project': _projectController.text,
                    'image': _pickedImage,
                    'role': _selectedRole,
                  };
                });
                Navigator.pop(context);
              } else {
                _addWorker();
              }
            },
            child: Text(editIndex != null ? 'Guardar' : 'Agregar'),
          ),
        ],
      ),
    );
  }

  void _removeWorker(int index) {
    setState(() {
      workers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredWorkers = workers.where((w) {
      final matchesName = w['name'].toString().toUpperCase().contains(searchQuery.toUpperCase());
      final matchesRole = roleFilter == 'Todos' || w['role'] == roleFilter;
      return matchesName && matchesRole;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Personal')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => searchQuery = val),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: roleFilter,
                  onChanged: (val) => setState(() => roleFilter = val!),
                  items: ['Todos', ..._roles].map((role) {
                    return DropdownMenuItem(value: role, child: Text(role));
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredWorkers.length,
              itemBuilder: (context, index) {
                final worker = filteredWorkers[index];
                return Dismissible(
                  key: Key(worker['name'] + index.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  secondaryBackground: Container(
                    color: Colors.blue,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.edit, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    final actualIndex = workers.indexOf(worker);
                    if (direction == DismissDirection.endToStart) {
                      _showAddDialog(editIndex: actualIndex);
                    } else {
                      _removeWorker(actualIndex);
                    }
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: worker['image'] != null
                          ? (worker['image'] is File
                          ? FileImage(worker['image'])
                          : worker['image'] as ImageProvider)
                          : null,
                      child: worker['image'] == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(worker['name']),
                    subtitle: Text('${worker['project']}\n${worker['role']}'),
                    isThreeLine: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundImage: worker['image'] != null
                                      ? (worker['image'] is File
                                      ? FileImage(worker['image'])
                                      : worker['image'] as ImageProvider)
                                      : null,
                                  child: worker['image'] == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(worker['name']),
                              Text(worker['project']),
                              Text('Rol: ${worker['role']}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}