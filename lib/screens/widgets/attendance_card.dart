import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// Shared pieces of the attendance card, used by the daily screen
// (screen_record_attendance) and REGISTRO PASADO (screen_backfill_attendance).
//
// Only the parts that must look identical live here. Each screen keeps its own
// status affordance: the daily screen toggles presente/falta on tap, while
// backfill picks from 1 / 0.5 / 0 / F and can leave a worker unmarked. That
// difference is real; the shell, the photo header, the hours strip and the
// V/INC watermark are not, and a copy of them would drift.

const Color kAttendanceBlue = Color(0xFF1C1CF0);

/// Statuses rendered read-only wherever they appear. Nothing in the app can
/// SET them any more — the long-press selection that did was removed, and
/// backfill no longer offers them either — but historical rows still carry
/// them. 'INC' and 'I' are both here on purpose: the daily screen historically
/// wrote 'INC' while backfill wrote 'I', and the backend validates neither, so
/// both spellings exist in the data. Match both or such a row renders as a
/// plain absence.
const Set<String> kSpecialAttendanceStatuses = {'V', 'INC', 'I'};

bool isSpecialAttendanceStatus(String? status) =>
    status != null && kSpecialAttendanceStatuses.contains(status);

/// One ink colour for both watermarks. V and INC/I are told apart by the icon
/// and the label, not by hue — a coloured icon on a greyed-out card reads as
/// active, which is the opposite of what these rows are.
const Color _watermarkInk = Color(0xFF424242);

String attendanceInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.map((p) => p[0]).take(2).join().toUpperCase();
}

BoxDecoration attendanceCardDecoration(bool isSpecial) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white24, width: 0.5),
    color: isSpecial
        ? Colors.grey[400]!.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

/// Blue header with the worker's photo, falling back to initials.
class AttendancePhotoHeader extends StatelessWidget {
  final String? photoUrl;
  final String initials;

  const AttendancePhotoHeader({
    super.key,
    required this.photoUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        color: kAttendanceBlue,
      ),
      child: photoUrl == null
          ? Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue[400]!, Colors.blue[600]!],
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          : ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.yellow),
                ),
                errorWidget: (context, url, error) =>
                    const Center(child: Icon(Icons.person)),
              ),
            ),
    );
  }
}

class AttendanceNameBlock extends StatelessWidget {
  final String name;

  const AttendanceNameBlock({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Green tick shown when the worker is marked present.
class AttendancePresentBadge extends StatelessWidget {
  final bool isPresent;

  const AttendancePresentBadge({super.key, required this.isPresent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPresent ? Colors.green : Colors.white.withValues(alpha: 0.85),
        border: Border.all(
          color: isPresent ? Colors.green : Colors.grey[400]!,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.check,
        size: 16,
        color: isPresent ? Colors.white : Colors.grey[400],
      ),
    );
  }
}

/// Horizontal picker for extra hours (HE), 0 to 10 in half-hour steps.
///
/// Owns its PageController, so the value it shows is the one it was built
/// with: a parent that changes [value] externally (zeroing the hours when a
/// status flips, say) does not scroll the strip back. That is the daily
/// screen's long-standing behaviour, kept here rather than quietly changed.
class AttendanceHoursStrip extends StatefulWidget {
  final String value;

  /// False disables interaction without changing the look, for read-only days
  /// and for statuses that cannot carry hours.
  final bool enabled;

  /// Greys the strip's backing to match a V/INC/I card.
  final bool isSpecial;

  final ValueChanged<String> onChanged;

  const AttendanceHoursStrip({
    super.key,
    required this.value,
    required this.enabled,
    required this.isSpecial,
    required this.onChanged,
  });

  @override
  State<AttendanceHoursStrip> createState() => _AttendanceHoursStripState();
}

class _AttendanceHoursStripState extends State<AttendanceHoursStrip> {
  static const List<double> heOptions = [
    0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0,
    5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0
  ];

  late PageController _heController;

  @override
  void initState() {
    super.initState();
    final currentValue = double.tryParse(widget.value) ?? 0.0;
    final initialIndex =
        heOptions.indexOf(currentValue).clamp(0, heOptions.length - 1);
    _heController = PageController(
      viewportFraction: 0.35,
      initialPage: initialIndex,
    );
  }

  @override
  void dispose() {
    _heController.dispose();
    super.dispose();
  }

  String _formatHours(double hours) {
    return hours == hours.toInt() ? '${hours.toInt()}' : '$hours';
  }

  @override
  Widget build(BuildContext context) {
    final hoursValue = double.tryParse(widget.value) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        color: widget.isSpecial ? Colors.grey[100] : Colors.blue[50],
      ),
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: PageView.builder(
          controller: _heController,
          itemCount: heOptions.length,
          onPageChanged: (index) {
            widget.onChanged(heOptions[index].toString());
          },
          itemBuilder: (context, index) {
            final hours = heOptions[index];
            final isSelectedHours = hoursValue == hours;
            return Center(
              child: GestureDetector(
                onTap: () {
                  _heController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isSelectedHours ? kAttendanceBlue : Colors.white,
                      border: Border.all(
                        color: isSelectedHours
                            ? Colors.yellow
                            : Colors.grey[300]!,
                        width: isSelectedHours ? 1.5 : 0.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'HE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isSelectedHours
                                ? Colors.white70
                                : Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatHours(hours),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelectedHours
                                ? Colors.white
                                : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Full-card overlay for V / INC / I. Nothing in the app sets these any more,
/// but historical rows carry them, so every screen that shows attendance has
/// to render them — greyed out and inert.
class AttendanceStatusWatermark extends StatelessWidget {
  final String status;

  const AttendanceStatusWatermark({super.key, required this.status});

  String get _label {
    switch (status) {
      case 'V':
        return 'VACACIONES';
      case 'INC':
      case 'I':
        return 'INCAPACITADO';
      default:
        return '';
    }
  }

  IconData get _icon =>
      status == 'V' ? Icons.beach_access : Icons.local_hospital;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.grey[400]!.withValues(alpha: 0.88),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _icon,
                size: 56,
                color: _watermarkInk.withValues(alpha: 0.70),
              ),
              const SizedBox(height: 6),
              Text(
                _label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _watermarkInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
