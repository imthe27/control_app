import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_project.dart';
import 'screen_project_form.dart';
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

  /// Opens the full-screen create/edit form. Refreshes the list when
  /// the form pops with a successful save.
  Future<void> _openProjectForm({Map<String, dynamic>? projectToEdit}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectFormScreen(projectToEdit: projectToEdit),
      ),
    );
    if (saved == true) {
      setState(() => selectedIndexes.clear());
      await fetchProjects();
    }
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
                onPressed: () => _openProjectForm(
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
                      builder: (_) => ProjectDetailScreen(project: project),
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
                          // Quick action: jump straight to attendance
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              elevation: 3,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecordAttendanceScreen(
                                        projectId: project['id'],
                                      ),
                                    ),
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.checklist,
                                    color: Color(0xFF1C1CF0),
                                    size: 24,
                                  ),
                                ),
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
        onPressed: _openProjectForm,
        tooltip: 'AGREGAR OBRA',
        child: const Icon(Icons.add),
      ),
    );
  }
}