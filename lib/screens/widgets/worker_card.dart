import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Section card shared by the worker ficha (`screen_worker`) and the worker
/// form (`screen_worker_form`).
///
/// Both screens grew their own near-identical helper — `_infoCard` and
/// `_sectionCard` — which had already drifted a few pixels apart in padding
/// and title spacing. One widget means they cannot drift again.
class WorkerSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const WorkerSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Circular worker photo with a person-icon fallback.
///
/// The ficha renders one from a URL, the form from either a URL or a
/// freshly-picked [File]. Both had their own copy with the same fallback,
/// and the form's copy had no handling for a URL that fails to load.
///
/// This does NOT own the photo *upload* — that stays in the form's
/// `_uploadPhoto`, on the save path, deliberately untouched.
class WorkerAvatar extends StatelessWidget {
  final String? photoUrl;
  final File? file;
  final double diameter;

  /// Backdrop behind the fallback icon. The ficha sits on white, the form on
  /// the blue gradient, so they want different fills.
  final Color placeholderColor;
  final Color iconColor;

  const WorkerAvatar({
    super.key,
    this.photoUrl,
    this.file,
    required this.diameter,
    required this.placeholderColor,
    this.iconColor = Colors.white,
  });

  Widget _placeholder() => Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: Icon(Icons.person, size: diameter * 0.55, color: iconColor),
      );

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (file != null) {
      inner = Image.file(file!, fit: BoxFit.cover);
    } else if (photoUrl != null) {
      inner = CachedNetworkImage(
        imageUrl: photoUrl!,
        fit: BoxFit.cover,
        errorWidget: (c, url, e) => _placeholder(),
      );
    } else {
      inner = _placeholder();
    }

    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: inner),
    );
  }
}
