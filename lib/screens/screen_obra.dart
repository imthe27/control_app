import 'package:flutter/material.dart';
import 'screen_asistencia.dart';

class ProjectTasksScreen extends StatelessWidget {
  final String projectName;

  const ProjectTasksScreen({super.key, required this.projectName});

  @override
  Widget build(BuildContext context) {
    final cards = [
      {'title': 'Asistencia', 'icon': Icons.person, 'color': Colors.blue[100]},
      {'title': '-', 'icon': Icons.work, 'color': Colors.blue[100]},
      {'title': '-', 'icon': Icons.check_circle, 'color': Colors.blue[100]},
      {'title': '=', 'icon': Icons.add_circle, 'color': Colors.blue[100]},
    ];

    return Scaffold(
      appBar: AppBar(title: Text(projectName)),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return GestureDetector(
              onTap: () {
                switch (index) {
                  case 0:
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceRecordScreen()));
                    break;
                  case 1:
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Text("En proceso"),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                        ],
                      ),
                    );
                    break;
                  case 2:
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Text("En proceso"),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                        ],
                      ),
                    );
                    break;
                  case 3:
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Text("En proceso"),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                        ],
                      ),
                    );
                    break;
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: card['color'] as Color?,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(card['icon'] as IconData, size: 36, color: Colors.black54),
                    const SizedBox(height: 12),
                    Text(
                      card['title'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
