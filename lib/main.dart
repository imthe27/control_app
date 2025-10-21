import 'package:flutter/material.dart';
import 'screens/screen_splash.dart';
import 'screens/screen_home.dart';
import 'screens/screen_login.dart';
import 'screens/screen_obras.dart';
import 'screens/screen_personal.dart';
import 'screens/screen_asistencia.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const MainApp());
}

const String baseUrlProd = 'https://f542a22302b6.ngrok-free.app';
const String baseUrlDev = 'http://192.168.1.7:8000';
final String baseUrl = kDebugMode ? baseUrlDev : baseUrlProd;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ControlApp',
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/projects': (context) => const ProjectsScreen(),
        '/personnel': (context) => const AttendanceScreen(),
        '/attendance': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return AttendanceRecordScreen(projectId: args['projectId']);
        },
      },
    );
  }
}
