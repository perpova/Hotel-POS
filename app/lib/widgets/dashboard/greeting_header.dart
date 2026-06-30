import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../api_service.dart';
import '../../services/translation_service.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({Key? key}) : super(key: key);

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning!';
    } else if (hour < 17) {
      return 'Good Afternoon!';
    } else {
      return 'Good Evening!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = APIService.instance.currentUser?.name ?? 'Guest User';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getGreeting().tr(context),
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE91E63), // Primary Pink
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user == 'Guest User' ? 'Guest User'.tr(context) : user,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B), // Dark text slate
              ),
            ),
          ],
        ),
        const Spacer(),
        // Version capsule badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5), // Light pink background
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFC0CB), width: 1.5),
          ),
          child: Text(
            'Version : 3.9'.tr(context),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFE91E63), // Vibrant pink
            ),
          ),
        ),
      ],
    );
  }
}
