class StaffUserModel {
  final int id;
  final String name;
  final String username;
  final String role;
  final String? email;
  final String? phone;

  StaffUserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.email,
    this.phone,
  });

  factory StaffUserModel.fromJson(Map<String, dynamic> json) {
    return StaffUserModel(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'role': role,
        'email': email,
        'phone': phone,
      };
}

DateTime parseServerDate(dynamic d) {
  if (d == null) return DateTime.now();
  final str = d.toString().trim();
  if (str.isEmpty) return DateTime.now();
  try {
    // Backend MySQL stores local wall-clock times.
    // Node.js JSON serialization turns Date objects into ISO strings ending with 'Z' (e.g. "2026-07-24T15:58:00.000Z").
    // Stripping 'Z' ensures Dart parses wall-clock time as local time rather than double-applying timezone offset.
    final cleanStr = str.replaceAll(RegExp(r'[Zz]'), '');
    final parsed = DateTime.parse(cleanStr);
    return parsed.isUtc ? parsed.toLocal() : parsed;
  } catch (_) {
    return DateTime.now();
  }
}

class ShiftLogModel {
  final int id;
  final int userId;
  final DateTime clockIn;
  final DateTime? clockOut;
  final int durationMinutes;
  final String status;

  ShiftLogModel({
    required this.id,
    required this.userId,
    required this.clockIn,
    this.clockOut,
    required this.durationMinutes,
    required this.status,
  });

  factory ShiftLogModel.fromJson(Map<String, dynamic> json) {
    return ShiftLogModel(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      clockIn: parseServerDate(json['clock_in']),
      clockOut: json['clock_out'] != null ? parseServerDate(json['clock_out']) : null,
      durationMinutes: int.tryParse(json['duration_minutes']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'active',
    );
  }

  bool get isActive => status == 'active' && clockOut == null;

  String get durationFormatted {
    if (isActive) {
      final mins = DateTime.now().difference(clockIn).inMinutes;
      final validMins = mins < 0 ? 0 : mins;
      final hrs = validMins ~/ 60;
      final remMins = validMins % 60;
      return '${hrs}h ${remMins}m';
    } else {
      final hrs = durationMinutes ~/ 60;
      final remMins = durationMinutes % 60;
      return '${hrs}h ${remMins}m';
    }
  }
}
