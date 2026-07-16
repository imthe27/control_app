import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'screens/screen_splash.dart';
import 'screens/screen_home.dart';
import 'screens/screen_login.dart';
import 'screens/screen_project_selection.dart';
import 'screens/screen_personnel.dart';
import 'screens/screen_record_attendance.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const MainApp());
}

const String baseUrlProd = 'https://api.cotelsa-app.com';
const String baseUrlDev = 'http://192.168.1.7:8000';
final String baseUrl = kDebugMode ? baseUrlDev : baseUrlProd;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COTELSA',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF1C1CF0),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          }
        )
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/projects': (context) => const ProjectSelectionScreen(),
        '/personnel': (context) => const PersonnelScreen(),
        '/attendance': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return RecordAttendanceScreen(projectId: args['projectId']);
        },
      },
    );
  }
}
