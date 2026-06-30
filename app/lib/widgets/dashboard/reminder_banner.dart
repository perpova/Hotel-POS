import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/translation_service.dart';

class ReminderBanner extends StatelessWidget {
  const ReminderBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F2), // Light pink background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD5DB), width: 1), // Soft pink border
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reminder!'.tr(context),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFD63384), // Deep pink / magenta text
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dummy data will be reset in every 60 minutes.'.tr(context),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFE91E63), // Vibrant pink body text
            ),
          ),
        ],
      ),
    );
  }
}
