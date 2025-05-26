import 'package:flutter/material.dart';

class ToolsInventoryScreen extends StatefulWidget {
  const ToolsInventoryScreen({super.key});

  @override
  State<ToolsInventoryScreen> createState() => _ToolsInventoryScreenState();
}

class _ToolsInventoryScreenState extends State<ToolsInventoryScreen> {
  final List<Map<String, dynamic>> tools = [
    {'name': 'Hammer', 'quantity': 5},
    {'name': 'Drill', 'quantity': 2},
    {'name': 'Ladder', 'quantity': 3},
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  void _addTool() {
    final name = _nameController.text.trim();
    final qty = int.tryParse(_quantityController.text);
    if (name.isNotEmpty && qty != null) {
      setState(() {
        tools.add({'name': name, 'quantity': qty});
      });
      _nameController.clear();
      _quantityController.clear();
      Navigator.pop(context);
    }
  }

  void _showAddToolDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Tool Name'),
            ),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('Cancel')),
          ElevatedButton(onPressed: _addTool, child: const Text('Add')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools Inventory')),
      body: ListView.builder(
        itemCount: tools.length,
        itemBuilder: (context, index) {
          final tool = tools[index];
          return ListTile(
            leading: const Icon(Icons.build),
            title: Text(tool['name']),
            trailing: Text('Qty: ${tool['quantity']}'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddToolDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
