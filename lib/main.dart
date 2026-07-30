import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'screens/screen_splash.dart';
import 'screens/screen_home.dart';
import 'screens/screen_login.dart';
import 'screens/screen_project_selection.dart';
import 'screens/screen_personnel.dart';
import 'screens/screen_record_attendance.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show runWithClient;
import 'package:control_app/api.dart' show AuthClient, navigatorKey;

/// [runWithClient] installs [AuthClient] for the whole zone, so every
/// top-level `http.get`/`http.post` in the app routes through it and an
/// expired session is caught in one place — including from call sites added
/// later, which is the part an opt-in check cannot guarantee.
///
/// Anything that needs early binding initialisation
/// (`WidgetsFlutterBinding.ensureInitialized()`) must go **inside** this
/// callback. Initialising the binding in a different zone from [runApp]
/// throws a zone-mismatch error at startup.
void main() {
  runWithClient(() => runApp(const MainApp()), AuthClient.new);
}

const String baseUrlProd = 'https://api.cotelsa-app.com';
const String baseUrlDev = 'http://192.168.1.7:8000';
final String baseUrl = kDebugMode ? baseUrlDev : baseUrlProd;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
