import 'package:intl/intl.dart';

/// Parses a date string returned from server / database without double-applying timezone offsets.
/// Server timestamps (e.g. "2026-07-24 19:07:29" or "2026-07-24T19:07:29.000Z") are already recorded
/// in local store time. This helper extracts the exact recorded local date & time.
DateTime parseServerDateTime(dynamic dateInput) {
  if (dateInput == null) return DateTime.now();
  final String dateStr = dateInput.toString().trim();
  if (dateStr.isEmpty) return DateTime.now();

  try {
    if (dateStr.endsWith('Z') || dateStr.contains('+') || dateStr.contains('T')) {
      final parsedIso = DateTime.tryParse(dateStr);
      if (parsedIso != null) {
        return parsedIso.toLocal();
      }
    }

    String s = dateStr.replaceAll('T', ' ');
    if (s.contains('+')) s = s.split('+').first.trim();
    if (s.contains('Z')) s = s.replaceAll('Z', '').trim();
    if (s.contains('.')) s = s.split('.').first.trim();

    final parts = s.split(' ');
    if (parts.length >= 2) {
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      if (dateParts.length == 3 && timeParts.length >= 2) {
        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
        return DateTime(year, month, day, hour, minute, second);
      }
    }
  } catch (_) {}

  final tryDt = DateTime.tryParse(dateStr);
  if (tryDt != null) return tryDt.toLocal();
  return DateTime.now();
}

/// Formats a server date string into a standard display string (e.g., "07:07 PM, 24-07-2026")
String formatServerDate(dynamic dateInput, {String pattern = 'hh:mm a, dd-MM-yyyy'}) {
  if (dateInput == null) return '';
  final dt = parseServerDateTime(dateInput);
  return DateFormat(pattern).format(dt);
}
