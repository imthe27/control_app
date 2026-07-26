import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Future<void> _initializeApp() async {
    final token = await _storage.read(key: 'auth_token');
    if (!mounted) return;

    // Guest mode was removed. No token — or a leftover 'guest' value from an
    // older build — means "not logged in": clear it and go to login.
    if (token == null || token == 'guest') {
      await _storage.delete(key: 'auth_token');
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } else {
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
