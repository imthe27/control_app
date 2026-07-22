import 'dart:convert';
import 'screen_worker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'models/worker.dart';
import 'package:control_app/main.dart' show baseUrl;
import 'screen_worker_form.dart';

Uri u(String path) => Uri.parse('$baseUrl$path');

class PersonnelScreen extends StatefulWidget {
  const PersonnelScreen({super.key});

  @override
  State<PersonnelScreen> createState() => _PersonnelScreenState();
}

class _PersonnelScreenState extends State<PersonnelScreen> {
  List<Worker> workers = [];
  bool isLoading = true;
  bool _isAdmin = false;
  String searchQuery = '';
  Set<int> selectedIndexes = {};

  //final List<String> _roles = ['Electricista', 'Albañil', 'Plomero', 'Herrero'];
  //String roleFilter = 'TODOS';  to be defined roles
  //String _selectedRole = 'Electricista';

  @override
  void initState() {
    super.initState();
    loadWorkers();
    _loadMe();
  }

  Future<void> loadWorkers() async {
    try {
      final response = await http.get(u('/workers/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          workers = data.map((json) {
            json['project_id'] ??= 0;
            return Worker.fromJson(json);
          }).toList();
          isLoading = false;
        });
      } else {
        throw Exception('Error al cargar trabajadores');
      }
    } catch (e) {
      print('Error al cargar trabajadores: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al cargar trabajadores'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadMe() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      if (token == null || token == 'guest') return;
      final resp = await http.get(
        u('/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _isAdmin = me['is_admin'] == true);
    } catch (_) {
      // not admin / offline: FAB stays hidden
    }
  }

  Future<void> _openWorkerForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const WorkerFormScreen()),
    );
    if (saved == true) loadWorkers();
  }

  Future<void> deleteWorkersFromBackend(List<int> ids) async {
    final response = await http.post(
      u('/delete-workers/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    if (response.statusCode != 200) {
      print('Error al eliminar trabajadores: ${response.body}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al eliminar trabajadores')),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trabajadores eliminados')));
    }
  }

  void _confirmDeleteSelected() {
    String password = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CONFIRMAR ELIMINAR TRABAJADORES'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'INGRESA LA CONTRASEÑA PARA ELIMINAR LOS TRABAJADORES SELECCIONADOS:',
            ),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(labelText: 'CONTRASEÑA'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (password == 'Mony1705') {
                final idsToDelete = selectedIndexes
                    .map((i) => workers[i].id)
                    .toList();
                await deleteWorkersFromBackend(idsToDelete);
                await loadWorkers();
                setState(() => selectedIndexes.clear());
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('CONTRASEÑA INCORRECTA')),
                );
              }
            },
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await loadWorkers();
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    return parts.map((p) => p[0]).take(2).join('').toUpperCase();
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
                  'CARGANDO PERSONAL . . .',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filteredWorkers = workers.where((w) {
      final matchesName = w.name.toUpperCase().contains(
        searchQuery.toUpperCase(),
      );
      //      final matchesRole = roleFilter == 'Todos' || w.role == roleFilter;
      return matchesName; // && matchesRole;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PERSONAL'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
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
          fontWeight: FontWeight.bold,
        ),
        elevation: 0,
        actions: [
          if (selectedIndexes.isNotEmpty) ...[
            if (selectedIndexes.length == 1)
            IconButton(
              icon: const Icon(Icons.delete),
              color: Colors.white,
              onPressed: _confirmDeleteSelected,
            ),
          ],
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
        child: RefreshIndicator(
          displacement: 60,
          edgeOffset: 72,
          onRefresh: _onRefresh,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'BUSCAR',
                        hintStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                      onChanged: (val) => setState(() => searchQuery = val),
                    ),
                    //const SizedBox(height: 12),
                    //SizedBox(
                    //  height: 40,
                    //  child: ListView(
                    //    scrollDirection: Axis.horizontal,
                    //    children: [
                    //      _filterChip('Todos', 'Todos'),
                    //      ..._roles.map((role) => _filterChip(role, role)),
                    //    ],
                    //  ),
                    //),
                  ],
                ),
              ),
              Expanded(
                child: filteredWorkers.isEmpty
                    ? Center(
                        child: Text(
                          'NO HAY TRABAJADORES',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: filteredWorkers.length,
                        itemBuilder: (context, index) {
                          final worker = filteredWorkers[index];
                          final isSelected = selectedIndexes.contains(index);
                          return _WorkerCard(
                            worker: worker,
                            isSelected: isSelected,
                            onTap: () {
                              if (selectedIndexes.isNotEmpty) {
                                setState(() {
                                  isSelected
                                      ? selectedIndexes.remove(index)
                                      : selectedIndexes.add(index);
                                });
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        WorkerDetailScreen(worker: worker),
                                  ),
                                );
                              }
                            },
                            onLongPress: () {
                              setState(() {
                                isSelected
                                    ? selectedIndexes.remove(index)
                                    : selectedIndexes.add(index);
                              });
                            },
                            initials: _getInitials(worker.name),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: _openWorkerForm,
              backgroundColor: const Color(0xFF1C1CF0),
              child: const Icon(Icons.person_add, color: Colors.white),
            )
          : null,
    );
  }

  //  Widget _filterChip(String label, String value) {
  //    final isSelected = roleFilter == value;
  //    return Padding(
  //      padding: const EdgeInsets.only(right: 8),
  //      child: FilterChip(
  //        label: Text(
  //          label,
  //          style: TextStyle(
  //            color: isSelected ? Colors.white : Colors.grey[700],
  //            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
  //          ),
  //        ),
  //        selected: isSelected,
  //        onSelected: (selected) {
  //          setState(() => roleFilter = selected ? value : 'Todos');
  //        },
  //        backgroundColor: Colors.white54,
  //        selectedColor: const Color(0xFF1C1CF0),
  //      ),
  //    );
  //  }

  //  void _showWorkerDetails(Worker worker) {
  //    showDialog(
  //      context: context,
  //      builder: (_) => AlertDialog(
  //        content: Column(
  //          mainAxisSize: MainAxisSize.min,
  //          crossAxisAlignment: CrossAxisAlignment.start,
  //          children: [
  //            Center(
  //              child: CircleAvatar(
  //                radius: 40,
  //                backgroundImage:
  //                worker.photoUrl != null ? CachedNetworkImageProvider(worker.photoUrl!) : null,
  //                child: worker.photoUrl == null
  //                    ? Text(
  //                  _getInitials(worker.name),
  //                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  //                )
  //                    : null,
  //              ),
  //            ),
  //            const SizedBox(height: 16),
  //            Text(worker.name, style: const TextStyle(fontWeight: FontWeight.bold)),
  //            Text(worker.project),
  //            Text('Rol: ${worker.role}'),
  //          ],
  //        ),
  //        actions: [
  //          TextButton(
  //            onPressed: () => Navigator.pop(context),
  //            child: const Text('CERRAR'),
  //          ),
  //        ],
  //      ),
  //    );
  //  }
}

class _WorkerCard extends StatelessWidget {
  final Worker worker;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String initials;

  const _WorkerCard({
    required this.worker,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.blue[300]! : Colors.white24,
                width: isSelected ? 2 : 0.5,
              ),
              color: isSelected
                  ? Colors.blue[100]
                  : Colors.white.withValues(alpha: 0.95),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? Colors.blue.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      image: worker.photoUrl != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(
                                worker.photoUrl!,
                              ),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: const Color(0xFF1C1CF0),
                    ),
                    child: worker.photoUrl == null
                        ? Center(
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue[400],
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            //Text(
                            //  worker.role.toUpperCase(),
                            //  maxLines: 1,
                            //  overflow: TextOverflow.ellipsis,
                            //  style: TextStyle(
                            //    fontSize: 11,
                            //    fontWeight: FontWeight.w500,
                            //    color: Colors.grey[600],
                            //    letterSpacing: 0.5,
                            //  ),
                            //),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.blue[200]!,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            worker.project.length > 15
                                ? '${worker.project.substring(0, 12)}...'
                                : worker.project,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
