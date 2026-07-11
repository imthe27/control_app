import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:control_app/main.dart' show baseUrl;

/// Checks the server for a newer APK and guides the user through the update.
///
/// Usage (e.g. in HomeScreen.initState):
///   WidgetsBinding.instance.addPostFrameCallback(
///     (_) => UpdateChecker.check(context),
///   );
class UpdateChecker {
  UpdateChecker._();

  /// When [silent] is true (default), network errors and "already up to date"
  /// are ignored — ideal for the automatic check on startup.
  /// Set [silent] to false to show feedback (e.g. a manual "check" button).
  static Future<void> check(BuildContext context, {bool silent = true}) async {
    try {
      // 1. Current installed version
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // 2. Latest version on the server
      final resp = await http
          .get(Uri.parse('$baseUrl/app-version'))
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200 ||
          !(resp.headers['content-type'] ?? '').contains('application/json')) {
        if (!silent && context.mounted) {
          _snack(context, 'No se pudo consultar la versión (HTTP ${resp.statusCode})');
        }
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final remoteBuild = (data['build'] ?? 0) as num;
      final remoteVersion = (data['version'] ?? '?').toString();
      final notes = (data['notes'] ?? '').toString();

      if (remoteBuild <= currentBuild) {
        if (!silent && context.mounted) {
          _snack(context, 'Ya tienes la última versión (${info.version})');
        }
        return;
      }

      // 3. Newer version available → ask the user
      if (!context.mounted) return;
      final wantsUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.system_update, color: Color(0xFF1C1CF0)),
              SizedBox(width: 8),
              Text('ACTUALIZACIÓN'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nueva versión disponible: $remoteVersion'),
              Text('Versión actual: ${info.version}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(notes, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('DESPUÉS'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C1CF0),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ACTUALIZAR'),
            ),
          ],
        ),
      );

      if (wantsUpdate != true || !context.mounted) return;

      // 4. Download + install
      await _downloadAndInstall(context, remoteVersion);
    } on TimeoutException {
      if (!silent && context.mounted) {
        _snack(context, 'El servidor no respondió');
      }
    } catch (e) {
      if (!silent && context.mounted) {
        _snack(context, 'Error al buscar actualización: $e');
      }
    }
  }

  static Future<void> _downloadAndInstall(
      BuildContext context, String version) async {
    final progress = ValueNotifier<double?>(null); // null = indeterminate

    // Progress dialog (not dismissible)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('DESCARGANDO...'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: const Color(0xFF1C1CF0),
                  backgroundColor: Colors.grey[200],
                ),
                const SizedBox(height: 12),
                Text(
                  value == null
                      ? 'Conectando...'
                      : '${(value * 100).toStringAsFixed(0)} %',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('$baseUrl/app-download'));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/control_app_$version.apk');
      final sink = file.openWrite();

      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          progress.value = received / total;
        }
      }
      await sink.close();

      if (context.mounted) Navigator.pop(context); // close progress dialog

      // 5. Launch the Android installer.
      // First time, Android will ask to allow installs from this app.
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        _snack(context, 'No se pudo abrir el instalador: ${result.message}');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        _snack(context, 'Error al descargar: $e');
      }
    } finally {
      client.close();
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}