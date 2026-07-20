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
    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime.now();
      try {
        return DateTime.parse(d.toString()).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }

    return ShiftLogModel(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      clockIn: parseDate(json['clock_in']),
      clockOut: json['clock_out'] != null ? parseDate(json['clock_out']) : null,
      durationMinutes: int.tryParse(json['duration_minutes']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'active',
    );
  }

  bool get isActive => status == 'active' && clockOut == null;

  String get durationFormatted {
    if (isActive) {
      final mins = DateTime.now().difference(clockIn).inMinutes;
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '${hrs}h ${remMins}m';
    } else {
      final hrs = durationMinutes ~/ 60;
      final remMins = durationMinutes % 60;
      return '${hrs}h ${remMins}m';
    }
  }
}
