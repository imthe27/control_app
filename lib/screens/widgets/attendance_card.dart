import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// Shared pieces of the attendance card, used by the daily screen
// (screen_record_attendance) and REGISTRO PASADO (screen_backfill_attendance).
//
// Only the parts that must look identical live here. Both screens now use the
// same affordance — tap the card to change status, extra hours on the strip
// below — and the one real difference left is that backfill can leave a worker
// UNMARKED, which is how it avoids writing attendance for a whole past-day
// roster. The shell, the photo header, the hours strip and the V/INC watermark
// are shared; a copy of them would drift.

const Color kAttendanceBlue = Color(0xFF1C1CF0);

/// Statuses rendered read-only wherever they appear. Nothing in the app can
/// SET them — the long-press selection that did was removed, and backfill never
/// offered them.
///
/// They arrive from the server, which now keeps vacaciones and incapacidad in
/// their own records and merges them into every attendance read. So a card can
/// show V or INC on a day with no saved attendance at all, and it must render
/// read-only: the value is not this screen's to change.
///
/// This is the single definition of "this status is not editable" — the daily
/// screen and REGISTRO PASADO both lock their card through
/// [isSpecialAttendanceStatus], and the daily screen's save path drops these
/// workers from its payload with the same test. Do not add a second V/INC
/// comparison anywhere; add to this set instead.
///
/// 'I' was a third member until 2026-08-10, on the stated grounds that the old
/// backfill screen wrote 'I' while the daily screen wrote 'INC' and "both
/// spellings exist in the data". That was never verified and was false:
/// `SELECT COUNT(*) FROM attendance WHERE status = 'I'` returned 0 after the
/// phase-13 migration, the server now coerces 'I' to 'INC' on the way in, and
/// no read path can emit it. Removed rather than kept as a guard, so this set
/// describes what the API actually returns.
const Set<String> kSpecialAttendanceStatuses = {'V', 'INC'};

bool isSpecialAttendanceStatus(String? status) =>
    status != null && kSpecialAttendanceStatuses.contains(status);

/// Days that are not a normal pay day: no attendance is recorded, only extra
/// hours. A worked Sunday is status '0' with extra_hours > 0 — there is no new
/// status value for it and the backend needs no change.
///
/// Named for the general concept so festivos can join later. **Today it is
/// Sunday and nothing else** — holiday handling is deliberately not here.
///
/// `DateTime.weekday` runs 1..7 with **Sunday == 7**, not 0. `weekday == 0`
/// compiles, matches nothing, and would leave this silently switched off on
/// every day of the week, so the constant is used rather than a literal.
bool isNonWorkingDay(DateTime date) => date.weekday == DateTime.sunday;

/// The only status a non-working day can carry. On a Sunday there is no
/// "presente" — just ausente plus whatever hours were worked.
///
/// Both write screens offer exactly this list on such a day, and both coerce a
/// stored '1' or '0.5' into it rather than letting one be re-saved.
const List<String> kNonWorkingDayStatuses = ['0'];

/// The notice both write screens put in their date header on a non-working day.
///
/// One string in one place. A screen whose behaviour changes with no
/// explanation reads as broken: an encargado who finds that "presente" has
/// stopped working either reports a bug or stops recording Sundays entirely,
/// which loses the extra hours — the only thing a Sunday is for.
///
/// It deliberately does not say "no se paga". What gets paid is a payroll
/// question; this states only what the app does.
const String kNonWorkingDayNotice =
    'DOMINGO — NO SE REGISTRA ASISTENCIA, SOLO HORAS EXTRA';

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
/// Three states, because backfill has three.
///
/// `true` presente · `false` ausente · **`null` sin marcar**.
///
/// The null case exists for REGISTRO PASADO, which saves only the rows that
/// were actually marked. Without a distinct look for it, "ausente" and
/// "untouched" render identically and the user cannot tell which rows the save
/// will write — the tap cycle back to unmarked would be invisible.
///
/// The daily screen passes a plain bool and is unaffected: it has no unmarked
/// state, since it always sends every worker on the obra.
class AttendancePresentBadge extends StatelessWidget {
  final bool? isPresent;

  const AttendancePresentBadge({super.key, required this.isPresent});

  @override
  Widget build(BuildContext context) {
    final present = isPresent == true;
    final unmarked = isPresent == null;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: present ? Colors.green : Colors.white.withValues(alpha: 0.85),
        border: Border.all(
          color: present ? Colors.green : Colors.grey[400]!,
          width: 1.5,
        ),
      ),
      // A dash rather than an empty circle: an empty corner reads as a
      // rendering fault, the same reason the non-working badge says DOM
      // instead of hiding itself.
      child: Icon(
        unmarked ? Icons.remove : Icons.check,
        size: 16,
        color: present ? Colors.white : Colors.grey[400],
      ),
    );
  }
}

/// Replaces [AttendancePresentBadge] on a non-working day.
///
/// The present badge is a check that is green or grey. On a Sunday every card
/// is '0' by rule, so it would be grey on every card and read "everyone was
/// absent" — the exact opposite of the point, since Sunday is the day the
/// extra hours ARE the record. Hiding it instead leaves an empty corner that
/// reads as a rendering fault, so the corner says what the day is.
class AttendanceNonWorkingBadge extends StatelessWidget {
  /// Short enough for a card corner. The date header carries the full
  /// explanation; this only has to stop the corner from lying.
  final String label;

  const AttendanceNonWorkingBadge({super.key, this.label = 'DOM'});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE65100),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
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

/// Full-card overlay for V / INC. No attendance screen sets these; they are
/// created on the AUSENCIAS screen and the server merges them into the `status`
/// of every attendance read, so any screen showing attendance has to render
/// them — greyed out and inert.
class AttendanceStatusWatermark extends StatelessWidget {
  final String status;

  const AttendanceStatusWatermark({super.key, required this.status});

  String get _label {
    switch (status) {
      case 'V':
        return 'VACACIONES';
      case 'INC':
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
