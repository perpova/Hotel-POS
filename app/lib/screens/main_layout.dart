import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../pos_controller.dart';
import '../models/models.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/app_settings_controller.dart';
import '../services/translation_service.dart';
import '../theme.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'table_management_screen.dart';
import 'kds_screen.dart';
import 'order_queue_screen.dart';
import 'shift_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'items_screen.dart';
import 'pos_orders_screen.dart';
import 'offers_screen.dart';
import 'users_screen.dart';
import 'sales_report_screen.dart';
import 'items_report_screen.dart';
import 'credit_balance_report_screen.dart';
import 'raw_materials_screen.dart';
import 'pos_stock_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'roles_permissions_screen.dart';
import 'pre_orders_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static bool _hasLaunchedQueueWindow = false;
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;
  bool _hasShownLowStockWarning = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<String> _titles = [
    'Dashboard',
    'POS System',
    'Dining Tables',
    'Kitchen Display (KDS)',
    'Order Queue Screen',
    'Shifts & Drawer',
    'Reports & Logs',
    'Settings & Stock',
    'Items',
    'POS Orders',
    'Offers',
    'Administrators',
    'Delivery Boys',
    'Customers',
    'Employees',
    'Waiters',
    'Chefs',
    'Sales Report',
    'Items Report',
    'Credit Balance Report',
    'Raw Materials',
    'POS Stock',
    'Edit Profile',
    'Change Password',
    'Roles & Permissions',
    'Pre Orders',
  ];

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const POSScreen();
      case 2:
        return const TableManagementScreen();
      case 3:
        return const KDSScreen();
      case 4:
        return const OrderQueueScreen();
      case 5:
        return const ShiftScreen();
      case 6:
        return const ReportsScreen();
      case 7:
        return const SettingsScreen();
      case 8:
        return const ItemsScreen();
      case 9:
        return const POSOrdersScreen();
      case 10:
        return const OffersScreen();
      case 11:
        return const UsersScreen(userType: 'Administrators');
      case 12:
        return const UsersScreen(userType: 'Delivery Boys');
      case 13:
        return const UsersScreen(userType: 'Customers');
      case 14:
        return const UsersScreen(userType: 'Employees');
      case 15:
        return const UsersScreen(userType: 'Waiters');
      case 16:
        return const UsersScreen(userType: 'Chefs');
      case 17:
        return const SalesReportScreen();
      case 18:
        return const ItemsReportScreen();
      case 19:
        return const CreditBalanceReportScreen();
      case 20:
        return const RawMaterialsScreen();
      case 21:
        return const POSStockScreen();
      case 22:
        return const EditProfileScreen();
      case 23:
        return const ChangePasswordScreen();
      case 24:
        return const RolesPermissionsScreen();
      case 25:
        return const PreOrdersScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = Provider.of<POSController>(context, listen: false);
      final appSettings = Provider.of<AppSettingsController>(context, listen: false);

      // Auto launch separate queue window on secondary display if setting is enabled
      if (appSettings.extendQueueScreen && !_hasLaunchedQueueWindow) {
        _hasLaunchedQueueWindow = true;
        try {
          final executable = Platform.resolvedExecutable;
          Process.start(executable, ['--queue-screen']);
        } catch (e) {
          print('Auto-launch separate queue window error: $e');
        }
      }

      await controller.reloadEnvironment();
      controller.setupEventSubscription();
      if (controller.activeShift == null) {
        setState(() {
          _selectedIndex = 5;
        });
      }
    });
  }

  /// Renders the two-tone company name with an optional favicon/icon beside it.
  Widget _buildLogoText(String? faviconBase64, String part1, String part2) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon: custom favicon image or default restaurant icon
        if (faviconBase64 != null && faviconBase64.isNotEmpty)
          Container(
            width: 34, height: 34,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Base64ImageWidget(base64Str: faviconBase64, fit: BoxFit.cover),
          )
        else
          Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.restaurant_menu, color: AppTheme.primary, size: 22),
          ),
        // Two-tone name text
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              text: part1,
              style: GoogleFonts.outfit(
                fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary),
              children: [
                TextSpan(
                  text: part2,
                  style: GoogleFonts.outfit(
                    fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFFFB300)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCloseShiftDialog(BuildContext context, POSController posController) async {
    // Show a loading dialog first while we compute the expected drawer balance
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );

    final stats = await posController.getShiftStatistics();
    
    if (mounted) {
      Navigator.pop(context); // Dismiss loading dialog
    }

    final TextEditingController actualCashController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    if (!mounted) return;

    final String currentUser = APIService.instance.currentUser?.name ?? 'System Administrator';
    final String logoutTime = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: AppTheme.cardLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Text(
                      'Shift Close Reconciliation Report'.tr(dialogCtx),
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Count drawer cash and compare with expected balances. Closing shift prints a final Z-Report.'.tr(dialogCtx),
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                    ),
                    Divider(height: 24, color: AppTheme.borderLight),

                    // Session Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Session User:'.tr(dialogCtx), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
                        Text(currentUser, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Logout Time:'.tr(dialogCtx), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
                        Text(logoutTime, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      ],
                    ),
                    Divider(height: 24, color: AppTheme.borderLight),

                    // Cash Drawer Reconciliation
                    Text('CASH DRAWER RECONCILIATION', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    _buildReconcileRow('Starting Cash Balance', stats['cash_sales'] == 0 ? posController.activeShift!.openingBalance : (stats['expected_cash']! - stats['cash_sales']! - stats['credit_settlements']! - stats['other_cash_in']! + stats['supplier_payments']! + stats['other_cash_out']!)),
                    _buildReconcileRow('Cash Sales (+)', stats['cash_sales']!, color: const Color(0xFF16A34A)),
                    _buildReconcileRow('Credit Settlements (+)', stats['credit_settlements']!, color: const Color(0xFF16A34A)),
                    _buildReconcileRow('Other Cash In (+)', stats['other_cash_in']!, color: const Color(0xFF16A34A)),
                    _buildReconcileRow('Supplier Payments (-)', -stats['supplier_payments']!, color: const Color(0xFFDC2626)),
                    _buildReconcileRow('Other Cash Out (-)', -stats['other_cash_out']!, color: const Color(0xFFDC2626)),
                    Divider(height: 16, color: AppTheme.dividerColor),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('EXPECTED CASH IN DRAWER', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                        Text('LKR ${stats['expected_cash']!.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      ],
                    ),
                    Divider(height: 24, color: AppTheme.borderLight),

                    // Non-Cash Sales Summary
                    Text('NON-CASH SALES SUMMARY', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    _buildReconcileRow('Card Payments', stats['card_sales']!),
                    _buildReconcileRow('LankaQR Payments', stats['qr_sales']!),
                    _buildReconcileRow('Credit Sales (Outstanding Added)', stats['credit_sales']!),
                    Divider(height: 16, color: AppTheme.dividerColor),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL SHIFT SALES', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        Text('LKR ${stats['total_sales']!.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                    Divider(height: 24, color: AppTheme.borderLight),

                    // Actual counted cash input
                    Text('ACTUAL DRAWER CASH COUNT', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: actualCashController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Actual Cash Counted (LKR) *'.tr(dialogCtx),
                        hintText: '0.00',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      style: GoogleFonts.inter(fontSize: 13),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter actual cash counted';
                        }
                        if (double.tryParse(val.trim()) == null) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final actual = double.tryParse(actualCashController.text.trim()) ?? 0.0;
                        
                        try {
                          showDialog(
                            context: dialogCtx,
                            barrierDismissible: false,
                            builder: (context) => Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                          );

                          await posController.closeActiveShift(stats['expected_cash']!, actual);
                          await APIService.instance.logout();
                          
                          if (mounted) {
                            Navigator.of(dialogCtx).pop(); // Dismiss loading
                            Navigator.of(dialogCtx).pop(); // Dismiss dialog
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          }
                        } catch (e) {
                          Navigator.pop(dialogCtx); // Dismiss loading
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to close shift: $e'), backgroundColor: Colors.red),
                          );
                        }
                      },
                      icon: const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                      label: Text('Close Shift & Print Z-Report'.tr(dialogCtx), style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: Text('Cancel'.tr(dialogCtx), style: GoogleFonts.inter(color: AppTheme.textLightSecondary, fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await APIService.instance.logout();
                              if (mounted) {
                                Navigator.pop(dialogCtx);
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
                              );
                            }
                          },
                          icon: Icon(Icons.logout_outlined, size: 14, color: AppTheme.primary),
                          label: Text('Logout (Keep Shift Open)'.tr(dialogCtx), style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReconcileRow(String label, double val, {Color? color}) {
    final prefix = val > 0 ? '+' : '';
    final signStr = val == 0 ? '' : prefix;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
          Text(
            'LKR ${val.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color ?? AppTheme.textLightPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    final posController = Provider.of<POSController>(context);
    final dashController = Provider.of<DashboardController>(context);
    final appSettings = context.watch<AppSettingsController>();

    if (posController.requestedScreenIndex != null) {
      final reqIdx = posController.requestedScreenIndex!;
      posController.requestedScreenIndex = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = reqIdx;
        });
      });
    }

    final branchNames = appSettings.branches.map((b) => b.name).toList();
    if (branchNames.isEmpty) {
      branchNames.add('Main Branch');
    }
    final isAdmin = APIService.instance.currentUser?.role == 'admin';

    // Ensure selected branch is valid
    String currentSelectedBranch = dashController.selectedBranch;
    if (!branchNames.contains(currentSelectedBranch)) {
      currentSelectedBranch = branchNames.first;
      // Safely update DashboardController after build frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dashController.setBranch(branchNames.first);
      });
    }

    // Ensure selected language is valid (English or Sinhala only)
    String currentSelectedLanguage = dashController.selectedLanguage;
    if (currentSelectedLanguage != 'English' && currentSelectedLanguage != 'Sinhala') {
      currentSelectedLanguage = 'English';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dashController.setLanguage('English');
      });
    }



    // Sidebar items structure categorized like FoodKing
    final categories = [
      _SidebarCategory(
        null,
        [
          _SidebarItem(Icons.dashboard_outlined, 'Dashboard', 0),
          _SidebarItem(Icons.restaurant_outlined, 'Items', 8),
          _SidebarItem(Icons.table_restaurant_outlined, 'Dining Tables', 2),
        ],
      ),
      _SidebarCategory(
        'POS & ORDERS',
        [
          _SidebarItem(Icons.point_of_sale_outlined, 'POS System', 1),
          _SidebarItem(Icons.history_toggle_off_outlined, 'Pre Orders', 25),
          _SidebarItem(Icons.receipt_long_outlined, 'POS Orders', 9),
          _SidebarItem(Icons.queue_play_next_outlined, 'Queue Screen', 4),
          _SidebarItem(Icons.kitchen_outlined, 'K.D.S (Kitchen)', 3),
        ],
      ),
      _SidebarCategory(
        'PROMO',
        [
          _SidebarItem(Icons.local_offer_outlined, 'Offers', 10),
        ],
      ),
      _SidebarCategory(
        'USERS',
        [
          _SidebarItem(Icons.admin_panel_settings_outlined, 'Administrators', 11),
          _SidebarItem(Icons.local_shipping_outlined, 'Delivery Boys', 12),
          _SidebarItem(Icons.people_outline, 'Customers', 13),
          _SidebarItem(Icons.badge_outlined, 'Employees', 14),
          _SidebarItem(Icons.room_service_outlined, 'Waiters', 15),
          _SidebarItem(Icons.soup_kitchen_outlined, 'Chefs', 16),
        ],
      ),
      _SidebarCategory(
        'REPORTS & SHIFTS',
        [
          _SidebarItem(Icons.bar_chart_outlined, 'Sales Report', 17),
          _SidebarItem(Icons.inventory_2_outlined, 'Items Report', 18),
          _SidebarItem(Icons.account_balance_wallet_outlined, 'Credit Balance Report', 19),
          _SidebarItem(Icons.monetization_on_outlined, 'Shifts & Cash', 5),
          _SidebarItem(Icons.analytics_outlined, 'Reports & Logs', 6),
        ],
      ),
      _SidebarCategory(
        'STOCKS',
        [
          _SidebarItem(Icons.shopping_basket_outlined, 'Raw Materials', 20),
          _SidebarItem(Icons.inventory_2_outlined, 'POS Stock', 21),
        ],
      ),
      _SidebarCategory(
        'SYSTEM',
        [
          _SidebarItem(Icons.settings_outlined, 'Settings', 7),
        ],
      ),
    ];

    Widget buildSidebarContent() {
      final appSettings = context.watch<AppSettingsController>();
      final companyName = appSettings.companyName;
      // Split into first-half / second-half for two-tone styling
      final half = companyName.length > 4 ? companyName.length ~/ 2 : companyName.length;
      final part1 = companyName.substring(0, half);
      final part2 = companyName.substring(half);

      return Container(
        color: AppTheme.cardLight,
        child: Column(
          children: [
            // Logo area - beautifully combines logo image / favicon and company name
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // Logo / Icon
                  if (appSettings.logoBase64 != null && appSettings.logoBase64!.isNotEmpty)
                    Container(
                      width: 42,
                      height: 42,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Base64ImageWidget(
                        base64Str: appSettings.logoBase64,
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (appSettings.faviconBase64 != null && appSettings.faviconBase64!.isNotEmpty)
                    Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Base64ImageWidget(
                        base64Str: appSettings.faviconBase64,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.restaurant_menu, color: AppTheme.primary, size: 20),
                    ),
                  // Company Name Text
                  Expanded(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        text: part1,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                        children: [
                          TextSpan(
                            text: part2,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFFB300), // Amber yellow
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Navigation Links grouped by categories
            (() {
              final visibleCategories = <_SidebarCategory>[];
              for (final cat in categories) {
                final filteredItems = cat.items.where((item) {
                  return APIService.instance.canViewPage(item.title);
                }).toList();
                if (filteredItems.isNotEmpty) {
                  visibleCategories.add(_SidebarCategory(cat.title, filteredItems));
                }
              }

              return Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: visibleCategories.length,
                  itemBuilder: (context, catIdx) {
                    final cat = visibleCategories[catIdx];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cat.title != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
                          child: Text(
                            cat.title!.tr(context),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF94A3B8), // Slate header text
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                      ...cat.items.map((item) {
                        final isSelected = _selectedIndex == item.screenIndex;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          child: ListTile(
                            selected: isSelected,
                            selectedTileColor: const Color(0xFFFFF0F5), // Light pink tile bg
                            hoverColor: Colors.pink.withOpacity(0.02),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            leading: Icon(
                              item.icon,
                              color: isSelected ? AppTheme.primary : Color(0xFF7A869A),
                              size: 18,
                            ),
                            title: Text(
                              item.title.tr(context),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppTheme.primary : Color(0xFF7A869A),
                              ),
                            ),
                            onTap: () {
                              if (posController.activeShift == null && item.screenIndex != 5) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please start your daily shift first by setting the opening cash drawer balance.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _selectedIndex = item.screenIndex;
                                if (item.screenIndex == 1) {
                                  _isSidebarCollapsed = true;
                                } else {
                                  _isSidebarCollapsed = false;
                                }
                              });
                              if (!isDesktop) {
                                Navigator.pop(context);
                              }
                            },
                            dense: true,
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            );
          })(),

            // User Profile Section & Logout
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                        radius: 18,
                        child: APIService.instance.currentUser?.imageBase64 != null && APIService.instance.currentUser!.imageBase64!.isNotEmpty
                            ? ClipOval(
                                child: Base64ImageWidget(
                                  base64Str: APIService.instance.currentUser!.imageBase64,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Text(
                                (APIService.instance.currentUser?.name ?? 'C')[0].toUpperCase(),
                                style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              APIService.instance.currentUser?.name ?? 'Guest User',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightPrimary,
                              ),
                            ),
                            Text(
                              (APIService.instance.currentUser?.role ?? 'cashier').toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      if (posController.activeShift != null) {
                        _showCloseShiftDialog(context, posController);
                      } else {
                        await APIService.instance.logout();
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.logout, size: 14),
                    label: Text('Logout'.tr(context)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size.fromHeight(36),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isQueueExtended = _selectedIndex == 4 && appSettings.extendQueueScreen;
    final isPosExtended = _selectedIndex == 1 && appSettings.extendPosScreen;
    final isFullScreenMode = isQueueExtended || isPosExtended;

    final borderStyleColor = AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final dividerColor = AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    final Widget scaffold = Scaffold(
      key: _scaffoldKey,
      drawer: (!isDesktop && !isFullScreenMode) ? Drawer(child: buildSidebarContent()) : null,
      body: Row(
        children: [
          // Sidebar on Desktop
          if (isDesktop && !_isSidebarCollapsed && !isFullScreenMode)
            SizedBox(
              width: 240,
              child: buildSidebarContent(),
            ),
          if (isDesktop && !_isSidebarCollapsed && !isFullScreenMode)
            VerticalDivider(width: 1, color: borderStyleColor),

          // Main Body Area
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                if (!isFullScreenMode)
                  Container(
                    height: 70,
                    color: AppTheme.cardLight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      if (!isDesktop) ...[
                        IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        const SizedBox(width: 8),
                      ],

                      if (isDesktop && _isSidebarCollapsed) ...[
                        // Collapsed sidebar: show logo/icon + company name
                        Consumer<AppSettingsController>(builder: (_, appS, __) {
                          final cn = appS.companyName;
                          final h = cn.length > 4 ? cn.length ~/ 2 : cn.length;
                          return Row(children: [
                            if (appS.faviconBase64 != null && appS.faviconBase64!.isNotEmpty)
                              Container(
                                width: 28, height: 28,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Base64ImageWidget(base64Str: appS.faviconBase64, fit: BoxFit.cover),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(5),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.restaurant_menu, color: AppTheme.primary, size: 18),
                              ),
                            RichText(text: TextSpan(
                              text: cn.substring(0, h),
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              children: [TextSpan(
                                text: cn.substring(h),
                                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFFFB300)),
                              )],
                            )),
                          ]);
                        }),
                        const SizedBox(width: 24),
                      ],

                      Text(
                        _titles[_selectedIndex].tr(context),
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textLightPrimary,
                        ),
                      ),

                      const Spacer(),

                      // Sync indicator
                      GestureDetector(
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Triggering sync...')),
                          );
                          await posController.reloadEnvironment();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  posController.isOnline
                                      ? 'System Online. Data synchronized successfully.'
                                      : 'System Offline. Offline data remains cached.'
                                ),
                                backgroundColor: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: posController.isOnline
                                ? AppTheme.accent.withOpacity(0.08)
                                : AppTheme.warning.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                posController.isOnline ? 'Online' : 'Offline',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.sync,
                                size: 12,
                                color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Shift Badge (simplified)
                      if (isDesktop && posController.activeShift != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.secondary, width: 1),
                          ),
                          child: Text(
                            'SHIFT OPEN',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Branch selection dropdown
                      if (isDesktop) ...[
                        Row(
                          children: [
                            Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 6),
                            isAdmin
                                ? DropdownButton<String>(
                                    value: currentSelectedBranch,
                                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                                    underline: const SizedBox(),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textLightPrimary,
                                    ),
                                    items: branchNames.map<DropdownMenuItem<String>>((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(value, style: TextStyle(color: AppTheme.textLightPrimary)),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        dashController.setBranch(newValue);
                                      }
                                    },
                                  )
                                : Text(
                                    currentSelectedBranch,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                          ],
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Language selection dropdown
                      if (isDesktop) ...[
                        Row(
                          children: [
                            const Icon(Icons.language_outlined, color: Colors.blue, size: 18),
                            const SizedBox(width: 6),
                            DropdownButton<String>(
                              value: currentSelectedLanguage,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                              underline: const SizedBox(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightPrimary,
                              ),
                              items: <String>['English', 'Sinhala']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  dashController.setLanguage(newValue);
                                  try {
                                    Provider.of<POSController>(context, listen: false).setVoiceLanguage(newValue);
                                  } catch (_) {}
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Pink menu toggle button on desktop
                      if (isDesktop) ...[
                        IconButton(
                          icon: Icon(
                            _isSidebarCollapsed ? Icons.menu : Icons.menu_open,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF0F5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.all(10),
                          ),
                          onPressed: () {
                            setState(() {
                              _isSidebarCollapsed = !_isSidebarCollapsed;
                            });
                          },
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Low Stock Raw Materials Warning Icon Badge with popup
                      if (posController.lowStockIngredientsCount > 0) ...[
                        PopupMenuButton<dynamic>(
                          offset: const Offset(0, 50),
                          icon: Badge(
                            label: Text(
                              '${posController.lowStockIngredientsCount}',
                              style: const TextStyle(fontSize: 8, color: Colors.white),
                            ),
                            isLabelVisible: true,
                            backgroundColor: Colors.amber.shade700,
                            child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 20),
                          ),
                          tooltip: 'Low Stock Ingredients',
                          itemBuilder: (BuildContext context) {
                            final List<IngredientModel> lowStockIngs = posController.ingredients.where((i) => i.stockQty <= i.minStockLevel).toList();
                            return [
                              PopupMenuItem<dynamic>(
                                enabled: false,
                                child: Container(
                                  width: 320,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Low Stock Raw Materials'.tr(context),
                                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 8, color: Color(0xFFE2E8F0)),
                                    ],
                                  ),
                                ),
                              ),
                              ...lowStockIngs.map((i) {
                                return PopupMenuItem<dynamic>(
                                  enabled: false,
                                  child: Container(
                                    width: 320,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            i.name,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${i.stockQty.toStringAsFixed(1)} ${i.unit}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ];
                          },
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Notification Bell with dynamic badge and dropdown menu
                      PopupMenuButton<dynamic>(
                        offset: const Offset(0, 50),
                        icon: Badge(
                          label: Text(
                            '${posController.unreadNotificationCount}',
                            style: const TextStyle(fontSize: 8, color: Colors.white),
                          ),
                          isLabelVisible: posController.unreadNotificationCount > 0,
                          backgroundColor: Colors.red,
                          child: const Icon(Icons.notifications_none_outlined, color: Color(0xFF64748B), size: 20),
                        ),
                        tooltip: 'Notifications',
                        itemBuilder: (BuildContext context) {
                          final list = posController.notifications;
                          return [
                            PopupMenuItem<dynamic>(
                              enabled: false,
                              child: Container(
                                width: 320,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Notifications'.tr(context),
                                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                        ),
                                        if (posController.unreadNotificationCount > 0)
                                          TextButton(
                                            onPressed: () async {
                                              await posController.readAllNotifications();
                                              Navigator.pop(context);
                                            },
                                            child: Text('Mark all as read'.tr(context), style: const TextStyle(fontSize: 11)),
                                          ),
                                      ],
                                    ),
                                    const Divider(height: 8, color: Color(0xFFE2E8F0)),
                                  ],
                                ),
                              ),
                            ),
                            if (list.isEmpty)
                              PopupMenuItem<dynamic>(
                                enabled: false,
                                child: Container(
                                  width: 320,
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'No notifications yet'.tr(context),
                                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                    ),
                                  ),
                                ),
                              )
                            else
                              ...list.map((n) {
                                final bool isRead = n['is_read'] == 1 || n['is_read'] == true;
                                return PopupMenuItem<dynamic>(
                                  onTap: () async {
                                    if (!isRead) {
                                      await posController.readNotification(n['id']);
                                    }
                                  },
                                  child: Container(
                                    width: 320,
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                n['title'] ?? 'Alert',
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isRead ? AppTheme.textLightSecondary : AppTheme.primary,
                                                ),
                                              ),
                                            ),
                                            if (!isRead)
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          n['message'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: isRead ? AppTheme.textLightSecondary : AppTheme.textLightPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.tryParse(n['created_at'])?.toLocal() ?? DateTime.now()),
                                          style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textLightSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                          ];
                        },
                      ),

                      const SizedBox(width: 8),

                      // Profile Display (Clickable Dropdown Popup)
                      PopupMenuButton<int>(
                        offset: const Offset(0, 50),
                        tooltip: 'User Profile Menu',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.teal.shade100,
                                child: APIService.instance.currentUser?.imageBase64 != null && APIService.instance.currentUser!.imageBase64!.isNotEmpty
                                    ? ClipOval(
                                        child: Base64ImageWidget(
                                          base64Str: APIService.instance.currentUser!.imageBase64,
                                          width: 32,
                                          height: 32,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(Icons.face, color: Colors.teal, size: 20),
                              ),
                              if (isDesktop) ...[
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Hello'.tr(context),
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        color: AppTheme.textLightSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      APIService.instance.currentUser?.name ?? 'John Doe',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppTheme.textLightPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        onSelected: (val) async {
                          if (val == 1) {
                            setState(() {
                              _selectedIndex = 22; // Edit Profile
                            });
                          } else if (val == 2) {
                            setState(() {
                              _selectedIndex = 23; // Change Password
                            });
                          } else if (val == 3) {
                            await APIService.instance.logout();
                            if (mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const LoginScreen()),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) {
                          final user = APIService.instance.currentUser;
                          final userRole = (user?.role ?? 'cashier').toUpperCase();
                          return [
                            PopupMenuItem<int>(
                              enabled: false,
                              child: Container(
                                width: 220,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Colors.teal.shade50,
                                      child: (user?.imageBase64 ?? '').isNotEmpty
                                          ? ClipOval(
                                              child: Base64ImageWidget(
                                                base64Str: user?.imageBase64,
                                                width: 72,
                                                height: 72,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : const Icon(Icons.face, color: Colors.teal, size: 40),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      user?.name ?? 'John Doe',
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      user?.email ?? 'admin@example.com',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                    ),
                                    if ((user?.phone ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        user?.phone ?? '',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        userRole,
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const PopupMenuDivider(),
                             PopupMenuItem<int>(
                              value: 1,
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 16, color: AppTheme.textLightSecondary),
                                  const SizedBox(width: 10),
                                  Text('Edit Profile', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                                ],
                              ),
                            ),
                            PopupMenuItem<int>(
                              value: 2,
                              child: Row(
                                children: [
                                  Icon(Icons.key_outlined, size: 16, color: AppTheme.textLightSecondary),
                                  const SizedBox(width: 10),
                                  Text('Change Password', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                                ],
                              ),
                            ),
                            PopupMenuItem<int>(
                              value: 3,
                              child: Row(
                                children: [
                                  const Icon(Icons.logout_outlined, size: 16, color: AppTheme.danger),
                                  const SizedBox(width: 10),
                                  Text('Logout', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),

                // Screen Content - always keep the screen widget in the tree
                // so its State is never disposed during background reloads.
                Expanded(
                  child: Stack(
                    children: [
                      _getScreen(_selectedIndex),
                      if (posController.isLoading)
                        Container(
                          color: Colors.black.withOpacity(0.15),
                          child: Center(
                            child: CircularProgressIndicator(color: AppTheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (!_hasShownLowStockWarning && posController.lowStockIngredientsCount > 0)
          _buildLowStockWarningOverlay(posController),
      ],
    );
  }

  Widget _buildLowStockWarningOverlay(POSController posController) {
    final lowStockIngs = posController.ingredients.where((i) => i.stockQty <= i.minStockLevel).toList();
    final names = lowStockIngs.map((i) => '${i.name} (${i.stockQty.toStringAsFixed(1)} ${i.unit})').join(', ');
    
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Blurred background
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          ),
          
          // Warning Card
          Center(
            child: Container(
              width: 480,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB), // Soft yellow/amber background
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.shade300, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber.shade800,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Header
                  Text(
                    'Depleted / Negative Stock Warning!'.tr(context),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Message
                  Text(
                    'The following ingredients are out of stock or negative: $names. Please update stock level immediately to prevent recipe deduction errors.'.tr(context),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.amber.shade900.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _selectedIndex = 20; // Navigate to Raw Materials
                              _hasShownLowStockWarning = true;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.amber.shade700),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Update Stock'.tr(context),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _hasShownLowStockWarning = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                          child: Text(
                            'Dismiss'.tr(context),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String title;
  final int screenIndex;
  _SidebarItem(this.icon, this.title, this.screenIndex);
}

class _SidebarCategory {
  final String? title;
  final List<_SidebarItem> items;
  _SidebarCategory(this.title, this.items);
}
