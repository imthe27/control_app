import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'screen_obra.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final List<Map<String, dynamic>> projects = [
    {
      'name': 'Parque La Cañada',
      'status': 'In Progress',
      'progress': 0.65,
      'address': 'Av. Hidalgo 123',
      'image': const AssetImage('assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg'),
      'isPinned': false,
    },
    {
      'name': 'Parque Los Nogales',
      'status': 'Finished',
      'progress': 1.0,
      'address': 'Calle Robles 45',
      'image': const AssetImage('assets/42f8f0125ac4eeea8301cba1d8dc88eb_fit.jpg'),
      'isPinned': false,
    },
    {
      'name': 'Escuela Secundaria Técnica 101',
      'status': 'Finished',
      'progress': 1.0,
      'address': 'Calle Río Nazas 45',
      'image': const AssetImage('assets/a3ca9011f7c72ccd2395d0fcac08ed26_fit.jpg'),
      'isPinned': false,
    },
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _pickedImage;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pickedImage = File(picked.path);
      });
    }
  }

  void _showAddProjectDialog({Map<String, dynamic>? projectToEdit}) {
    _nameController.text = projectToEdit?['name'] ?? '';
    _addressController.text = projectToEdit?['address'] ?? '';
    _pickedImage = projectToEdit?['image'];

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
                        backgroundImage:
                        _pickedImage != null ? FileImage(_pickedImage!) : null,
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
                  onPressed: () {
                    final name = _nameController.text.trim();
                    final address = _addressController.text.trim();
                    if (name.isNotEmpty && address.isNotEmpty) {
                      setState(() {
                        if (projectToEdit != null) {
                          projectToEdit['name'] = name;
                          projectToEdit['address'] = address;
                          projectToEdit['image'] = _pickedImage;
                        } else {
                          projects.add({
                            'name': name,
                            'status': 'In Progress',
                            'progress': 0.0,
                            'address': address,
                            'image': _pickedImage,
                            'isPinned': false,
                          });
                        }
                      });
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
      appBar: AppBar(title: const Text('Obras')),
      body: ListView.builder(
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          projects.sort((a, b) => (b['isPinned'] ? 1 : 0) - (a['isPinned'] ? 1 : 0));
          return Dismissible(
            key: Key(project['name']),
            background: Container(
              color: Colors.blue,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(Icons.edit, color: Colors.white),
            ),
            secondaryBackground: Container(
              color: Colors.purple,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: Icon(
                project['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                _showAddProjectDialog(projectToEdit: project);
              } else if (direction == DismissDirection.endToStart) {
                setState(() {
                  project['isPinned'] = !(project['isPinned'] ?? false);
                });
              }
              return false;
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectTasksScreen(
                        projectName: project['name'] as String,
                      ),
                    ),
                  );
                },
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
                              image: project['image'] is File
                                  ? FileImage(project['image']) as ImageProvider
                                  : project['image'] ?? const AssetImage('assets/demo1.jpg'),
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
                              color: Colors.black.withValues(alpha: 0.3),
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
                            value: project['progress'] as double,
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
