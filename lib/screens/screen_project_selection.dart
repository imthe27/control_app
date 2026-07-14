import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_record_attendance.dart';
import 'package:control_app/main.dart' show baseUrl;

Uri u(String path) => Uri.parse('$baseUrl$path');

/// Builds a loadable image URL from whatever the API returns.
/// Handles: null, bare filenames, relative "/media/..." paths, and
/// absolute URLs. Relative paths are resolved against the app's own
/// baseUrl, so images work in BOTH debug (LAN IP) and release (ngrok)
/// without depending on any server-side env variable.
String? resolvePhotoUrl(String? stored) {
  if (stored == null || stored.isEmpty) return null;
  if (stored.startsWith('http://') || stored.startsWith('https://')) {
    return stored;
  }
  final path = stored.startsWith('/') ? stored : '/media/$stored';
  return '$baseUrl$path';
}

class ProjectSelectionScreen extends StatefulWidget {
  const ProjectSelectionScreen({super.key});

  @override
  State<ProjectSelectionScreen> createState() => _ProjectSelectionScreenState();
}

class _ProjectSelectionScreenState extends State<ProjectSelectionScreen> {
  List<Map<String, dynamic>> projects = [];
  Set<String> pinnedProjectNames = {};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _pickedImage;
  bool _isSaving = false;
  bool isLoading = true;
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    fetchProjects();
  }

  Future<void> fetchProjects() async {
    try {
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
          projects.sort((a, b) =>
          (b['isPinned'] ? 1 : 0) - (a['isPinned'] ? 1 : 0));
          isLoading = false;
        });
      } else {
        throw Exception('Error al cargar las obras');
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al cargar las obras'),
          backgroundColor: Colors.red));
    }
  }

  Future<String?> uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      u('/upload-photo/'),
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
    if (photoUrl == null || photoUrl.isEmpty) return;

    try {
      // Extract filename from URL (handles both /media/filename and full URLs)
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;
      final filename = pathSegments.isNotEmpty ? pathSegments.last : null;

      if (filename == null || filename.isEmpty) {
        print("Could not extract filename from: $photoUrl");
        return;
      }

      // NOTE: trailing slash matters! The API route is "/delete-photo/".
      // Without it, FastAPI answers with a 307 redirect that Dart's http
      // client does NOT follow for DELETE — so the file was never deleted.
      final deleteUrl =
      u('/delete-photo/?filename=${Uri.encodeQueryComponent(filename)}');
      final response = await http.delete(deleteUrl);

      if (response.statusCode == 200) {
        print("Old image deleted: $filename");
      } else {
        print("Failed to delete old image: ${response.body}");
      }
    } catch (e) {
      print("Error deleting old image: $e");
    }
  }

  Future<bool> _updateProject(int projectId, Map<String, dynamic> updates) async {
    final response = await http.put(
      u('/projects/$projectId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updates),
    );

    if (!mounted) return response.statusCode == 200;
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyecto actualizado')),
      );
      await fetchProjects();
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar: ${response.body}')),
      );
      return false;
    }
  }

  void _showAddProjectDialog({Map<String, dynamic>? projectToEdit}) {
    _nameController.text = projectToEdit?['name'] ?? '';
    _addressController.text = projectToEdit?['address'] ?? '';
    _pickedImage = null;
    _isSaving = false;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(projectToEdit == null ? 'NUEVA OBRA' : 'EDITAR OBRA'),
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
                      decoration: const InputDecoration(labelText: 'NOMBRE DE LA OBRA'),
                    ),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'DIRECCIÓN'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                    final name = _nameController.text.trim();
                    final address = _addressController.text.trim();

                    if (name.isEmpty || address.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Por favor completa todos los campos')),
                      );
                      return;
                    }

                    setModalState(() => _isSaving = true);

                    try {
                      String? photoUrl;

                      // 1. Upload the new image FIRST (if one was picked).
                      //    We don't touch the old image yet — if this
                      //    upload fails, the project keeps its old photo.
                      if (_pickedImage != null) {
                        photoUrl = await uploadImage(_pickedImage!);
                        if (photoUrl == null) {
                          if (!mounted) return;
                          setModalState(() => _isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Error al subir la imagen')),
                          );
                          return;
                        }
                      }

                      if (projectToEdit != null) {
                        // 2. EDIT: always send photo_url. If no new image
                        //    was picked, resend the existing one so the
                        //    backend never receives null (which used to
                        //    wipe the photo). The backend normalizes any
                        //    URL form down to the bare filename.
                        final ok = await _updateProject(projectToEdit['id'], {
                          'name': name,
                          'address': address,
                          'status': projectToEdit['status'] ?? 'EN PROCESO',
                          'progress': projectToEdit['progress'] ?? 0.6,
                          'photo_url': photoUrl ?? projectToEdit['photo_url'],
                        });

                        // 3. Only delete the old image AFTER the update
                        //    succeeded, and only if it was replaced.
                        if (ok && photoUrl != null) {
                          await deleteOldImage(projectToEdit['photo_url']);
                        }

                        if (!ok) {
                          if (!mounted) return;
                          setModalState(() => _isSaving = false);
                          return;
                        }
                      } else {
                        // CREATE
                        final response = await http.post(
                          u('/projects'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'name': name,
                            'status': 'EN PROCESO',
                            'progress': 0.6,
                            'address': address,
                            if (photoUrl != null) 'photo_url': photoUrl,
                          }),
                        );

                        if (response.statusCode != 200 && response.statusCode != 201) {
                          if (!mounted) return;
                          setModalState(() => _isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al crear: ${response.body}')),
                          );
                          return;
                        }

                        await fetchProjects();
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                    } catch (e) {
                      if (!mounted) return;
                      setModalState(() => _isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: _isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.yellow),
                  )
                      : Text(projectToEdit == null ? 'AGREGAR' : 'GUARDAR'),
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
    if (isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow),
                ),
                SizedBox(height: 16),
                Text(
                  'CARGANDO OBRAS . . .',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('OBRAS'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue, Color(0xFF1C1CF0)],
            ),
          ),
        ),
        titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold
        ),
        elevation: 0,
        actions: [
          if (selectedIndexes.isNotEmpty) ...[
            if (selectedIndexes.length == 1)
              IconButton(
                icon: const Icon(Icons.edit),
                color: Colors.white,
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
                  color: Colors.white,
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
          ),
        ),
        child: ListView.builder(
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
                      builder: (_) => RecordAttendanceScreen(
                        projectId: project['id'],
                        //projectName: project['name'], to use when the project screen works
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
                              color: Colors.black,
                            ),
                            child: resolvePhotoUrl(project['photo_url']) != null
                                ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: CachedNetworkImage(
                                imageUrl: resolvePhotoUrl(project['photo_url'])!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(color: Colors.yellow),
                                ),
                                errorWidget: (context, url, error) => Image.asset(
                                  'assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                                : ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: Image.asset(
                                'assets/2df5b81c8b584348e7c4bb1f07ad6e87_fit.jpg',
                                fit: BoxFit.cover,
                              ),
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProjectDialog,
        tooltip: 'AGREGAR OBRA',
        child: const Icon(Icons.add),
      ),
    );
  }
}