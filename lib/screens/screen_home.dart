import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cards = [
      {'title': 'Obras',
        'icon': Icons.construction,
        'color': Colors.blue[900],
        'action': () => Navigator.pushNamed(context, '/projects')
      },
      {'title': 'Personal',
        'icon': Icons.people,
        'color': Colors.blue[900],
        'action': () => Navigator.pushNamed(context, '/personnel')
      },
      {'title': 'Compras',
        'icon': Icons.monetization_on,
        'color': Colors.blue[900],
        'action': () => Navigator.pushNamed(context, '/attendance')
      },
      {'title': 'Inventario',
        'icon': Icons.check_circle,
        'color': Colors.blue[900],
        'action': () => Navigator.pushNamed(context, '/inventory')
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('COTELSA')),
      body: Column(
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              shrinkWrap: true, // Important: only takes needed height
              physics: const NeverScrollableScrollPhysics(), // Disable scroll
              children: cards.map((card) {
                return GestureDetector(
                  onTap: card['action'] as VoidCallback,
                  child: Container(
                    decoration: BoxDecoration(
                      color: card['color'] as Color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(card['icon'] as IconData, size: 45, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          card['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
