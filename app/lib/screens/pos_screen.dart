import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                // Left: Products Grid (60% width)
                Expanded(
                  flex: 3,
                  child: _buildProductsArea(controller),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                // Right: Bill / Checkout Details (40% width)
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
                  height: size.height * 0.45,
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
          // Search and Barcode Input Row
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search products by name or scan barcode...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.textLightSecondary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (val) => controller.setSearchWord(val),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.barcode_reader, color: AppTheme.primary),
                tooltip: 'Scan acknowledgement barcode',
                onPressed: () => _showBarcodeScanDialog(controller),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal Categories Slider
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryTab(null, 'All Items', controller),
                ...controller.categories.map((cat) => _buildCategoryTab(cat.id, cat.name, controller)).toList(),
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
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
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

  Widget _buildCategoryTab(int? id, String title, POSController controller) {
    final isSelected = controller.activeCategoryId == id;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textLightSecondary,
          ),
        ),
        selected: isSelected,
        selectedColor: AppTheme.primary,
        backgroundColor: Colors.white,
        onSelected: (val) => controller.filterCategory(id),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product, POSController controller) {
    final isLowStock = product.stockQty <= product.minStockLevel;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isLowStock ? AppTheme.danger.withOpacity(0.5) : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: product.stockQty > 0 ? () => _showProductNotesDialog(product, controller) : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product visual representation
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppTheme.primary.withOpacity(0.05),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Base64ImageWidget(
                      base64Str: product.imageBase64,
                      width: double.infinity,
                      height: double.infinity,
                      fallback: Center(
                        child: Icon(
                          product.isShortEat ? Icons.bakery_dining_outlined : Icons.restaurant,
                          color: AppTheme.primary.withOpacity(0.6),
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (product.sinhalaName != null)
                Text(
                  product.sinhalaName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary, fontWeight: FontWeight.w500),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LKR ${product.activePrice.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                      if (product.isHappyHour)
                        Text(
                          'LKR ${product.price.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.textLightSecondary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isLowStock ? AppTheme.danger.withOpacity(0.1) : Colors.grey[200]!,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Qty: ${product.stockQty}',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isLowStock ? AppTheme.danger : AppTheme.textLightSecondary,
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer Picker Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<CustomerModel>(
                  value: controller.selectedCustomer,
                  decoration: const InputDecoration(
                    labelText: 'Select Customer',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    ...controller.customers.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.name} (${c.phone})', style: const TextStyle(fontSize: 12)),
                        )),
                  ],
                  onChanged: (c) => controller.selectCustomer(c),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                tooltip: 'Add new customer',
                onPressed: () => _showAddCustomerDialog(controller),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Order type picker Dine-In/Takeaway/Delivery
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTypeSelector('dine_in', 'Dine-In', controller),
              _buildTypeSelector('takeaway', 'Takeaway', controller),
              _buildTypeSelector('delivery', 'Delivery', controller),
            ],
          ),
          const SizedBox(height: 12),

          // Dine-in Table selectors / Delivery platform selectors
          if (controller.orderType == 'dine_in') ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DiningTableModel>(
                    value: controller.selectedTable,
                    decoration: const InputDecoration(
                      labelText: 'Select Table',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      ...controller.diningTables.map((t) => DropdownMenuItem(
                            value: t,
                            child: Text('${t.tableNumber} (${t.status.toUpperCase()})', style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                    onChanged: (t) => controller.selectTable(t),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Steward Name',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) => controller.setStewardName(val),
                  ),
                ),
              ],
            ),
          ] else if (controller.orderType == 'delivery') ...[
            DropdownButtonFormField<String>(
              value: controller.deliveryPlatform,
              decoration: const InputDecoration(
                labelText: 'Delivery Platform',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'uber_eats', child: Text('Uber Eats', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'pickme', child: Text('PickMe Food', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'phone', child: Text('Phone Order', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'direct', child: Text('Direct Delivery', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (platform) => controller.setDeliveryPlatform(platform),
            ),
          ],
          const SizedBox(height: 12),

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
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      if (item.notes != null)
                                        Text(
                                          'Note: ${item.notes}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w500),
                                        ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                                      onPressed: () => controller.updateCartQuantity(index, item.quantity - 1),
                                    ),
                                    Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 18),
                                      onPressed: () => controller.updateCartQuantity(index, item.quantity + 1),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('LKR ${(item.price * item.quantity).toStringAsFixed(0)}'),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),

          // Totals Section
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal:'),
                  Text('LKR ${controller.cartSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Discount:'),
                  SizedBox(
                    width: 100,
                    height: 30,
                    child: TextField(
                      controller: _discountController,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        hintText: '0.00',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final amt = double.tryParse(val) ?? 0.00;
                        controller.setDiscount(amt);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Bill:', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    'LKR ${controller.cartTotal.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Flow action buttons
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: controller.cart.isEmpty ? null : () => _handlePrintKOTFlow(controller),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.indigoGradient.colors.first,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Print KOT'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: controller.cart.isEmpty ? null : () => _handlePrintAcknowledgementFlow(controller),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warning,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Print ACK'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: controller.cart.isEmpty ? null : () => _showPaymentFlowDialog(controller),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Checkout & Pay'),
              ),
              if (controller.cart.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => controller.clearCart(),
                  child: const Text('Cancel / Reset Bill', style: TextStyle(color: AppTheme.danger)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(String type, String label, POSController controller) {
    final isSelected = controller.orderType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) => controller.setOrderType(type),
      selectedColor: AppTheme.primary.withOpacity(0.2),
      checkmarkColor: AppTheme.primary,
    );
  }

  // ----------------------------------------------------
  // FLOW IMPLEMENTATIONS (KOT, ACK, MOCK TICKET PRINT)
  // ----------------------------------------------------
  void _handlePrintKOTFlow(POSController controller) async {
    try {
      // Logic for Dine-In table seated state change
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
      // Logic for Table status billing change (yellow)
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
  void _showProductNotesDialog(ProductModel product, POSController controller) {
    _notesController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Notes for ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock Available: ${product.stockQty}'),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'e.g. 2 parcels, extra gravy, no stock powder',
                labelText: 'Order Notes',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.addToCart(product, notes: _notesController.text.isEmpty ? null : _notesController.text);
              Navigator.pop(context);
            },
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );
  }

  void _showAddCustomerDialog(POSController controller) {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _customerBirthdayController.clear();
    _customerLimitController.clear();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register New Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _customerNameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: _customerPhoneController, decoration: const InputDecoration(labelText: 'Phone Number')),
              const SizedBox(height: 10),
              TextField(controller: _customerBirthdayController, decoration: const InputDecoration(labelText: 'Birthday (YYYY-MM-DD)', hintText: '1990-05-15')),
              const SizedBox(height: 10),
              TextField(controller: _customerLimitController, decoration: const InputDecoration(labelText: 'Credit Limit (LKR)', hintText: '50000')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
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
                  // Offline save Mock
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
                if (mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  _showErrorSnackBar('Customer save failed: $e');
                }
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
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
            const Icon(Icons.qr_code_scanner, size: 64, color: AppTheme.primary),
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
                
                // Retrieve order
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
                // Load order items into current cart to settle
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
                
                _showPaymentFlowDialog(controller);
              },
              child: const Text('Proceed to Checkout'),
            ),
        ],
      ),
    );
  }

  void _showPaymentFlowDialog(POSController controller) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Choose Payment Method'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Total Payable: LKR ${controller.cartTotal.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
              const SizedBox(height: 20),
              
              // Cash payment
              ElevatedButton.icon(
                onPressed: () => _handleFinalCheckout(controller, 'cash'),
                icon: const Icon(Icons.money, color: Colors.white),
                label: const Text('Cash Payment'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              ),
              const SizedBox(height: 10),
              
              // LankaQR
              ElevatedButton.icon(
                onPressed: () async {
                  await controller.generateLankaQR();
                  setModalState(() {});
                  if (mounted) {
                    _showLankaQRDialog(controller);
                  }
                },
                icon: const Icon(Icons.qr_code, color: Colors.white),
                label: const Text('LankaQR (CBSL Compliant)'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
              ),
              const SizedBox(height: 10),
              
              // Card terminal simulation
              ElevatedButton.icon(
                onPressed: () async {
                  await controller.chargeCardMachine();
                  if (mounted) {
                    Navigator.pop(context); // Close selection
                    _showCardSimulatorDialog(controller);
                  }
                },
                icon: const Icon(Icons.credit_card, color: Colors.white),
                label: const Text('Credit/Debit Card Machine'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
              const SizedBox(height: 10),
              
              // Credit settlement (Mandatory select customer)
              ElevatedButton.icon(
                onPressed: () {
                  if (controller.selectedCustomer == null || controller.selectedCustomer!.id == 1) {
                    _showErrorSnackBar('Error: You must select a valid Customer (not Walking Customer) for Credit settlements.');
                  } else {
                    _handleFinalCheckout(controller, 'credit');
                  }
                },
                icon: const Icon(Icons.assignment_ind_outlined, color: Colors.white),
                label: const Text('Weekly Credit List Account'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  void _showLankaQRDialog(POSController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan LankaQR Compliant Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.activeLankaQR != null)
              SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  data: controller.activeLankaQR!,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              )
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('LKR ${controller.cartTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 12),
            const Text('Merchant: Hotel POS (PVT) Ltd', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const Text('Scan using any Sri Lankan bank app (e.g. Frimi, Flash, Solo).', style: TextStyle(fontSize: 10, color: AppTheme.textLightSecondary), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close qr
              _handleFinalCheckout(controller, 'qr');
            },
            child: const Text('Confirm Received'),
          ),
        ],
      ),
    );
  }

  void _showCardSimulatorDialog(POSController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<POSController>(
        builder: (context, ctrl, child) => AlertDialog(
          title: const Text('2-Way Card Machine Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ctrl.cardTerminalStatus == 'processing') ...[
                const CircularProgressIndicator(color: Colors.blue),
                const SizedBox(height: 16),
                const Text('Transaction sent to Card Reader...'),
                const Text('Waiting for customer PIN / card swipe...', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ] else if (ctrl.cardTerminalStatus == 'approved') ...[
                const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.accent),
                const SizedBox(height: 16),
                const Text('TRANSACTION APPROVED', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
                Text('Auth Code: ${ctrl.cardTerminalTxRef ?? "000000"}'),
              ] else ...[
                const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
                const SizedBox(height: 16),
                const Text('TRANSACTION DECLINED', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
              ],
              const SizedBox(height: 16),
              Text('Amount: LKR ${ctrl.cartTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            if (ctrl.cardTerminalStatus != 'processing') ...[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ctrl.cardTerminalStatus = null;
                },
                child: const Text('Close'),
              ),
              if (ctrl.cardTerminalStatus == 'approved')
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleFinalCheckout(ctrl, 'card');
                  },
                  child: const Text('Complete Order'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleFinalCheckout(POSController controller, String method) async {
    try {
      final orderNum = 'ORD-${DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '')}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      
      // Place order in online/offline mode
      await controller.placeOrder(
        printKOT: false,
        printAck: false,
        status: 'delivered',
        paymentStatus: method == 'credit' ? 'unpaid' : 'paid',
        paymentMethod: method,
      );

      if (mounted) {
        Navigator.pop(context); // close modal
        _showReceiptDialog(orderNum, method, controller);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.toString());
      }
    }
  }

  void _showReceiptDialog(String orderNum, String method, POSController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Complete - Bill Receipt'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text('HOTEL PERPOVA', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Center(
                  child: Text('LAN-First Hybrid Terminal'),
                ),
                const Divider(),
                Text('Order: $orderNum', style: const TextStyle(fontSize: 12)),
                Text('Date: ${DateTime.now().toString().split('.')[0]}', style: const TextStyle(fontSize: 12)),
                Text('Payment: ${method.toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const Divider(),
                const Text('Items Printed Successfully.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    height: 50,
                    width: 200,
                    child: BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: orderNum,
                      drawText: false,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(orderNum, style: const TextStyle(fontSize: 9)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Print Receipt & Done'),
          ),
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
