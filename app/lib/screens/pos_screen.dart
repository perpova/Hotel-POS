import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';
import '../controllers/app_settings_controller.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({Key? key}) : super(key: key);

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _customerBirthdayController = TextEditingController();
  final TextEditingController _customerLimitController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _barcodeInputController = TextEditingController();
  final TextEditingController _tokenNoController = TextEditingController();
  final TextEditingController _customerSearchController = TextEditingController();
  bool _isCustomerDropdownOpen = false;
  String _customerSearchQuery = '';

  String _discountType = 'percent';

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerBirthdayController.dispose();
    _customerLimitController.dispose();
    _discountController.dispose();
    _barcodeInputController.dispose();
    _tokenNoController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  void _applyDiscount(POSController controller) {
    final val = double.tryParse(_discountController.text) ?? 0.0;
    if (_discountType == 'percent') {
      final discountAmt = controller.cartSubtotal * (val / 100.0);
      controller.setDiscount(discountAmt);
    } else {
      controller.setDiscount(val);
    }
  }

  IconData _getCategoryIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('burger') || lower.contains('whopper')) return Icons.lunch_dining;
    if (lower.contains('appetizer')) return Icons.cookie_outlined;
    if (lower.contains('sandwich')) return Icons.breakfast_dining;
    if (lower.contains('chicken')) return Icons.kebab_dining;
    if (lower.contains('beef')) return Icons.restaurant;
    if (lower.contains('seafood') || lower.contains('fish')) return Icons.set_meal;
    if (lower.contains('salad')) return Icons.eco_outlined;
    if (lower.contains('soup')) return Icons.soup_kitchen;
    if (lower.contains('beverage') || lower.contains('drink')) return Icons.local_cafe;
    if (lower.contains('side')) return Icons.cookie_outlined;
    return Icons.fastfood_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final appSettings = Provider.of<AppSettingsController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: isDesktop
          ? Row(
              children: appSettings.cartOnLeft
                  ? [
                      // Left: Bill / Checkout Details (28.6% width)
                      Expanded(
                        flex: 2,
                        child: _buildBillingArea(controller),
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                      // Right: Products Grid (71.4% width)
                      Expanded(
                        flex: 5,
                        child: _buildProductsArea(controller),
                      ),
                    ]
                  : [
                      // Left: Products Grid (71.4% width)
                      Expanded(
                        flex: 5,
                        child: _buildProductsArea(controller),
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                      // Right: Bill / Checkout Details (28.6% width)
                      Expanded(
                        flex: 2,
                        child: _buildBillingArea(controller),
                      ),
                    ],
            )
          : Column(
              children: [
                Expanded(child: _buildProductsArea(controller)),
                const Divider(height: 1),
                SizedBox(
                  height: size.height * 0.55,
                  child: _buildBillingArea(controller),
                ),
              ],
            ),
    );
  }

  // ----------------------------------------------------
  // LEFT: PRODUCTS AREA
  // ----------------------------------------------------
  Widget _buildProductsArea(POSController controller) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // FoodKing Custom Search and Barcode Scanner Row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search by Menu Item...',
                            hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (val) => controller.setSearchWord(val),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.search, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: IconButton(
                  icon: Icon(Icons.barcode_reader, color: AppTheme.primary, size: 20),
                  tooltip: 'Scan acknowledgement barcode',
                  padding: EdgeInsets.zero,
                  onPressed: () => _showBarcodeScanDialog(controller),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal Categories Slider with FoodKing Card style
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryTab(null, 'All Items', controller),
                ...controller.categories.map((cat) => _buildCategoryTab(cat, cat.name, controller)).toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Products Grid
          Expanded(
            child: controller.filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.fastfood_outlined, size: 64, color: AppTheme.textLightSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'No items found.',
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textLightSecondary),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 155,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: controller.filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = controller.filteredProducts[index];
                      return _buildProductCard(product, controller);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(CategoryModel? cat, String title, POSController controller) {
    final id = cat?.id;
    final isSelected = controller.activeCategoryId == id;
    final icon = _getCategoryIcon(title);
    final base64Str = cat?.imageBase64;

    return GestureDetector(
      onTap: () => controller.filterCategory(id),
      child: Container(
        width: 95,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF0F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            base64Str != null && base64Str.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Base64ImageWidget(
                      base64Str: base64Str,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      fallback: Icon(
                        icon,
                        color: isSelected ? AppTheme.primary : Color(0xFF64748B),
                        size: 24,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: isSelected ? AppTheme.primary : Color(0xFF64748B),
                    size: 24,
                  ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product, POSController controller) {
    final isLowStock = product.trackStock && (product.stockQty <= product.minStockLevel);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: Color(0xFFF1F5F9),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: (!product.trackStock || product.stockQty > 0)
            ? () {
                if (product.hasSizes || product.hasExtras || product.hasAddons) {
                  _showProductOptionsModal(product, controller);
                } else {
                  controller.addToCart(product, quantity: 1);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${product.name} successfully added to cart'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.primary.withOpacity(0.05),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Base64ImageWidget(
                          base64Str: product.imageBase64,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          fallback: Center(
                            child: Icon(
                              product.isShortEat ? Icons.bakery_dining_outlined : Icons.restaurant,
                              color: AppTheme.primary.withOpacity(0.6),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isLowStock && product.stockQty > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Low Stock: ${product.stockQty}',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    if (product.trackStock && product.stockQty <= 0)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'OUT OF STOCK',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
              ),
              if (product.sinhalaName != null) ...[
                const SizedBox(height: 1),
                Text(
                  product.sinhalaName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textLightSecondary, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) {
                            final currentPrice = controller.getProductActivePrice(product);
                            final isHappyHour = currentPrice < product.price;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LKR ${currentPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                ),
                                if (isHappyHour)
                                  Text(
                                    'LKR ${product.price.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: AppTheme.textLightSecondary,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: Colors.red,
                                      decorationThickness: 1.5,
                                    ),
                                  ),
                              ],
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                   InkWell(
                    onTap: product.stockQty > 0
                        ? () {
                            if (product.hasSizes || product.hasExtras || product.hasAddons) {
                              _showProductOptionsModal(product, controller);
                            } else {
                              final activePrice = controller.getProductActivePrice(product);
                              controller.addToCart(product, quantity: 1, customPrice: activePrice);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${product.name} successfully added to cart'),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_bag_outlined, color: AppTheme.primary, size: 10),
                          const SizedBox(width: 3),
                          Text(
                            'Add',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // RIGHT: BILLING AREA
  // ----------------------------------------------------
  Widget _buildBillingArea(POSController controller) {
    // Keep UI discount inputs in sync with controller state
    if (controller.cart.isEmpty) {
      if (_discountController.text.isNotEmpty) {
        _discountController.clear();
      }
    } else {
      if (controller.rawDiscountValue > 0 && (_discountController.text.isEmpty || _discountController.text == '0')) {
        _discountController.text = controller.rawDiscountValue.toStringAsFixed(0);
        _discountType = controller.discountType;
      }
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer Picker Header styled like FoodKing
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isCustomerDropdownOpen = !_isCustomerDropdownOpen;
                          if (_isCustomerDropdownOpen) {
                            _customerSearchQuery = '';
                            _customerSearchController.clear();
                          }
                        });
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                controller.selectedCustomer != null
                                    ? '${controller.selectedCustomer!.name} (${controller.selectedCustomer!.phone})'
                                    : 'Select Customer',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (_isCustomerDropdownOpen) ...[
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: TextField(
                                  controller: _customerSearchController,
                                  autofocus: true,
                                  style: GoogleFonts.inter(fontSize: 11),
                                  onChanged: (val) {
                                    setState(() {
                                      _customerSearchQuery = val;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search customer name or phone...',
                                    hintStyle: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                                    prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF94A3B8)),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            Flexible(
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  ...controller.customers
                                      .where((c) {
                                        if (_customerSearchQuery.isEmpty) return true;
                                        final term = _customerSearchQuery.toLowerCase();
                                        return c.name.toLowerCase().contains(term) ||
                                            c.phone.contains(term);
                                      })
                                      .map((c) => ListTile(
                                            dense: true,
                                            visualDensity: VisualDensity.compact,
                                            title: Text(
                                              '${c.name} (${c.phone})',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: controller.selectedCustomer?.id == c.id ? FontWeight.bold : FontWeight.normal,
                                                color: controller.selectedCustomer?.id == c.id ? AppTheme.primary : const Color(0xFF1E293B),
                                              ),
                                            ),
                                            onTap: () {
                                              controller.selectCustomer(c);
                                              setState(() {
                                                _isCustomerDropdownOpen = false;
                                              });
                                            },
                                          )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white, size: 14),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _showAddCustomerDialog(controller),
                ),
              ),
            ],
          ),
          // Select Order Type Radio Cards
          _buildOrderTypeSelectorCard(controller),
          const SizedBox(height: 12),

          // Dine-in Table selectors / Delivery platform selectors
          if (controller.orderType == 'dine_in') ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<DiningTableModel>(
                        value: controller.selectedTable,
                        hint: Align(
                          alignment: Alignment.center,
                          child: Text('Select Table', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                        ),
                        alignment: Alignment.center,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        iconSize: 18,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        items: [
                          ...controller.diningTables.map((t) => DropdownMenuItem(
                                value: t,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text('${t.tableNumber} (${t.status.toUpperCase()})', style: GoogleFonts.inter(fontSize: 13)),
                                ),
                              )),
                        ],
                        onChanged: (t) => controller.selectTable(t),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: controller.waiters.any((w) => w.name == controller.stewardName) ? controller.stewardName : null,
                        hint: Align(
                          alignment: Alignment.center,
                          child: Text('Select Waiter', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                        ),
                        alignment: Alignment.center,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        iconSize: 18,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        items: [
                          ...controller.waiters.map((w) => DropdownMenuItem(
                                value: w.name,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text(w.name, style: GoogleFonts.inter(fontSize: 13)),
                                ),
                              )),
                        ],
                        onChanged: (val) => controller.setStewardName(val),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (controller.orderType == 'delivery') ...[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButtonFormField<String>(
                  value: controller.deliveryPlatform,
                  hint: Align(
                    alignment: Alignment.center,
                    child: Text('Delivery Platform', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                  ),
                  alignment: Alignment.center,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  iconSize: 18,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  items: const [
                    DropdownMenuItem(value: 'uber_eats', child: Align(alignment: Alignment.center, child: Text('Uber Eats', style: TextStyle(fontSize: 13)))),
                    DropdownMenuItem(value: 'pickme', child: Align(alignment: Alignment.center, child: Text('PickMe Food', style: TextStyle(fontSize: 13)))),
                    DropdownMenuItem(value: 'phone', child: Align(alignment: Alignment.center, child: Text('Phone Order', style: TextStyle(fontSize: 13)))),
                    DropdownMenuItem(value: 'direct', child: Align(alignment: Alignment.center, child: Text('Direct Delivery', style: TextStyle(fontSize: 13)))),
                  ],
                  onChanged: (platform) => controller.setDeliveryPlatform(platform),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Cart Column Headers
          Container(
            color: const Color(0xFFFFF0F5),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text('Item', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Text('Qty', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Price', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                  ),
                ),
              ],
            ),
          ),

          // Bill Items Cart List
          Expanded(
            child: controller.cart.isEmpty
                ? Center(
                    child: Text(
                      'Cart is empty. Select products on the left.',
                      style: GoogleFonts.inter(color: AppTheme.textLightSecondary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: controller.cart.length,
                    itemBuilder: (context, index) {
                      final item = controller.cart[index];
                      return _buildCartRow(item, index, controller);
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),

          // Discount selector row (no Apply button needed)
          Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _discountType = _discountType == 'percent' ? 'fixed' : 'percent';
                    final parsed = double.tryParse(_discountController.text) ?? 0.0;
                    controller.updateDiscount(parsed, _discountType);
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      _discountType == 'percent' ? '%' : 'LKR',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _discountController,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Add Discount',
                      hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final parsed = double.tryParse(val) ?? 0.0;
                      controller.updateDiscount(parsed, _discountType);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Totals Section
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sub Total:', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                  Text('LKR ${controller.cartSubtotal.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Discount:', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                  Text('LKR ${controller.discount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total:', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  Text(
                    'LKR ${controller.cartTotal.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Checkout Action Buttons Flow
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: controller.cart.isEmpty ? null : () {
                        controller.clearCart();
                        _tokenNoController.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444), // Red
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: controller.cart.isEmpty ? null : () => _showOrderPaymentDialog(controller),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981), // Green
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Order', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeSelectorCard(POSController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Order Type',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildFoodKingTypeButton('dine_in', 'Dine-In', controller)),
            const SizedBox(width: 8),
            Expanded(child: _buildFoodKingTypeButton('takeaway', 'Takeaway', controller)),
            const SizedBox(width: 8),
            Expanded(child: _buildFoodKingTypeButton('delivery', 'Delivery', controller)),
          ],
        ),
      ],
    );
  }

  Widget _buildFoodKingTypeButton(String type, String label, POSController controller) {
    final isSel = controller.orderType == type;
    return GestureDetector(
      onTap: () => controller.setOrderType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFFFF0F5) : Colors.white,
          border: Border.all(
            color: isSel ? AppTheme.primary : const Color(0xFFE2E8F0),
            width: isSel ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSel
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSel ? AppTheme.primary : const Color(0xFFCBD5E1),
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                  color: isSel ? AppTheme.primary : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartRow(OrderItemModel item, int index, POSController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // 1. Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 16),
            onPressed: () => controller.updateCartQuantity(index, 0),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          
          // 2. Item Name & Details
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                ),
                if (item.notes != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    item.notes!,
                    style: GoogleFonts.inter(fontSize: 8, color: AppTheme.primary, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          
          // 3. Quantity Outline Selectors
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () => controller.updateCartQuantity(index, item.quantity - 1),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.remove, size: 14, color: Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.quantity}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => controller.updateCartQuantity(index, item.quantity + 1),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.add, size: 14, color: Color(0xFF15803D)),
                  ),
                ),
              ],
            ),
          ),
          
          // 4. Line price total
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'LKR ${(item.price * item.quantity).toStringAsFixed(0)}',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // FLOW IMPLEMENTATIONS (KOT, ACK, MOCK TICKET PRINT)
  // ----------------------------------------------------
  void _handlePrintKOTFlow(POSController controller) async {
    try {
      await controller.placeOrder(
        printKOT: true,
        printAck: false,
        status: 'preparing',
        paymentStatus: 'unpaid',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KOT Ticket sent to kitchen. Voice notification played to chef.')),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  void _handlePrintAcknowledgementFlow(POSController controller) async {
    try {
      await controller.placeOrder(
        printKOT: false,
        printAck: true,
        status: 'pending',
        paymentStatus: 'unpaid',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acknowledgement bill printed with Barcode. Dining Table status set to BILLING.')),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  // ----------------------------------------------------
  // DIALOG FLOWS
  // ----------------------------------------------------
  void _showProductOptionsModal(ProductModel product, POSController controller) {
    final List<Map<String, dynamic>> sizes = product.hasSizes && product.sizes.isNotEmpty
        ? product.sizes.map((s) => {'name': s.name, 'price': s.price}).toList()
        : [
            {'name': 'Regular', 'price': controller.getProductActivePrice(product)},
          ];
          
    final List<Map<String, dynamic>> extras = product.hasExtras && product.extras.isNotEmpty
        ? product.extras.map((e) => {'name': e.name, 'price': e.price}).toList()
        : [];

    final List<Map<String, dynamic>> addons = [];
    if (product.hasAddons && product.addons.isNotEmpty) {
      for (var addonId in product.addons) {
        final addonProd = controller.products.firstWhere(
          (p) => p.id == addonId,
          orElse: () => ProductModel(id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false),
        );
        if (addonProd.id != 0) {
          addons.add({
            'name': addonProd.name,
            'price': controller.getProductActivePrice(addonProd),
            'image': Icons.local_drink_outlined,
            'product': addonProd,
          });
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        String selectedSize = sizes.first['name'];
        double selectedSizePrice = sizes.first['price'];
        final selectedExtrasQty = <String, int>{};
        for (var ex in extras) {
          selectedExtrasQty[ex['name']] = 0;
        }
        final selectedAddons = <String, Map<String, dynamic>>{};
        for (var add in addons) {
          selectedAddons[add['name']] = {
            'qty': 0,
            'price': add['price'],
          };
        }
        
        int itemQty = 1;
        final TextEditingController instructionController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setModalState) {
            double basePrice = product.hasSizes ? selectedSizePrice : controller.getProductActivePrice(product);
            double extrasSum = 0.0;
            selectedExtrasQty.forEach((name, qty) {
              final exObj = extras.firstWhere((e) => e['name'] == name);
              extrasSum += exObj['price'] * qty;
            });
            double addonsSum = 0.0;
            selectedAddons.forEach((name, data) {
              addonsSum += data['price'] * data['qty'];
            });
            
            double singleItemPrice = basePrice + extrasSum;
            double totalPrice = (singleItemPrice * itemQty) + addonsSum;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 680,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row with product info
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product Image
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: AppTheme.primary.withOpacity(0.05),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Base64ImageWidget(
                                base64Str: product.imageBase64,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                fallback: Center(
                                  child: Icon(
                                    product.isShortEat ? Icons.bakery_dining_outlined : Icons.restaurant,
                                    color: AppTheme.primary.withOpacity(0.6),
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  product.description ?? 'A delicious menu item prepared with fresh ingredients.',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'LKR ${product.activePrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                ),
                              ],
                            ),
                          ),
                          // Close button
                          IconButton(
                            icon: const Icon(Icons.close_outlined, color: Color(0xFFEF4444)),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFFEE2E2),
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Options Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quantity selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Quantity:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 20),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                      onPressed: () {
                                        if (itemQty > 1) {
                                          setModalState(() => itemQty--);
                                        }
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      child: Text('$itemQty', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 20),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                      onPressed: () {
                                        setModalState(() => itemQty++);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                    if (product.hasSizes) ...[
                              // Sizes Options
                              Text('Size', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: sizes.map((sz) {
                                  final isSel = selectedSize == sz['name'];
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedSize = sz['name'];
                                          selectedSizePrice = sz['price'];
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSel ? const Color(0xFFFFF0F5) : Colors.white,
                                          border: Border.all(
                                            color: isSel ? AppTheme.primary : Color(0xFFE2E8F0),
                                            width: isSel ? 1.5 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSel ? AppTheme.primary : Color(0xFFCBD5E1),
                                                  width: 2,
                                                ),
                                              ),
                                              child: isSel
                                                  ? Center(
                                                      child: Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: AppTheme.primary,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                "${sz['name']} (LKR ${sz['price'].toStringAsFixed(0)})",
                                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 20),
                            ],

                            if (product.hasExtras) ...[
                              // Extras Options
                              Text('Extras', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              Column(
                                children: extras.map((ex) {
                                  final name = ex['name'];
                                  final qty = selectedExtrasQty[name] ?? 0;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                      borderRadius: BorderRadius.circular(8),
                                      color: qty > 0 ? const Color(0xFFFFF0F5) : Colors.white,
                                    ),
                                    child: Row(
                                      children: [
                                        // Left: Extra Name
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: const Color(0xFF1E293B),
                                              fontWeight: qty > 0 ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        // Middle: Price
                                        Text(
                                          '+LKR ${ex['price'].toStringAsFixed(0)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: qty > 0 ? AppTheme.primary : const Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Right: Counter (- qty +)
                                        Row(
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                if (qty > 0) {
                                                  setModalState(() {
                                                    selectedExtrasQty[name] = qty - 1;
                                                  });
                                                }
                                              },
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Icon(Icons.remove, size: 14, color: Color(0xFF475569)),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text('$qty', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                                            const SizedBox(width: 10),
                                            InkWell(
                                              onTap: () {
                                                setModalState(() {
                                                  selectedExtrasQty[name] = qty + 1;
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Icon(Icons.add, size: 14, color: Color(0xFF475569)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 20),
                            ],

                            if (product.hasAddons) ...[
                              // Addons Options (Horizontal Cards)
                              Text('Addons', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 100,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: addons.map((add) {
                                    final name = add['name'];
                                    final qty = selectedAddons[name]?['qty'] ?? 0;
                                    return Container(
                                      width: 200,
                                      margin: const EdgeInsets.only(right: 12),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(add['image'] as IconData, color: AppTheme.primary, size: 28),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text('LKR ${add['price'].toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                children: [
                                                   InkWell(
                                                     onTap: () {
                                                       if (qty > 0) {
                                                         setModalState(() {
                                                           selectedAddons[name]!['qty'] = qty - 1;
                                                         });
                                                       }
                                                     },
                                                     borderRadius: BorderRadius.circular(6),
                                                     child: Container(
                                                       width: 32,
                                                       height: 32,
                                                       decoration: BoxDecoration(
                                                         color: const Color(0xFFF1F5F9),
                                                         borderRadius: BorderRadius.circular(6),
                                                       ),
                                                       child: const Icon(Icons.remove, size: 14, color: Color(0xFF475569)),
                                                     ),
                                                   ),
                                                   const SizedBox(width: 8),
                                                   Text('$qty', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                                                   const SizedBox(width: 8),
                                                   InkWell(
                                                     onTap: () {
                                                       setModalState(() {
                                                         selectedAddons[name]!['qty'] = qty + 1;
                                                       });
                                                     },
                                                     borderRadius: BorderRadius.circular(6),
                                                     child: Container(
                                                       width: 32,
                                                       height: 32,
                                                       decoration: BoxDecoration(
                                                         color: const Color(0xFFF1F5F9),
                                                         borderRadius: BorderRadius.circular(6),
                                                       ),
                                                       child: const Icon(Icons.add, size: 14, color: Color(0xFF475569)),
                                                     ),
                                                   ),
                                                ],
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Special Instructions
                            Text('Special Instructions', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: instructionController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Add note (extra mayo, cheese, etc.)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.primary)),
                                fillColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Footer checkout button
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          final List<String> notesParts = [];
                          notesParts.add('Size: $selectedSize');
                          
                          final List<String> selectedExtrasNames = [];
                          selectedExtrasQty.forEach((name, qty) {
                            if (qty > 0) {
                              selectedExtrasNames.add('$name (x$qty)');
                            }
                          });
                          if (selectedExtrasNames.isNotEmpty) {
                            notesParts.add('Extras: ${selectedExtrasNames.join(", ")}');
                          }
                          
                          if (instructionController.text.trim().isNotEmpty) {
                            notesParts.add('Instructions: ${instructionController.text.trim()}');
                          }
                          
                          final finalNotes = notesParts.join(' | ');

                          // Calculate the single item price including size and extras (excluding addons!)
                          double finalItemPrice = basePrice + extrasSum;

                          final customProduct = ProductModel(
                            id: product.id,
                            name: product.name,
                            sinhalaName: product.sinhalaName,
                            description: product.description,
                            categoryId: product.categoryId,
                            price: product.price,
                            cost: product.cost,
                            activePrice: finalItemPrice, // Dynamic updated price including size and extras
                            isHappyHour: controller.getProductActivePrice(product) < product.price,
                            barcode: product.barcode,
                            stockQty: product.stockQty,
                            minStockLevel: product.minStockLevel,
                            isShortEat: product.isShortEat,
                            imageBase64: product.imageBase64,
                            status: product.status,
                            itemType: product.itemType,
                            tax: product.tax,
                            isFeatured: product.isFeatured,
                            caution: product.caution,
                            hasSizes: product.hasSizes,
                            hasExtras: product.hasExtras,
                            hasAddons: product.hasAddons,
                            sizes: product.sizes,
                            extras: product.extras,
                            addons: product.addons,
                          );

                          // Duplicate extra models for backend stock deduction based on their chosen count
                          final List<ProductExtra> selectedProductExtras = [];
                          selectedExtrasQty.forEach((name, qty) {
                            if (qty > 0) {
                              final originalExtra = product.extras.firstWhere((e) => e.name == name);
                              for (int i = 0; i < qty; i++) {
                                selectedProductExtras.add(originalExtra);
                              }
                            }
                          });

                          // 1. Add main item to cart with the finalItemPrice (which includes happy hour + size + extras)
                          controller.addToCart(
                            customProduct,
                            quantity: itemQty,
                            notes: finalNotes,
                            extras: selectedProductExtras,
                            customPrice: finalItemPrice,
                          );

                          // 2. Add addons to cart separately
                          selectedAddons.forEach((name, data) {
                            final qty = data['qty'] as int;
                            if (qty > 0) {
                              final addonMap = addons.firstWhere((a) => a['name'] == name);
                              final ProductModel addonProductObj = addonMap['product'];
                              controller.addToCart(addonProductObj, quantity: qty);
                            }
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Successfully added to cart'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text('Add to Cart - LKR ${totalPrice.toStringAsFixed(0)}'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddCustomerDialog(POSController controller) {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _customerBirthdayController.clear();
    _customerLimitController.clear();
    
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> selectBirthday() async {
              DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 25));
              if (_customerBirthdayController.text.isNotEmpty) {
                initial = DateTime.tryParse(_customerBirthdayController.text) ?? initial;
              }
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(1920),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _customerBirthdayController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Register New Customer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NAME *', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _customerNameController,
                        style: GoogleFonts.inter(fontSize: 13),
                        validator: (val) => val == null || val.isEmpty ? 'Please enter customer name' : null,
                        decoration: const InputDecoration(hintText: 'Enter customer name'),
                      ),
                      const SizedBox(height: 16),
                      
                      Text('PHONE NUMBER *', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _customerPhoneController,
                        style: GoogleFonts.inter(fontSize: 13),
                        keyboardType: TextInputType.phone,
                        validator: (val) => val == null || val.isEmpty ? 'Please enter phone number' : null,
                        decoration: const InputDecoration(hintText: 'Enter phone number'),
                      ),
                      const SizedBox(height: 16),
                      
                      Text('BIRTHDAY', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _customerBirthdayController,
                        style: GoogleFonts.inter(fontSize: 13),
                        readOnly: true,
                        onTap: selectBirthday,
                        decoration: const InputDecoration(
                          hintText: 'yyyy-mm-dd',
                          suffixIcon: Icon(Icons.calendar_today, size: 16, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      Text('CREDIT LIMIT (LKR)', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _customerLimitController,
                        style: GoogleFonts.inter(fontSize: 13),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Enter credit limit'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final double limit = double.tryParse(_customerLimitController.text) ?? 0.00;
                      final data = {
                        'name': _customerNameController.text,
                        'phone': _customerPhoneController.text,
                        'birthday': _customerBirthdayController.text.isEmpty ? null : _customerBirthdayController.text,
                        'credit_limit': limit
                      };
                      
                      if (controller.isOnline) {
                        await APIService.instance.createCustomer(data);
                      } else {
                        final newC = CustomerModel(
                          id: DateTime.now().millisecondsSinceEpoch,
                          name: _customerNameController.text,
                          phone: _customerPhoneController.text,
                          birthday: _customerBirthdayController.text.isEmpty ? null : _customerBirthdayController.text,
                          creditLimit: limit,
                          outstandingBalance: 0.00,
                        );
                        controller.customers.add(newC);
                      }
                      
                      await controller.reloadEnvironment();
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Customer registered successfully'), backgroundColor: AppTheme.accent),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Customer save failed: $e'), backgroundColor: AppTheme.danger),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text('Register', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBarcodeScanDialog(POSController controller) {
    _barcodeInputController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Barcode Scanner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 64, color: AppTheme.primary),
            const SizedBox(height: 12),
            const Text('Scan acknowledgement ticket barcode or input order number manually to retrieve:'),
            const SizedBox(height: 16),
            TextField(
              controller: _barcodeInputController,
              decoration: const InputDecoration(
                labelText: 'Order / Barcode Number',
                hintText: 'ORD-YYYYMMDD-XXXX',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final barcodeVal = _barcodeInputController.text.trim();
                if (barcodeVal.isEmpty) return;
                
                if (mounted) {
                  Navigator.pop(context);
                }
                
                final order = await APIService.instance.getOrderByBarcode(barcodeVal);
                if (mounted) {
                  _showRetrieveOrderDialog(order, controller);
                }
              } catch (e) {
                if (mounted) {
                  _showErrorSnackBar(e.toString());
                }
              }
            },
            child: const Text('Retrieve'),
          ),
        ],
      ),
    );
  }

  void _showRetrieveOrderDialog(OrderModel order, POSController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retrieved Order: ${order.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${order.orderType.toUpperCase()}'),
            Text('Status: ${order.status.toUpperCase()}'),
            Text('Payment Status: ${order.paymentStatus.toUpperCase()}'),
            const SizedBox(height: 12),
            Text('Total Amount: LKR ${order.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (order.paymentStatus == 'unpaid')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                controller.clearCart();
                controller.setOrderType(order.orderType);
                if (order.tableId != null) {
                  final tbl = controller.diningTables.firstWhere((t) => t.id == order.tableId);
                  controller.selectTable(tbl);
                }
                if (order.customerId != null) {
                  final cust = controller.customers.firstWhere((c) => c.id == order.customerId);
                  controller.selectCustomer(cust);
                }
                controller.setStewardName(order.stewardName);
                controller.setDiscount(order.discount);
                
                for (var item in order.items) {
                  final prod = controller.products.firstWhere((p) => p.id == item.productId);
                  controller.addToCart(prod, quantity: item.quantity, notes: item.notes);
                }
                
                _showOrderPaymentDialog(controller);
              },
              child: const Text('Proceed to Checkout'),
            ),
        ],
      ),
    );
  }

  void _showOrderPaymentDialog(POSController controller) {
    String paymentMethod = 'cash'; // 'cash', 'card', 'qr', 'credit'
    String enteredAmount = '';
    CustomerModel? selectedCreditCustomer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cartTotal = controller.cartTotal;
            final double receivedVal = double.tryParse(enteredAmount) ?? 0.00;
            final double changeVal = receivedVal > cartTotal ? receivedVal - cartTotal : 0.00;

            // Trigger LankaQR generation if tab is QR
            if (paymentMethod == 'qr' && controller.activeLankaQR == null) {
              controller.generateLankaQR();
            }

            void handleKeyPress(String key) {
              setModalState(() {
                if (key == '⌫') {
                  if (enteredAmount.isNotEmpty) {
                    enteredAmount = enteredAmount.substring(0, enteredAmount.length - 1);
                  }
                } else if (key == 'Clear') {
                  enteredAmount = '';
                } else {
                  // Max 10 digits
                  if (enteredAmount.length < 10) {
                    if (key == '.' && enteredAmount.contains('.')) return;
                    enteredAmount += key;
                  }
                }
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Order Payment',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 24),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),

                    // Total Amount Display
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'LKR ${cartTotal.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Payment Method Tabs
                    Text(
                      'Select Payment Method',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Cash
                        Expanded(
                          child: _buildPaymentTabButton(
                            label: 'Cash',
                            icon: Icons.wallet_outlined,
                            isActive: paymentMethod == 'cash',
                            onTap: () {
                              setModalState(() {
                                paymentMethod = 'cash';
                                enteredAmount = '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Card
                        Expanded(
                          child: _buildPaymentTabButton(
                            label: 'Card',
                            icon: Icons.credit_card_outlined,
                            isActive: paymentMethod == 'card',
                            onTap: () {
                              setModalState(() {
                                paymentMethod = 'card';
                                enteredAmount = '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // MFS
                        Expanded(
                          child: _buildPaymentTabButton(
                            label: 'MFS',
                            icon: Icons.qr_code_scanner_outlined,
                            isActive: paymentMethod == 'qr',
                            onTap: () {
                              setModalState(() {
                                paymentMethod = 'qr';
                                enteredAmount = '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Other / Credit
                        Expanded(
                          child: _buildPaymentTabButton(
                            label: 'Other',
                            icon: Icons.assignment_ind_outlined,
                            isActive: paymentMethod == 'credit',
                            onTap: () {
                              setModalState(() {
                                paymentMethod = 'credit';
                                enteredAmount = '';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Area based on selection
                    if (paymentMethod == 'cash') ...[
                      Text(
                        'Enter Received Amount',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                        child: Text(
                          enteredAmount.isEmpty ? '0.00' : enteredAmount,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Change Amount',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'LKR ${changeVal.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildKeypad(handleKeyPress),
                    ] else if (paymentMethod == 'card') ...[
                      Text(
                        'Enter Last 4 Digits Of Card',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                        child: Text(
                          enteredAmount.isEmpty ? '****' : enteredAmount,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildKeypad(handleKeyPress),
                    ] else if (paymentMethod == 'qr') ...[
                      Text(
                        'Scan LankaQR Code',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: controller.activeLankaQR != null
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: QrImageView(
                                  data: controller.activeLankaQR!,
                                  version: QrVersions.auto,
                                  size: 150.0,
                                ),
                              )
                            : SizedBox(
                                height: 150,
                                child: Center(
                                  child: CircularProgressIndicator(color: AppTheme.primary),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Merchant: Hotel POS (PVT) Ltd',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF475569)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Or Enter Transaction Reference ID:',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                        child: Text(
                          enteredAmount.isEmpty ? 'Reference ID' : enteredAmount,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: enteredAmount.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildKeypad(handleKeyPress),
                    ] else if (paymentMethod == 'credit') ...[
                      Text(
                        'Select Credit Customer',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<CustomerModel>(
                            value: selectedCreditCustomer,
                            hint: Text('Choose credit account...', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                            items: [
                              ...controller.customers
                                  .where((c) => c.id != 1)
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text('${c.name} (${c.phone})', style: GoogleFonts.inter(fontSize: 12)),
                                      )),
                            ],
                            onChanged: (c) {
                              setModalState(() {
                                selectedCreditCustomer = c;
                              });
                            },
                          ),
                        ),
                      ),
                      if (selectedCreditCustomer != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Credit Status:',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFB45309),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Credit Limit: LKR ${selectedCreditCustomer!.creditLimit.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF78350F)),
                              ),
                              Text(
                                'Outstanding Balance: LKR ${selectedCreditCustomer!.outstandingBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF78350F)),
                              ),
                              Text(
                                'Remaining Credit: LKR ${(selectedCreditCustomer!.creditLimit - selectedCreditCustomer!.outstandingBalance).toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (selectedCreditCustomer!.creditLimit - selectedCreditCustomer!.outstandingBalance) >= cartTotal
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF991B1B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Confirm & Print Action Button
                    ElevatedButton(
                      onPressed: () async {
                        // Validation
                        if (paymentMethod == 'cash') {
                          if (receivedVal < cartTotal) {
                            _showErrorSnackBar('Received amount must be greater than or equal to total payable.');
                            return;
                          }
                        } else if (paymentMethod == 'card') {
                          if (enteredAmount.length < 4) {
                            _showErrorSnackBar('Please enter at least last 4 digits of card.');
                            return;
                          }
                        } else if (paymentMethod == 'credit') {
                          if (selectedCreditCustomer == null) {
                            _showErrorSnackBar('Please select a credit customer for weekly billing settlement.');
                            return;
                          }
                        }

                        // Create ReceiptData copy
                        final List<OrderItemModel> itemsCopy = List.from(controller.cart);
                        final double finalSub = controller.cartSubtotal;
                        final double finalDisc = controller.discount;
                        final double finalTot = controller.cartTotal;
                        final String orderTypeLabel = controller.orderType == 'dine_in'
                            ? 'Dining Table'
                            : controller.orderType == 'takeaway'
                                ? 'Takeaway'
                                : 'Delivery';
                        final String? tblName = controller.selectedTable?.tableNumber;
                        final String? custName = paymentMethod == 'credit' ? selectedCreditCustomer!.name : controller.selectedCustomer?.name;
                        final int tknNumber = int.tryParse(_tokenNoController.text) ?? (controller.activeOrders.length + 1);
                        final String cashierUsername = APIService.instance.currentUser?.username ?? 'admin';

                        try {
                          if (paymentMethod == 'credit' && selectedCreditCustomer != null) {
                            controller.selectCustomer(selectedCreditCustomer);
                          }

                          // Close payment dialog first
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }

                          // Place order (triggers clearCart + reloadEnvironment)
                          final orderResult = await controller.placeOrder(
                            printKOT: true,
                            printAck: true,
                            status: 'delivered',
                            paymentStatus: paymentMethod == 'credit' ? 'unpaid' : 'paid',
                            paymentMethod: paymentMethod,
                          );

                          final int orderId = orderResult['orderId'] ?? 0;
                          final String orderNum = orderResult['orderNumber'] ?? '';

                          final receiptData = ReceiptData(
                            orderId: orderId,
                            orderNumber: orderNum,
                            paymentMethod: paymentMethod,
                            items: itemsCopy,
                            subtotal: finalSub,
                            discount: finalDisc,
                            total: finalTot,
                            orderType: orderTypeLabel,
                            tableName: tblName,
                            customerName: custName,
                            receivedAmount: paymentMethod == 'cash' ? receivedVal : finalTot,
                            changeAmount: paymentMethod == 'cash' ? changeVal : 0.00,
                            tokenNumber: tknNumber,
                            cardLastDigits: paymentMethod == 'card' ? enteredAmount : null,
                            transactionRef: paymentMethod == 'qr' ? enteredAmount : null,
                            cashierName: cashierUsername,
                          );

                          // TTS voice notification to kitchen
                          String ttsMsg = "Payment complete. Invoice generated. Kitchen copy printed for table ${tblName ?? 'Takeaway'}. ";
                          for (var item in itemsCopy) {
                            ttsMsg += "${item.quantity} ${item.productName}. ";
                          }
                          controller.speakVoiceMessage(ttsMsg);

                          // Show receipt dialog — State is guaranteed alive because
                          // main_layout no longer replaces the screen during isLoading.
                          // Use this.context (State's context, never shadowed here).
                          _showReceiptDialog(receiptData);
                          _tokenNoController.clear();

                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Confirm & Print Receipt',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentTabButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFFF0F5) : const Color(0xFFF8FAFC),
          border: Border.all(
            color: isActive ? AppTheme.primary : Color(0xFFE2E8F0),
            width: isActive ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.primary : Color(0xFF64748B),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? AppTheme.primary : Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(Function(String) onKeyPress) {
    final List<String> keys = [
      '1', '2', '3', '⌫',
      '4', '5', '6', '',
      '7', '8', '9', '',
      '00', '0', '.', 'Clear',
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: keys.length,
      itemBuilder: (context, idx) {
        final key = keys[idx];
        if (key.isEmpty) return const SizedBox.shrink();

        final isAction = key == '⌫' || key == 'Clear';
        return ElevatedButton(
          onPressed: () => onKeyPress(key),
          style: ElevatedButton.styleFrom(
            backgroundColor: isAction ? const Color(0xFFF1F5F9) : Colors.white,
            foregroundColor: isAction ? const Color(0xFF475569) : const Color(0xFF1E293B),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            padding: EdgeInsets.zero,
          ),
          child: key == '⌫'
              ? const Icon(Icons.backspace_outlined, size: 16)
              : Text(
                  key,
                  style: GoogleFonts.inter(
                    fontSize: key == 'Clear' ? 11 : 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        );
      },
    );
  }

  void _showReceiptDialog(ReceiptData data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildReceiptDialogWidget(data),
    );
  }

  /// Builds the receipt dialog widget (KOT + Invoice side-by-side).
  /// Extracted so it can be passed to showDialog from any context.
  Widget _buildReceiptDialogWidget(ReceiptData data) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFFF1F5F9),
      child: Builder(
        builder: (dialogCtx) {
          final controller = Provider.of<POSController>(dialogCtx, listen: false);
          return Container(
            width: MediaQuery.of(dialogCtx).size.width * 0.8,
            constraints: BoxConstraints(
              maxWidth: 780,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
            ),
            child: Column(
              children: [
                // Top Action Buttons
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const Spacer(),
                      // Print KOT
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final bytes = await _generateKOTPdfBytes(data, controller);
                            await Printing.layoutPdf(
                              onLayout: (format) async => bytes,
                              name: 'KOT_Token_${data.tokenNumber}',
                            );
                          } catch (e) {
                            _showErrorSnackBar('Failed to print KOT: $e');
                          }
                        },
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print KOT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Download KOT PDF
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final bytes = await _generateKOTPdfBytes(data, controller);
                            await _savePdfToFile(bytes, 'KOT_Token_${data.tokenNumber}.pdf');
                          } catch (e) {
                            _showErrorSnackBar('Failed to download KOT: $e');
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Download KOT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Print Invoice
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final bytes = await _generateInvoicePdfBytes(data, controller);
                            await Printing.layoutPdf(
                              onLayout: (format) async => bytes,
                              name: 'Invoice_Token_${data.tokenNumber}',
                            );
                          } catch (e) {
                            _showErrorSnackBar('Failed to print Invoice: $e');
                          }
                        },
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print Invoice'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Download Invoice PDF
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final bytes = await _generateInvoicePdfBytes(data, controller);
                            await _savePdfToFile(bytes, 'Invoice_Token_${data.tokenNumber}.pdf');
                          } catch (e) {
                            _showErrorSnackBar('Failed to download Invoice: $e');
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Download Invoice'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),

                // Both slips side-by-side
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 340, child: _buildKOTSlip(data, controller)),
                            const SizedBox(width: 20),
                            SizedBox(width: 340, child: _buildCustomerInvoiceSlip(data, controller)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Save [bytes] as a PDF. Opens a Save-As dialog (Windows/Linux/macOS)
  /// via FilePicker so the user can pick any download location.
  Future<void> _savePdfToFile(Uint8List bytes, String suggestedName) async {
    try {
      // Try native Save-As dialog first (desktop)
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('PDF saved: ${file.path}')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (_) {
      // Fallback: use printing package share sheet (opens save/print dialog)
      await Printing.sharePdf(bytes: bytes, filename: suggestedName);
    }
  }

  Future<Uint8List> _generateKOTPdfBytes(ReceiptData data, POSController controller) async {
    final pdf = pw.Document();
    
    // Load Sinhala Font
    final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
    final sinhalaFont = pw.Font.ttf(fontData);
    
    final kotItems = data.items.where((item) {
      final p = controller.products.firstWhere(
        (p) => p.id == item.productId,
        orElse: () => ProductModel(id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false, isKotItem: false),
      );
      return p.id != 0 && p.isKotItem;
    }).toList();

    final int totalQty = kotItems.fold(0, (sum, item) => sum + item.quantity);
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  _getKOTHeader(data, controller),
                  style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 5),
              
              _buildPdfInfoRow('KOT No:', _getKOTNumber(data), sinhalaFont),
              _buildPdfInfoRow('Date:', '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}', sinhalaFont),
              _buildPdfInfoRow('Time:', _formatTime(DateTime.now(), includeSpace: true), sinhalaFont),
              if (data.tableName != null && data.tableName!.isNotEmpty)
                _buildPdfInfoRow('Table:', data.tableName!, sinhalaFont),
              
              pw.SizedBox(height: 4),
              _buildPdfDashedLine(),
              pw.SizedBox(height: 4),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Description', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Qty', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 3),

              ...kotItems.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4.0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              item.productSinhalaName ?? item.productName,
                              style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            '${item.quantity}',
                            style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          '  * ${item.notes!}',
                          style: pw.TextStyle(font: sinhalaFont, fontSize: 7, fontStyle: pw.FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),

              pw.SizedBox(height: 3),
              _buildPdfDashedLine(),
              pw.SizedBox(height: 3),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    '$totalQty',
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              _buildPdfDashedLine(),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> _generateInvoicePdfBytes(ReceiptData data, POSController controller) async {
    final pdf = pw.Document();
    
    // Load Sinhala Font
    final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
    final sinhalaFont = pw.Font.ttf(fontData);

    // Load Logo
    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/images/mhb_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}
    
    final int totalQty = data.items.fold(0, (sum, item) => sum + item.quantity);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo & Oval Header Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null) ...[
                        pw.Image(logoImage, width: 28, height: 28),
                        pw.SizedBox(width: 6),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'මාතර හෝටලය',
                            style: pw.TextStyle(font: sinhalaFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            'නො: 04 මහා වීදිය, අකුරැස්ස',
                            style: pw.TextStyle(font: sinhalaFont, fontSize: 7, color: PdfColors.grey700),
                          ),
                          pw.Text(
                            '041 2283857',
                            style: pw.TextStyle(font: sinhalaFont, fontSize: 7, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                    ),
                    child: pw.Text(
                      _getOvalNumber(data),
                      style: pw.TextStyle(font: sinhalaFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(font: sinhalaFont, fontSize: 10, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline),
                ),
              ),
              pw.SizedBox(height: 4),
              
              _buildPdfInfoRow('Receipt No', _getReceiptNumber(data), sinhalaFont),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Date  ${DateTime.now().day.toString().padLeft(2, '0')}-${_getMonthName(DateTime.now())}-${DateTime.now().year}',
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                  ),
                  pw.Text(
                    _formatTime(DateTime.now(), includeSpace: false),
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                  ),
                  pw.Text(
                    data.cashierName,
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 4),
              _buildPdfDashedLine(),
              pw.SizedBox(height: 4),

              pw.Row(
                children: [
                  pw.Expanded(flex: 3, child: pw.Text('Description', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Expanded(flex: 1, child: pw.Align(alignment: pw.Alignment.center, child: pw.Text('Qty', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8)))),
                  pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Price', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8)))),
                  pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Amount', style: pw.TextStyle(font: sinhalaFont, fontWeight: pw.FontWeight.bold, fontSize: 8)))),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),

              ...data.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4.0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              item.productSinhalaName ?? item.productName,
                              style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Align(
                              alignment: pw.Alignment.center,
                              child: pw.Text('${item.quantity}', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(item.price.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text((item.price * item.quantity).toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                            ),
                          ),
                        ],
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          '  * ${item.notes!}',
                          style: pw.TextStyle(font: sinhalaFont, fontSize: 7, fontStyle: pw.FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              
              pw.SizedBox(height: 3),
              _buildPdfDashedLine(),
              pw.SizedBox(height: 4),
              
              // Summary
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('No of Items', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text('$totalQty', style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('Total', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 15),
                      pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(data.total.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.SizedBox.shrink(),
                  pw.Row(
                    children: [
                      pw.Text('Paid Amount', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 5),
                      pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(data.receivedAmount.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'PAID BY ${data.paymentMethod.toUpperCase()}',
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Row(
                    children: [
                      pw.Text('Balance', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(data.changeAmount.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 4),
              _buildPdfDashedLine(),
              pw.SizedBox(height: 5),
              
              pw.Center(
                child: pw.Text('Thank you & Come Again', style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Center(
                child: pw.Text('Software by Perpova. 0713555566', style: pw.TextStyle(font: sinhalaFont, fontSize: 7)),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  void _showPrintJobsQueuedDialog(BuildContext context, ReceiptData data, {required bool printKOT, required bool printInvoice}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.print, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text('Print Jobs Queued', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invoice and KOT tickets successfully sent to thermal printer network:'),
            const SizedBox(height: 12),
            if (printKOT)
              _buildPrintJobItem('1. KOT Ticket (Kitchen Copy)', 'Sent to Kitchen Printer (Table: ${data.tableName ?? "Takeaway"})'),
            if (printInvoice) ...[
              _buildPrintJobItem('2. Customer Invoice Receipt', 'Sent to Cashier Receipt Printer'),
              if (data.paymentMethod == 'credit')
                _buildPrintJobItem('3. Credit Agreement Receipt', 'Sent to Cashier Receipt Printer (Merchant Signed Copy)'),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getKOTNumber(ReceiptData data) {
    final prefix = data.orderType.toLowerCase().contains('take') 
        ? 'TK' 
        : data.orderType.toLowerCase().contains('deli') 
            ? 'DL' 
            : 'DI';
    final paddedId = data.orderId.toString().padLeft(9, '0');
    return '$prefix$paddedId';
  }

  String _getReceiptNumber(ReceiptData data) {
    final paddedId = data.orderId.toString().padLeft(9, '0');
    return '1$paddedId';
  }

  String _getOvalNumber(ReceiptData data) {
    final idStr = data.orderId.toString();
    if (idStr.length >= 3) {
      return idStr.substring(idStr.length - 3);
    }
    return idStr.padLeft(3, '0');
  }

  String _getKOTHeader(ReceiptData data, POSController controller) {
    String orderTypeUpper = data.orderType.toUpperCase();
    if (orderTypeUpper.contains("DINING")) {
      orderTypeUpper = "DINE IN";
    } else if (orderTypeUpper.contains("TAKE")) {
      orderTypeUpper = "TAKE AWAY";
    } else if (orderTypeUpper.contains("DELI")) {
      orderTypeUpper = "DELIVERY";
    }
    
    if (data.items.isNotEmpty) {
      final firstItem = data.items.first;
      final product = controller.products.firstWhere(
        (p) => p.id == firstItem.productId,
        orElse: () => ProductModel(
          id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false
        ),
      );
      if (product.id != 0) {
        final category = controller.categories.firstWhere(
          (c) => c.id == product.categoryId,
          orElse: () => CategoryModel(id: 0, name: ''),
        );
        if (category.id != 0) {
          return "KOT $orderTypeUpper - ${category.name}";
        }
      }
    }
    return "KOT $orderTypeUpper";
  }

  pw.Widget _buildPdfInfoRow(String label, String val, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text(val, style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfDashedLine() {
    return pw.Text(
      '-' * 45,
      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
    );
  }

  String _getMonthName(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1];
  }

  String _formatTime(DateTime dt, {bool includeSpace = true}) {
    final hour12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final hourStr = hour12.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');
    final secStr = dt.second.toString().padLeft(2, '0');
    return '$hourStr:$minStr:$secStr${includeSpace ? " " : ""}$period';
  }

  Widget _buildKOTSlip(ReceiptData data, POSController controller) {
    final kotItems = data.items.where((item) {
      final p = controller.products.firstWhere(
        (p) => p.id == item.productId,
        orElse: () => ProductModel(id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false, isKotItem: false),
      );
      return p.id != 0 && p.isKotItem;
    }).toList();

    final int totalQty = kotItems.fold(0, (sum, item) => sum + item.quantity);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              _getKOTHeader(data, controller),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
          ),
          const SizedBox(height: 8),
          
          _buildInfoRow('KOT No:', _getKOTNumber(data)),
          _buildInfoRow('Date:', '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}'),
          _buildInfoRow('Time:', _formatTime(DateTime.now(), includeSpace: true)),
          if (data.tableName != null && data.tableName!.isNotEmpty)
            _buildInfoRow('Table:', data.tableName!),
          
          const SizedBox(height: 6),
          _buildDashedLine(),
          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Description', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold)),
              Text('Qty', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 6),

          ...kotItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.productSinhalaName ?? item.productName,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${item.quantity}',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '  * ${item.notes!}',
                      style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 4),
          _buildDashedLine(),
          const SizedBox(height: 4),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$totalQty',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildDashedLine(),
        ],
      ),
    );
  }

  Widget _buildCustomerInvoiceSlip(ReceiptData data, POSController controller) {
    final int totalQty = data.items.fold(0, (sum, item) => sum + item.quantity);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Oval Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/mhb_logo.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.restaurant_menu, size: 32, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'මාතර හෝටලය',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      Text(
                        'නො: 04 මහා වීදිය, අකුරැස්ස',
                        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
                      ),
                      Text(
                        '041 2283857',
                        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF1E293B), width: 1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _getOvalNumber(data),
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'INVOICE',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: const Color(0xFF1E293B)),
            ),
          ),
          const SizedBox(height: 6),
          
          _buildInfoRow('Receipt No', _getReceiptNumber(data)),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Date  ${DateTime.now().day.toString().padLeft(2, '0')}-${_getMonthName(DateTime.now())}-${DateTime.now().year}',
                style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
              Text(
                _formatTime(DateTime.now(), includeSpace: false),
                style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
              Text(
                data.cashierName,
                style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          _buildDashedLine(),
          const SizedBox(height: 6),

          Row(
            children: [
              Expanded(flex: 3, child: Text('Description', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 1, child: Align(alignment: Alignment.center, child: Text('Qty', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold)))),
              Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('Price', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold)))),
              Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('Amount', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold)))),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 6),

          ...data.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          item.productSinhalaName ?? item.productName,
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text('${item.quantity}', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(item.price.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text((item.price * item.quantity).toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '  * ${item.notes!}',
                      style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 4),
          _buildDashedLine(),
          const SizedBox(height: 6),
          
          // Summary rows matching photo
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('No of Items', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text('$totalQty', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
              Row(
                children: [
                  Text('Total', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 32),
                  Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text(data.total.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox.shrink(),
              Row(
                children: [
                  Text('Paid Amount', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 8),
                  Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text(data.receivedAmount.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PAID BY ${data.paymentMethod.toUpperCase()}',
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              Row(
                children: [
                  Text('Balance', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 22),
                  Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text(data.changeAmount.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          _buildDashedLine(),
          const SizedBox(height: 8),
          
          Center(
            child: Text(
              'Thank you & Come Again',
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
            ),
          ),
          Center(
            child: Text(
              'Software by Perpova. 0713555566',
              style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashedLine() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFCBD5E1)),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildPrintJobItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                Text(desc, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
          Text(val, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF475569))),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
          Text(val, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
      );
    }
  }
}

class ReceiptData {
  final int orderId;
  final String orderNumber;
  final String paymentMethod;
  final List<OrderItemModel> items;
  final double subtotal;
  final double discount;
  final double total;
  final String orderType;
  final String? tableName;
  final String? customerName;
  final double receivedAmount;
  final double changeAmount;
  final int tokenNumber;
  final String? cardLastDigits;
  final String? transactionRef;
  final String cashierName;

  ReceiptData({
    required this.orderId,
    required this.orderNumber,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.orderType,
    this.tableName,
    this.customerName,
    required this.receivedAmount,
    required this.changeAmount,
    required this.tokenNumber,
    this.cardLastDigits,
    this.transactionRef,
    required this.cashierName,
  });
}
