import 'package:control_app/screens/screen_lista_chats.dart';
import 'package:flutter/material.dart';
import 'screens/screen_home.dart';
import 'screens/screen_obras.dart';
import 'screens/screen_inventario.dart';
import 'screens/screen_personal.dart';
import 'screens/screen_asistencia.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ControlApp',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/projects': (context) => const ProjectsScreen(),
        '/inventory': (context) => const ToolsInventoryScreen(),
        '/personnel': (context) => const AttendanceScreen(),
        '/attendance': (context) => const AttendanceRecordScreen(),
        '/chatlist': (context) => const ChatListScreen(),
      },
    );
  }
}
