import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/shift_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<ShiftProvider>();
    final list = shift.history;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Shift Attendance History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: list.isEmpty
          ? const Center(
              child: Text('No past shift history found', style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final item = list[i];
                final inStr = DateFormat('hh:mm a, dd MMM yyyy').format(item.clockIn);
                final outStr = item.clockOut != null
                    ? DateFormat('hh:mm a, dd MMM yyyy').format(item.clockOut!)
                    : 'Active Shift';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: item.isActive ? AppColors.success.withOpacity(0.4) : AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.isActive ? AppColors.success.withOpacity(0.15) : AppColors.bgCardAlt,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.isActive ? 'ACTIVE' : 'COMPLETED',
                              style: TextStyle(
                                color: item.isActive ? AppColors.success : AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            item.durationFormatted,
                            style: const TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Clock In row
                      Row(
                        children: [
                          const Icon(Icons.login_rounded, color: AppColors.success, size: 16),
                          const SizedBox(width: 8),
                          const Text('Clock In: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          Text(inStr, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Clock Out row
                      Row(
                        children: [
                          const Icon(Icons.logout_rounded, color: AppColors.error, size: 16),
                          const SizedBox(width: 8),
                          const Text('Clock Out: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          Text(outStr, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
