import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/translation_service.dart';
import '../../services/api_service.dart';
import '../../theme.dart';

class ReminderBanner extends StatefulWidget {
  const ReminderBanner({Key? key}) : super(key: key);

  @override
  State<ReminderBanner> createState() => _ReminderBannerState();
}

class _ReminderBannerState extends State<ReminderBanner> {
  List<String> _lowStockItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkWarnings();
  }

  Future<void> _checkWarnings() async {
    try {
      final products = await APIService.instance.getProducts();
      final ingredients = await APIService.instance.getIngredients();

      final List<String> lowStockNames = [];
      for (var p in products) {
        if (p.trackStock && p.stockQty <= p.minStockLevel) {
          lowStockNames.add(p.name);
        }
      }
      for (var ing in ingredients) {
        if (ing.stockQty <= ing.minStockLevel) {
          lowStockNames.add(ing.name);
        }
      }

      if (mounted) {
        setState(() {
          _lowStockItems = lowStockNames;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
        ),
      );
    }

    final hasWarnings = _lowStockItems.isNotEmpty;

    // Warning Banner style (Amber tint)
    final bannerBg = AppTheme.isDarkMode 
        ? Colors.amber.withOpacity(0.08) 
        : const Color(0xFFFFFBEB);
    final borderCol = AppTheme.isDarkMode 
        ? Colors.amber.withOpacity(0.2) 
        : const Color(0xFFFDE68A);
    final titleCol = AppTheme.isDarkMode 
        ? Colors.amber[300] 
        : const Color(0xFFB45309);
    final textCol = AppTheme.isDarkMode 
        ? Colors.amber[100] 
        : const Color(0xFF92400E);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderCol, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasWarnings ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: titleCol,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasWarnings ? 'Low Stock Warning!'.tr(context) : 'System Status'.tr(context),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: titleCol,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasWarnings 
                      ? 'The following items are running below minimum stock levels: ${_lowStockItems.join(", ")}'
                      : 'All menu items and raw materials are currently above their minimum stock thresholds.'.tr(context),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textCol,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
