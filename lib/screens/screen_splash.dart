import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:control_app/api.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// **This method's ordering is load-bearing.** `authHeadersSync()` backs the
  /// ten media render sites, which cannot await inside `build()`, so the token
  /// must be in memory before any of them exists. It is, because `build()` here
  /// draws only a spinner and navigation happens after the `await` below — no
  /// image widget can be constructed until this has run. Never navigate before
  /// seeding the token, or the first screen's photos race the read and go out
  /// unauthenticated.
  ///
  /// Seeded from the value already read here rather than by calling
  /// `primeAuthToken()`, which would repeat the same secure-storage read.
  Future<void> _initializeApp() async {
    final token = await _storage.read(key: 'auth_token');
    if (!mounted) return;

    // Guest mode was removed. No token — or a leftover 'guest' value from an
    // older build — means "not logged in": clear it and go to login.
    if (token == null || token == 'guest') {
      await _storage.delete(key: 'auth_token');
      clearAuthToken();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      setAuthToken(token);
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Colors.yellow)),
    );
  }
}
