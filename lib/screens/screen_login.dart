import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:control_app/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        u('/login'),
        headers: jsonHeaders,
        body: jsonEncode({
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];

        final storage = FlutterSecureStorage();
        await storage.write(key: 'auth_token', value: token);
        // Seed the sync mirror before navigating: /home renders photos, and
        // authHeadersSync() cannot await a storage read inside build().
        setAuthToken(token);
        // Re-arm the global 401 guard: this session is valid again.
        resetUnauthorizedGuard();

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() => _errorMessage = 'Credenciales incorrectas');
      }
    } catch (_) {
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error de conexión'),
          content: const Text('No se pudo conectar al servidor. Verifica tu red.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('INICIAR SESIÓN'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue, Color(0xFF1C1CF0)],
            ),
          ),
        ),
        titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1CF0), Color(0xFF0000CD)],
          ),
        ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 100,
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                  labelText: 'USUARIO',
                labelStyle: const TextStyle(color: Colors.white),
              ),
              style: TextStyle(color: Colors.white),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                  labelText: 'CONTRASEÑA',
                labelStyle: const TextStyle(color: Colors.white),
              ),
              style: const TextStyle(color: Colors.white),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (_isLoading) const CircularProgressIndicator(color: Colors.yellow,),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: const Text('ENTRAR'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}