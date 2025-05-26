import 'package:flutter/material.dart';
import 'screen_chat.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chats = [
      {'name': 'Luis Pérez', 'lastMessage': 'Ya terminé el muro.'},
      {'name': 'Jorge Ramos', 'lastMessage': '¿Dónde está la escalera?'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: ListView.builder(
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(chat['name']!),
            subtitle: Text(chat['lastMessage']!),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(name: chat['name']!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
