import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_project.dart';
import 'screen_project_form.dart';
import 'screen_record_attendance.dart';
import 'package:control_app/main.dart' show baseUrl;
import 'package:control_app/api.dart';

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
  bool _showActive = true;
  bool _showFinished = false;

  @override
  void initState() {
    super.initState();
    fetchProjects();
  }

  /// Pinned first (existing behavior), then newest first. On a serial PK the
  /// id is an exact proxy for insertion order — projects has no created_at,
  /// and backfilling one now was considered and rejected. The full comparator
  /// also makes the order deterministic; the old single-key pin sort left
  /// unpinned items at the mercy of List.sort being unstable.
  int _compareProjects(Map<String, dynamic> a, Map<String, dynamic> b) {
    final pin =
        (b['isPinned'] == true ? 1 : 0) - (a['isPinned'] == true ? 1 : 0);
    if (pin != 0) return pin;
    return (b['id'] as int).compareTo(a['id'] as int);
  }

  Future<void> fetchProjects() async {
    try {
      final response = await http.get(u('/projects'),
          headers: await authHeaders(json: false));
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
          projects.sort(_compareProjects);
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

  Widget _buildProjectCard(int index) {
    final project = projects[index];
    final isSelected = selectedIndexes.contains(index);

    return GestureDetector(
      onTap: () {
        if (selectedIndexes.isNotEmpty) {
          HapticFeedback.selectionClick();
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
        HapticFeedback.mediumImpact();
        setState(() {
          isSelected
              ? selectedIndexes.remove(index)
              : selectedIndexes.add(index);
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
                        httpHeaders: authHeadersSync(),
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
                    right: 12,
                    child: Align(
                      alignment: Alignment.centerLeft,
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
                            Expanded(
                              child: Text(
                                project['name'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                    project['progress'] == null
                        ? Text('AVANCE: N/A — SIN CATÁLOGO',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[500]))
                        : LinearProgressIndicator(
                      value: (project['progress'] as num)
                          .toDouble()
                          .clamp(0.0, 1.0),
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
                      projects.sort(_compareProjects);
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
        child: Builder(builder: (context) {
          bool isFinished(Map<String, dynamic> p) {
            final s = (p['status'] ?? '').toString().toLowerCase();
            return s.contains('termin') || s.contains('finish') || s.contains('final');
          }

          final activos = <int>[];
          final finalizados = <int>[];
          for (var i = 0; i < projects.length; i++) {
            (isFinished(projects[i]) ? finalizados : activos).add(i);
          }

          Widget sectionHeader(String title, int count, bool expanded, VoidCallback onTap) {
            return InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            children: [
              sectionHeader('ACTIVOS', activos.length, _showActive,
                      () => setState(() => _showActive = !_showActive)),
              if (_showActive) ...activos.map((i) => _buildProjectCard(i)),
              sectionHeader('FINALIZADOS', finalizados.length, _showFinished,
                      () => setState(() => _showFinished = !_showFinished)),
              if (_showFinished) ...finalizados.map((i) => _buildProjectCard(i)),
              const SizedBox(height: 80),
            ],
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openProjectForm,
        tooltip: 'AGREGAR OBRA',
        icon: const Icon(Icons.add, color: Color(0xFF1C1CF0)),
        label: const Text('AGREGAR OBRA', style: TextStyle(color: Color(0xFF1C1CF0))),
      ),
    );
  }
}