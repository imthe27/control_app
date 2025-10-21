import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_obra.dart';
import 'package:control_app/main.dart' show baseUrl;

Uri u(String path) => Uri.parse('$baseUrl$path');

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>> projects = [];
  Set<String> pinnedProjectNames = {};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _pickedImage;
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    fetchProjects();
  }

  Future<void> fetchProjects() async {
    final response = await http.get(u('/projects'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      final pinned = prefs.getStringList('pinned_projects') ?? [];
      setState(() {
        pinnedProjectNames = pinned.toSet();
        projects = List<Map<String, dynamic>>.from(data).map((proj) {
          proj['isPinned'] = pinnedProjectNames.contains(proj['name']);
          return proj;
        }).toList();
        projects.sort((a, b) => (b['isPinned'] ? 1 : 0) - (a['isPinned'] ? 1 : 0));
      });
    }
  }

  Future<String?> uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://fdb0c23faf9e.ngrok-free.app/upload-photo/'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      final data = jsonDecode(responseData);
      return data['url'];
    }
    return null;
  }

  Future<void> togglePin(String projectName, bool isPinned) async {
    final prefs = await SharedPreferences.getInstance();
    if (isPinned) {
      pinnedProjectNames.add(projectName);
    } else {
      pinnedProjectNames.remove(projectName);
    }
    await prefs.setStringList('pinned_projects', pinnedProjectNames.toList());
  }

  Future<void> deleteOldImage(String? photoUrl) async {
    if (photoUrl == null) return;

    final filename = Uri.parse(photoUrl).pathSegments.last;
    final url = Uri.parse('https://fdb0c23faf9e.ngrok-free.app/delete-photo?filename=$filename');

    try {
      final response = await http.delete(url);
      if (response.statusCode != 200) {
        print("Failed to delete old image: ${response.body}");
      }
    } catch (e) {
      print("Error deleting old image: $e");
    }
  }

  Future<void> _updateProject(int projectId, Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('https://fdb0c23faf9e.ngrok-free.app/projects/$projectId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updates),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyecto actualizado')),
      );
      fetchProjects();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al actualizar el proyecto')),
      );
    }
  }

  void _showAddProjectDialog({Map<String, dynamic>? projectToEdit}) {
    _nameController.text = projectToEdit?['name'] ?? '';
    _addressController.text = projectToEdit?['address'] ?? '';
    _pickedImage = null;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(projectToEdit == null ? 'Nuevo proyecto' : 'Editar proyecto'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                        if (picked != null) {
                          setModalState(() {
                            _pickedImage = File(picked.path);
                          });
                        }
                      },
                      child: CircleAvatar(
                        radius: 40,
                        backgroundImage: _pickedImage != null ? FileImage(_pickedImage!) : null,
                        child: _pickedImage == null ? const Icon(Icons.camera_alt) : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nombre del proyecto'),
                    ),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Dirección'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    final name = _nameController.text.trim();
                    final address = _addressController.text.trim();

                    if (name.isNotEmpty && address.isNotEmpty) {
                      String? photoUrl;

                      if (_pickedImage != null) {
                        await deleteOldImage(projectToEdit!['photo_url']);

                        final request = http.MultipartRequest(
                          'POST',
                          Uri.parse('https://fdb0c23faf9e.ngrok-free.app/upload-photo/'),
                        );
                        request.files.add(await http.MultipartFile.fromPath('file', _pickedImage!.path));
                        final res = await request.send();

                        if (res.statusCode == 200) {
                          final body = await res.stream.bytesToString();
                          photoUrl = jsonDecode(body)['url'];
                        }
                      }

                      if (projectToEdit != null) {
                        await _updateProject(projectToEdit['id'], {
                          'name': name,
                          'address': address,
                          'status': 'En Proceso',
                          'progress': 0.6,
                          if (photoUrl != null) 'photo_url': photoUrl,
                        });
                      } else {
                        await http.post(
                          Uri.parse('https://fdb0c23faf9e.ngrok-free.app/projects'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'name': name,
                            'status': 'In Progress',
                            'progress': 0.0,
                            'address': address,
                            'photo_url': photoUrl,
                          }),
                        );
                        await fetchProjects();
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                    }
                  },
                  child: Text(projectToEdit == null ? 'Agregar' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Obras'),
        actions: [
          if (selectedIndexes.isNotEmpty) ...[
            if (selectedIndexes.length == 1)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showAddProjectDialog(
                  projectToEdit: projects[selectedIndexes.first],
                ),
              ),
            Builder(
              builder: (context) {
                final project = projects[selectedIndexes.first];
                final isPinned = project['isPinned'] == true;
                return IconButton(
                  icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                  onPressed: () async {
                    final newStatus = !isPinned;
                    await togglePin(project['name'], newStatus);
                    setState(() {
                      project['isPinned'] = newStatus;
                      projects.sort((a, b) => (b['isPinned'] ? 1 : 0) - (a['isPinned'] ? 1 : 0));
                    });
                  },
                );
              },
            ),
          ]
        ],
      ),
      body: ListView.builder(
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          final isSelected = selectedIndexes.contains(index);

          return GestureDetector(
            onTap: () {
              if (selectedIndexes.isNotEmpty) {
                setState(() {
                  isSelected ? selectedIndexes.remove(index) : selectedIndexes.add(index);
                });
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectTasksScreen(
                      projectId: project['id'],
                      projectName: project['name'],
                    ),
                  ),
                );
              }
            },
            onLongPress: () {
              setState(() {
                selectedIndexes.add(index);
              });
            },
            child: Card(
              color: isSelected ? Colors.blue.shade100 : null,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            image: DecorationImage(
                              image: project['photo_url'] != null
                                  ? NetworkImage('${project['photo_url']}')
                                  : const AssetImage('assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg') as ImageProvider,
                              fit: BoxFit.cover,
                            ),
                            color: Colors.grey[300],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (project['isPinned'] == true)
                                  const Icon(Icons.push_pin, size: 14, color: Colors.yellow),
                                Text(
                                  project['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            project['address'] ?? '',
                            style: const TextStyle(fontSize: 18, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Estado: ${project['status']}',
                            style: TextStyle(
                              color: project['status'] == 'Finished' ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (project['progress'] ?? 0).toDouble(),
                            minHeight: 6,
                            backgroundColor: Colors.grey[300],
                            color: Colors.blueAccent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProjectDialog,
        tooltip: 'Agregar proyecto',
        child: const Icon(Icons.add),
      ),
    );
  }
}
