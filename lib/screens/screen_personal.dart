import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'models/worker.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Worker> workers = [];
  bool isLoading = true;
  final List<String> _roles = ['Electricista', 'Albañil', 'Plomero', 'Herrero'];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  String _selectedRole = 'Electricista';
  String searchQuery = '';
  String roleFilter = 'Todos';
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    loadWorkers();
  }

  Future<void> loadWorkers() async {
    try {
      final response = await http.get(Uri.parse('https://fdb0c23faf9e.ngrok-free.app/workers'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          workers = data.map((json) {
            json['project_id'] ??= 0;
            return Worker.fromJson(json);
          }).toList();
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos actualizados')));
      } else {
        throw Exception('Error al cargar trabajadores');
      }
    } catch (e) {
      print('Error al cargar trabajadores: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al cargar trabajadores')));
    }
  }

  Future<void> addWorkerToBackend(String name, String project, String role, String? photoUrl) async {
    final url = Uri.parse('https://fdb0c23faf9e.ngrok-free.app/workers');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'project': project,
        'role': role,
        'photo_url': photoUrl,
      }),
    );
    if (response.statusCode != 200) {
      print('Error al agregar trabajador: ${response.body}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al agregar trabajador')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trabajador agregado')));
    }
  }

  Future<void> updateWorkerInBackend(int id, String name, String project, String role) async {
    final url = Uri.parse('https://fdb0c23faf9e.ngrok-free.app/workers/$id');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'project': project,
        'role': role,
      }),
    );
    if (response.statusCode != 200) {
      print('Error al actualizar trabajador: ${response.body}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al actualizar trabajador')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trabajador actualizado')));
    }
  }

  Future<void> deleteWorkersFromBackend(List<int> ids) async {
    final url = Uri.parse('https://fdb0c23faf9e.ngrok-free.app/delete-workers');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    if (response.statusCode != 200) {
      print('Error al eliminar trabajadores: ${response.body}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar trabajadores')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trabajadores eliminados')));
    }
  }

  void _clearInputs() {
    _nameController.clear();
    _projectController.clear();
    _selectedRole = _roles.first;
  }

  void _showAddDialog({Worker? worker, int? index}) {
    if (worker != null) {
      _nameController.text = worker.name;
      _projectController.text = worker.project;
      _selectedRole = _roles.contains(worker.role) ? worker.role : _roles.first;
    } else {
      _clearInputs();
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(worker != null ? 'Editar trabajador' : 'Nuevo trabajador'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                items: _roles.map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                onChanged: (val) => setState(() => _selectedRole = val!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              final project = _projectController.text.trim();
              if (name.isNotEmpty && project.isNotEmpty) {
                if (worker != null && index != null) {
                  await updateWorkerInBackend(worker.id!, name, project, _selectedRole);
                } else {
                  await addWorkerToBackend(name, project, _selectedRole, null);
                }
                await loadWorkers();
                Navigator.pop(context);
              }
            },
            child: Text(worker != null ? 'Guardar' : 'Agregar'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSelected() {
    String password = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa la contraseña para eliminar los trabajadores seleccionados:'),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (password == 'Mony1705') {
                final idsToDelete = selectedIndexes.map((i) => workers[i].id!).toList();
                await deleteWorkersFromBackend(idsToDelete);
                await loadWorkers();
                setState(() => selectedIndexes.clear());
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña incorrecta')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await loadWorkers();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredWorkers = workers.where((w) {
      final matchesName = w.name.toUpperCase().contains(searchQuery.toUpperCase());
      final matchesRole = roleFilter == 'Todos' || w.role == roleFilter;
      return matchesName && matchesRole;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal'),
        actions: [
          if (selectedIndexes.isNotEmpty) ...[
            if (selectedIndexes.length == 1)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showAddDialog(
                  worker: workers[selectedIndexes.first],
                  index: selectedIndexes.first,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _confirmDeleteSelected,
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
    Navigator.pushNamed(context, '/download');
    },
    ),
    ],
    ),
    body: RefreshIndicator(
    displacement: 60,
    edgeOffset: 120,
    onRefresh: _onRefresh,
    child: Column(
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
    onChanged: (val) => setState(() =>
     searchQuery = val),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: roleFilter,
                    onChanged: (val) => setState(() => roleFilter = val!),
                    items: ['Todos', ..._roles].map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredWorkers.length,
                itemBuilder: (context, index) {
                  final worker = filteredWorkers[index];
                  final selected = selectedIndexes.contains(index);
                  return ListTile(
                    tileColor: selected ? Colors.blue.shade100 : null,
                    onLongPress: () => setState(() {
                      selectedIndexes.contains(index)
                          ? selectedIndexes.remove(index)
                          : selectedIndexes.add(index);
                    }),
                    onTap: () {
                      if (selectedIndexes.isNotEmpty) {
                        setState(() {
                          selectedIndexes.contains(index)
                              ? selectedIndexes.remove(index)
                              : selectedIndexes.add(index);
                        });
                      } else {
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
                                    backgroundImage: worker.photoUrl != null ? NetworkImage(worker.photoUrl!) : null,
                                    child: worker.photoUrl == null ? const Icon(Icons.person) : null,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(worker.name),
                                Text(worker.project),
                                Text('Rol: ${worker.role}'),
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
                      }
                    },
                    leading: CircleAvatar(
                      backgroundImage: worker.photoUrl != null ? NetworkImage(worker.photoUrl!) : null,
                      child: worker.photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(worker.name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
