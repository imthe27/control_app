import 'dart:convert';
import 'screen_worker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'models/worker.dart';
import 'models/worker_roles.dart';
import 'package:control_app/api.dart';
import 'screen_absences.dart';
import 'screen_worker_form.dart';

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

  /// Needed so QUITAR FILTROS can clear the visible text, not just the state.
  final TextEditingController _searchController = TextEditingController();

  /// Selected worker IDs — not list indexes, which shift when the search
  /// filter is active and would target the wrong worker.
  ///
  /// Selection deliberately SURVIVES both filters: a worker can be selected
  /// and then filtered out of view. The delete confirmation lists every
  /// selected name for that reason, so nothing is ever deleted unseen.
  Set<int> selectedIds = {};

  /// Roles come from GET /worker-roles, not a hardcoded list. SIN ASIGNAR is
  /// a real stored role (17 of 37 workers), so it is an ordinary chip.
  static const String _allRoles = 'TODOS';
  List<String> _roles = [];
  String roleFilter = _allRoles;

  @override
  void initState() {
    super.initState();
    loadWorkers();
    _loadMe();
    _loadRoles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Sort key for Spanish names.
  ///
  /// Dart's String.compareTo is code-unit based, so 'Á' (U+00C1) sorts after
  /// 'Z' (U+005A) and ÁLVAREZ would land below ZAMORA. Accents are folded to
  /// the base letter, which is correct: in Spanish an accent never changes a
  /// word's alphabetical position.
  ///
  /// Ñ is NOT folded. The RAE treats it as its own letter between N and O.
  /// There is no code unit between 'N' and 'O', so it becomes 'N' plus a
  /// sentinel that outranks every letter: ÑANDU -> 'N￿ANDU', which sorts
  /// after NANDU and still before OCAMPO.
  static String _sortKey(String name) {
    const accented = 'ÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÇ';
    const plain = 'AAAAAAEEEEIIIIOOOOOUUUUC';
    final buf = StringBuffer();
    for (final rune in name.toUpperCase().runes) {
      final ch = String.fromCharCode(rune);
      if (ch == 'Ñ') {
        buf.write('N￿');
        continue;
      }
      final i = accented.indexOf(ch);
      buf.write(i >= 0 ? plain[i] : ch);
    }
    return buf.toString();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await fetchWorkerRoles();
      if (!mounted) return;
      setState(() => _roles = roles);
    } catch (_) {
      // Filter row just stays collapsed; the list itself is unaffected.
    }
  }

  Future<void> loadWorkers() async {
    try {
      final response = await http.get(
        u('/workers'),
        headers: await authHeaders(json: false),
      );
      if (!mounted) return;
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
      debugPrint('Error al cargar trabajadores: $e');
      if (!mounted) return;
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
      final resp = await http.get(
        u('/me'),
        headers: await authHeaders(json: false),
      );
      if (!mounted || resp.statusCode != 200) return;
      final me = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _isAdmin = me['is_admin'] == true);
    } catch (_) {
      // not admin / offline: admin-only actions stay hidden
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
      u('/delete-workers'),
      headers: await authHeaders(),
      body: jsonEncode({'ids': ids}),
    );
    if (!mounted) return;
    if (response.statusCode != 200) {
      debugPrint('Error al eliminar trabajadores: ${response.body}');
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

    // Selection survives the search and role filters, so some of these may be
    // off-screen right now. Naming them is the safeguard: a count alone would
    // let someone delete a worker they cannot see.
    final selectedNames =
        workers.where((w) => selectedIds.contains(w.id)).map((w) => w.name).toList()
          ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CONFIRMAR ELIMINAR TRABAJADORES'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VAS A ELIMINAR ${selectedIds.length} TRABAJADOR(ES):'),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final name in selectedNames)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '• $name',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('INGRESA LA CONTRASEÑA PARA CONFIRMAR:'),
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
                final navigator = Navigator.of(context);
                final idsToDelete = selectedIds.toList();
                await deleteWorkersFromBackend(idsToDelete);
                await loadWorkers();
                if (!mounted) return;
                setState(() => selectedIds.clear());
                navigator.pop();
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
    // Skip empty segments: a trailing/double space would otherwise make
    // p[0] throw a RangeError on an empty string.
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.map((p) => p[0]).take(2).join().toUpperCase();
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

    // Both predicates, then sort. The two filters are commutative; the sort
    // runs last so it orders whatever survived.
    final filteredWorkers =
        workers.where((w) {
          final matchesName =
              w.name.toUpperCase().contains(searchQuery.toUpperCase());
          final matchesRole =
              roleFilter == _allRoles || w.role.trim() == roleFilter;
          return matchesName && matchesRole;
        }).toList()
          ..sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));

    final hasActiveFilter = roleFilter != _allRoles || searchQuery.isNotEmpty;

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
          // Hidden during multi-select so it does not sit next to the delete
          // action. Admin-only because creating an absence is admin-only
          // server-side — and because it destroys attendance rows.
          if (selectedIds.isEmpty && _isAdmin)
            IconButton(
              tooltip: 'AUSENCIAS',
              icon: const Icon(Icons.event_busy),
              color: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AbsencesScreen()),
              ),
            ),
          if (selectedIds.isNotEmpty) ...[
            Center(
              child: Text(
                '${selectedIds.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Deleting workers is admin-only server-side; hide it for the rest.
            if (_isAdmin)
              IconButton(
                tooltip: 'ELIMINAR SELECCIONADOS',
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
                      controller: _searchController,
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
                    if (_roles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _filterChip(_allRoles),
                            ..._roles.map(_filterChip),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: filteredWorkers.isEmpty
                    // Scrollable so pull-to-refresh still works when empty
                    // (e.g. after a failed load).
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              // "No workers at all" and "no match for these
                              // filters" are different problems; saying the
                              // first when a filter is active reads as data
                              // loss.
                              hasActiveFilter
                                  ? 'SIN RESULTADOS'
                                  : 'NO HAY TRABAJADORES',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          if (hasActiveFilter) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: TextButton(
                                onPressed: () => setState(() {
                                  roleFilter = _allRoles;
                                  searchQuery = '';
                                  _searchController.clear();
                                }),
                                child: const Text(
                                  'QUITAR FILTROS',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ],
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
                          final isSelected = selectedIds.contains(worker.id);
                          return _WorkerCard(
                            worker: worker,
                            isSelected: isSelected,
                            onTap: () {
                              // Selection only exists to feed the bulk
                              // delete, which is admin-only server-side.
                              // UX gate only — the server is the boundary.
                              if (_isAdmin && selectedIds.isNotEmpty) {
                                setState(() {
                                  isSelected
                                      ? selectedIds.remove(worker.id)
                                      : selectedIds.add(worker.id);
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
                            onLongPress: !_isAdmin
                                ? null
                                : () {
                                    setState(() {
                                      isSelected
                                          ? selectedIds.remove(worker.id)
                                          : selectedIds.add(worker.id);
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openWorkerForm,
        backgroundColor: const Color(0xFF1C1CF0),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  /// One chip per role, plus TODOS. Label and value are the same string —
  /// the earlier commented-out version took them separately and initialised
  /// roleFilter to 'TODOS' while comparing against 'Todos', so nothing ever
  /// matched. A single sentinel avoids that whole class of bug.
  Widget _filterChip(String value) {
    final isSelected = roleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          value,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        showCheckmark: false,
        // Deselecting a chip falls back to TODOS rather than an empty filter.
        onSelected: (selected) =>
            setState(() => roleFilter = selected ? value : _allRoles),
        backgroundColor: Colors.white70,
        selectedColor: const Color(0xFF1C1CF0),
        side: const BorderSide(color: Colors.white24),
      ),
    );
  }

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

  /// Null for non-admins: selection feeds the admin-only bulk delete, so
  /// there is nothing for them to select. GestureDetector simply ignores
  /// the gesture when this is null.
  final VoidCallback? onLongPress;
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
                              // The tenth media fetch, and the one a grep for
                              // `imageUrl:` misses — this is the ImageProvider
                              // form, not the widget, so the header parameter
                              // is `headers`, not `httpHeaders`. A
                              // DecorationImage has no errorWidget either, so a
                              // failure here is a silent blue box rather than a
                              // broken-image icon.
                              image: CachedNetworkImageProvider(
                                worker.photoUrl!,
                                headers: authHeadersSync(),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
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
