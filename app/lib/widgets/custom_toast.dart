import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomToast {
  static void show(BuildContext context, String message, String type) {
    Color barColor;
    Color iconBgColor;
    IconData iconData;

    switch (type) {
      case 'success':
        barColor = const Color(0xFF10B981);
        iconBgColor = const Color(0xFF10B981);
        iconData = Icons.check;
        break;
      case 'error':
        barColor = const Color(0xFFEF4444);
        iconBgColor = const Color(0xFFEF4444);
        iconData = Icons.close;
        break;
      case 'warning':
      default:
        barColor = const Color(0xFFF59E0B);
        iconBgColor = const Color(0xFFF59E0B);
        iconData = Icons.priority_high;
        break;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 110,
          left: MediaQuery.of(context).size.width > 500
              ? MediaQuery.of(context).size.width - 380
              : 20,
          right: 20,
        ),
        duration: const Duration(seconds: 3),
        content: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: iconBgColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          iconData,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF1E293B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        },
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFF94A3B8),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 4,
                color: barColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension BuildContextToast on BuildContext {
  void showSuccessToast(String message) {
    CustomToast.show(this, message, 'success');
  }

  void showErrorToast(String message) {
    CustomToast.show(this, message, 'error');
  }

  void showWarningToast(String message) {
    CustomToast.show(this, message, 'warning');
  }
}
