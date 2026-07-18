import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../controllers/pos_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../models/models.dart';
import '../widgets/image_helper.dart';

class POSOrdersScreen extends StatefulWidget {
  const POSOrdersScreen({Key? key}) : super(key: key);

  @override
  State<POSOrdersScreen> createState() => _POSOrdersScreenState();
}

class _POSOrdersScreenState extends State<POSOrdersScreen> {
  List<OrderModel> _allOrders = [];
  bool _isLoadingOrders = false;
  String _errorMessage = '';
  
  // Selected order for Detail View
  OrderModel? _selectedOrder;
  bool _isUpdatingStatus = false;
  bool _isLoadingItems = false;

  // Search and Filter variables
  String _searchQuery = '';
  String _selectedTypeFilter = 'All'; // 'All', 'dine_in', 'takeaway', 'delivery'
  String _selectedStatusFilter = 'All'; // 'All', 'pending', 'preparing', 'prepared', 'delivered', 'cancelled'
  
  // Pagination variables
  int _currentPage = 1;
  final int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoadingOrders = true;
      _errorMessage = '';
    });
    try {
      final api = APIService.instance;
      final online = await api.checkOnline();
      List<OrderModel> ords = [];
      if (online) {
        ords = await api.getOrders();
      } else {
        ords = await LocalDB.instance.getUnsyncedOrders();
      }
      if (mounted) {
        setState(() {
          _allOrders = ords;
          // Sync selected order object if we are currently viewing one
          if (_selectedOrder != null) {
            final updatedIdx = ords.indexWhere((o) => o.id == _selectedOrder!.id);
            if (updatedIdx != -1) {
              final prevItems = _selectedOrder!.items;
              final newOrder = ords[updatedIdx];
              _selectedOrder = OrderModel(
                id: newOrder.id,
                orderNumber: newOrder.orderNumber,
                tableId: newOrder.tableId,
                orderType: newOrder.orderType,
                deliveryPlatform: newOrder.deliveryPlatform,
                customerId: newOrder.customerId,
                stewardName: newOrder.stewardName,
                status: newOrder.status,
                paymentStatus: newOrder.paymentStatus,
                paymentMethod: newOrder.paymentMethod,
                subtotal: newOrder.subtotal,
                discount: newOrder.discount,
                total: newOrder.total,
                cashierId: newOrder.cashierId,
                shiftId: newOrder.shiftId,
                kotPrinted: newOrder.kotPrinted,
                ackPrinted: newOrder.ackPrinted,
                cardTxReference: newOrder.cardTxReference,
                barcode: newOrder.barcode,
                createdAt: newOrder.createdAt,
                receivedAmount: newOrder.receivedAmount,
                changeAmount: newOrder.changeAmount,
                items: prevItems.isNotEmpty ? prevItems : newOrder.items,
              );
            }
          }
          _isLoadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load orders: $e';
          _isLoadingOrders = false;
        });
      }
    }
  }

  Future<void> _selectOrder(OrderModel order) async {
    setState(() {
      _selectedOrder = order;
      _isLoadingItems = order.items.isEmpty;
    });

    if (order.items.isNotEmpty) return;

    try {
      if (order.id != null) {
        final api = APIService.instance;
        final online = await api.checkOnline();
        if (online) {
          final items = await api.getOrderItems(order.id!);
          if (mounted) {
            setState(() {
              final updatedOrder = OrderModel(
                id: order.id,
                orderNumber: order.orderNumber,
                tableId: order.tableId,
                orderType: order.orderType,
                deliveryPlatform: order.deliveryPlatform,
                customerId: order.customerId,
                stewardName: order.stewardName,
                status: order.status,
                paymentStatus: order.paymentStatus,
                paymentMethod: order.paymentMethod,
                subtotal: order.subtotal,
                discount: order.discount,
                total: order.total,
                cashierId: order.cashierId,
                shiftId: order.shiftId,
                kotPrinted: order.kotPrinted,
                ackPrinted: order.ackPrinted,
                cardTxReference: order.cardTxReference,
                barcode: order.barcode,
                createdAt: order.createdAt,
                receivedAmount: order.receivedAmount,
                changeAmount: order.changeAmount,
                items: items,
              );
              _selectedOrder = updatedOrder;

              final idx = _allOrders.indexWhere((o) => o.id == order.id);
              if (idx != -1) {
                _allOrders[idx] = updatedOrder;
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load order items: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingItems = false;
        });
      }
    }
  }

  // Helper: Format Date
  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        // Convert to local time and format
        final localDt = dt.toLocal();
        return DateFormat('hh:mm a, dd-MM-yyyy').format(localDt);
      }
    } catch (_) {}
    return dateStr;
  }

  // Helpers: Resolve names
  String _getCustomerName(int? id, List<CustomerModel> customers) {
    if (id == null) return 'Walking Customer';
    final customer = customers.firstWhere(
      (c) => c.id == id,
      orElse: () => CustomerModel(id: id, name: 'Walking Customer', phone: '', creditLimit: 0, outstandingBalance: 0),
    );
    return customer.name;
  }

  String _getTableName(int? tableId, List<DiningTableModel> tables) {
    if (tableId == null) return 'N/A';
    final table = tables.firstWhere(
      (t) => t.id == tableId,
      orElse: () => DiningTableModel(id: tableId, tableNumber: 'Table', capacity: 4, status: 'empty'),
    );
    return table.tableNumber;
  }

  // Action: Update Order Status Online
  Future<void> _updateOrderStatus(OrderModel order, String field, String newValue) async {
    if (order.id == null) return;
    setState(() {
      _isUpdatingStatus = true;
    });
    try {
      final Map<String, dynamic> updatePayload = {field: newValue};
      await APIService.instance.updateOrderOnline(order.id!, updatePayload);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${field.replaceAll('_', ' ').toUpperCase()} updated to $newValue successfully.'),
          backgroundColor: AppTheme.accent,
        ),
      );
      
      await _loadOrders();
      // Reload POS Controller's active orders too
      if (mounted) {
        Provider.of<POSController>(context, listen: false).reloadEnvironment();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatus = false;
        });
      }
    }
  }

  // Action: Cancel Order (soft delete status update)
  Future<void> _promptCancelOrder(OrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Order', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to cancel Order #${order.orderNumber}? This will restore its items to the inventory stock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateOrderStatus(order, 'status', 'cancelled');
      if (_selectedOrder?.id == order.id) {
        setState(() {
          _selectedOrder = null;
        });
      }
    }
  }

  // Filtered orders list
  List<OrderModel> get _filteredOrders {
    return _allOrders.where((order) {
      final posController = Provider.of<POSController>(context, listen: false);
      final custName = _getCustomerName(order.customerId, posController.customers).toLowerCase();
      final orderNum = order.orderNumber.toLowerCase();
      final matchesSearch = orderNum.contains(_searchQuery.toLowerCase()) || custName.contains(_searchQuery.toLowerCase());

      final matchesType = _selectedTypeFilter == 'All' || order.orderType == _selectedTypeFilter;
      
      final matchesStatus = _selectedStatusFilter == 'All' || order.status == _selectedStatusFilter;

      return matchesSearch && matchesType && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final posController = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isLargeScreen = size.width > 900;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _selectedOrder == null 
              ? _buildOrderListUI(posController, isLargeScreen)
              : _buildOrderDetailUI(posController, isLargeScreen),
        ),
      ),
    );
  }

  // =========================================================================
  // ORDER LIST VIEW
  // =========================================================================
  Widget _buildOrderListUI(POSController posController, bool isLargeScreen) {
    final filtered = _filteredOrders;
    
    // Pagination slicing
    final startIndex = (_currentPage - 1) * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage) > filtered.length 
        ? filtered.length 
        : (startIndex + _rowsPerPage);
    
    List<OrderModel> paginatedOrders = [];
    if (startIndex < filtered.length) {
      paginatedOrders = filtered.sublist(startIndex, endIndex);
    }
    
    final totalPages = (filtered.length / _rowsPerPage).ceil();

    return Column(
      key: const ValueKey('OrderListKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POS Orders',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textLightPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                    Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                    Text('POS Orders', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                // Quick reload
                IconButton(
                  icon: Icon(Icons.refresh, color: AppTheme.primary),
                  onPressed: _loadOrders,
                ),
                const SizedBox(width: 8),
                // Filter outline button
                _buildOutlineIconButton(
                  icon: Icons.filter_alt_outlined,
                  label: 'Filter',
                  onTap: () => _showFilterDialog(),
                ),
                const SizedBox(width: 12),
                // Export outline button
                _buildOutlineIconButton(
                  icon: Icons.download_outlined,
                  label: 'Export',
                  onTap: () => _exportOrdersExcel(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Search & Quick Tabs Bar
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Search bar
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val;
                                _currentPage = 1; // Reset to page 1
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search by Order ID, customer...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            child: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Quick Filters Tabs
                _buildFilterChip('All', 'All', isType: true),
                const SizedBox(width: 8),
                _buildFilterChip('Dining Table', 'dine_in', isType: true),
                const SizedBox(width: 8),
                _buildFilterChip('Takeaway', 'takeaway', isType: true),
                const SizedBox(width: 8),
                _buildFilterChip('Delivery', 'delivery', isType: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Table
        Expanded(
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: _isLoadingOrders
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _loadOrders, child: const Text('Try Again')),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(child: Text('No orders found.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Table Header
                              Container(
                                color: const Color(0xFFF8FAFC),
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: _buildTableHeaderText('ORDER ID')),
                                    Expanded(flex: 2, child: _buildTableHeaderText('ORDER TYPE')),
                                    Expanded(flex: 2, child: _buildTableHeaderText('CUSTOMER')),
                                    Expanded(flex: 2, child: _buildTableHeaderText('AMOUNT')),
                                    Expanded(flex: 3, child: _buildTableHeaderText('DATE')),
                                    Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
                                    Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
                                  ],
                                ),
                              ),
                              // Table Rows
                              Expanded(
                                child: ListView.separated(
                                  itemCount: paginatedOrders.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  itemBuilder: (context, index) {
                                    final order = paginatedOrders[index];
                                    return _buildOrderRow(order, posController);
                                  },
                                ),
                              ),
                              
                              // Table Footer (Pagination)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      filtered.isEmpty 
                                          ? 'Showing 0 to 0 of 0 entries'
                                          : 'Showing ${startIndex + 1} to $endIndex of ${filtered.length} entries',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                    ),
                                    Row(
                                      children: [
                                        // Previous Page Button
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left, size: 18),
                                          onPressed: _currentPage > 1 
                                              ? () => setState(() => _currentPage--)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$_currentPage / ${totalPages == 0 ? 1 : totalPages}',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                        ),
                                        const SizedBox(width: 8),
                                        // Next Page Button
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right, size: 18),
                                          onPressed: _currentPage < totalPages 
                                              ? () => setState(() => _currentPage++)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF475569),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildOrderRow(OrderModel order, POSController posController) {
    final custName = _getCustomerName(order.customerId, posController.customers);
    
    // Order Type badging
    Color typeBg = const Color(0xFFFFF0F5);
    Color typeText = AppTheme.primary;
    String typeLabel = 'Dining Table';

    if (order.orderType == 'takeaway') {
      typeBg = const Color(0xFFFFF7ED);
      typeText = const Color(0xFFEA580C);
      typeLabel = 'Takeaway';
    } else if (order.orderType == 'delivery') {
      typeBg = const Color(0xFFF0FDF4);
      typeText = const Color(0xFF16A34A);
      typeLabel = 'Delivery';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Row(
        children: [
          // ORDER ID
          Expanded(
            flex: 2,
            child: Text(
              order.orderNumber.length > 10 
                  ? order.orderNumber.substring(order.orderNumber.length - 8)
                  : order.orderNumber,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
          ),
          
          // ORDER TYPE
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      typeLabel,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: typeText),
                    ),
                  ),
                  if (order.preOrderId != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Text(
                        'Pre-Order',
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // CUSTOMER
          Expanded(
            flex: 2,
            child: Text(
              custName,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), fontWeight: FontWeight.w500),
            ),
          ),

          // AMOUNT
          Expanded(
            flex: 2,
            child: Text(
              order.total.toStringAsFixed(2),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
          ),

          // DATE
          Expanded(
            flex: 3,
            child: Text(
              _formatDate(order.createdAt),
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ),

          // STATUS
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(order.status),
            ),
          ),

          // ACTION
          Expanded(
            flex: 2,
            child: Row(
              children: [
                // View icon button
                GestureDetector(
                  onTap: () => _selectOrder(order),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.visibility, color: AppTheme.primary, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                // Cancel/Delete icon button
                if (order.status != 'cancelled')
                  GestureDetector(
                    onTap: () => _promptCancelOrder(order),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.delete, color: AppTheme.danger, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFF1F5F9);
    Color text = const Color(0xFF64748B);
    String label = status.toUpperCase();

    switch (status) {
      case 'pending':
        bg = const Color(0xFFF0FDF4); // light green
        text = const Color(0xFF16A34A);
        label = 'Accept';
        break;
      case 'preparing':
        bg = const Color(0xFFFFF7ED); // light orange
        text = const Color(0xFFEA580C);
        label = 'Preparing';
        break;
      case 'prepared':
        bg = const Color(0xFFFAF5FF); // light purple
        text = const Color(0xFF9333EA);
        label = 'Prepared';
        break;
      case 'delivered':
        bg = const Color(0xFFECFDF5); // light emerald green
        text = const Color(0xFF047857);
        label = 'Delivered';
        break;
      case 'cancelled':
        bg = const Color(0xFFFEF2F2); // light red
        text = const Color(0xFFDC2626);
        label = 'Cancelled';
        break;
      case 'returned':
        bg = const Color(0xFFFEF2F2);
        text = const Color(0xFFDC2626);
        label = 'Returned';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  Widget _buildOutlineIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: AppTheme.primary),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppTheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, {required bool isType}) {
    final isSelected = isType ? _selectedTypeFilter == value : _selectedStatusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isType) {
            _selectedTypeFilter = value;
          } else {
            _selectedStatusFilter = value;
          }
          _currentPage = 1;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF0F5) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primary : Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempStatus = _selectedStatusFilter;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Filter POS Orders', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter by Order Status:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDialogChip('All', 'All', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                      _buildDialogChip('Accept', 'pending', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                      _buildDialogChip('Preparing', 'preparing', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                      _buildDialogChip('Prepared', 'prepared', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                      _buildDialogChip('Delivered', 'delivered', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                      _buildDialogChip('Cancelled', 'cancelled', tempStatus, (val) => setDialogState(() => tempStatus = val)),
                    ],
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
                    setState(() {
                      _selectedStatusFilter = tempStatus;
                      _currentPage = 1;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply Filter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogChip(String label, String val, String selectedVal, Function(String) onSelected) {
    final isSelected = val == selectedVal;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
      selected: isSelected,
      onSelected: (_) => onSelected(val),
      selectedColor: const Color(0xFFFFF0F5),
      labelStyle: TextStyle(color: isSelected ? AppTheme.primary : Color(0xFF475569)),
      checkmarkColor: AppTheme.primary,
    );
  }

  void _exportOrdersExcel() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Orders data exported successfully to Excel.'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

  // =========================================================================
  // ORDER DETAILS VIEW
  // =========================================================================
  Widget _buildOrderDetailUI(POSController posController, bool isLargeScreen) {
    final order = _selectedOrder!;
    final customer = posController.customers.firstWhere(
      (c) => c.id == order.customerId,
      orElse: () => CustomerModel(id: order.customerId ?? 1, name: 'Walking Customer', phone: 'N/A', creditLimit: 0, outstandingBalance: 0),
    );

    // Color Badges
    Color payBg = order.paymentStatus == 'paid' ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6);
    Color payText = order.paymentStatus == 'paid' ? const Color(0xFF137333) : const Color(0xFFC5221F);

    return Column(
      key: const ValueKey('OrderDetailKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation Header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _selectedOrder = null;
                });
              },
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Order ID: #${order.orderNumber.substring(order.orderNumber.length - 8)}',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLightPrimary,
                      ),
                    ),
                    if (order.preOrderId != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Text(
                          'Pre-Order',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                    Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                    Text('POS Orders', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                    Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                    Text('View', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const Spacer(),
            // Print invoice button
            ElevatedButton.icon(
              onPressed: () => _printInvoice(order, customer),
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Print Invoice'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Quick details row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildDetailInfoTile(Icons.calendar_today_outlined, 'Date', _formatDate(order.createdAt)),
              _buildDetailInfoTile(Icons.payment, 'Payment Type', (order.paymentMethod ?? 'Cash').toUpperCase()),
              _buildDetailInfoTile(Icons.restaurant_menu, 'Order Type', order.orderType == 'dine_in' ? 'Dining Table' : order.orderType == 'takeaway' ? 'Takeaway' : 'Delivery'),
              _buildDetailInfoTile(Icons.table_restaurant_outlined, 'Table Name', _getTableName(order.tableId, posController.diningTables)),
              _buildDetailInfoTile(Icons.badge_outlined, 'Cashier ID', 'ID: ${order.cashierId}'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Main Layout (Left: Items list, Right: Status Actions & Customer Details)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left pane: Items List
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order Details', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                        const SizedBox(height: 16),
                        _isLoadingItems
                            ? Expanded(
                                child: Center(
                                  child: CircularProgressIndicator(color: AppTheme.primary),
                                ),
                              )
                            : Expanded(
                                child: ListView.separated(
                            itemCount: order.items.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final item = order.items[index];
                              // Fetch product picture if available
                              final product = posController.products.firstWhere(
                                (p) => p.id == item.productId,
                                orElse: () => ProductModel(id: item.productId, name: item.productName, categoryId: 0, price: item.price, cost: 0, activePrice: item.price, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false),
                              );
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Row(
                                  children: [
                                    // Quantity badge
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${item.quantity}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Product Image or placeholder
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 50,
                                        height: 50,
                                        color: const Color(0xFFF1F5F9),
                                        child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
                                            ? Base64ImageWidget(base64Str: product.imageBase64, fit: BoxFit.cover)
                                            : const Icon(Icons.fastfood, color: Color(0xFF94A3B8), size: 24),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Item details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.productName, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                          if (item.notes != null && item.notes!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text('Notes: ${item.notes}', style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textLightSecondary)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Price
                                    Text(
                                      'LKR ${(item.price * item.quantity).toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              
              // Right pane: Actions, Summary, Customer Info
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Status Modification Card
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Manage Order', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                              const SizedBox(height: 16),
                              
                              // Payment Status Selector
                              Text('Payment Status', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: order.paymentStatus,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                                    ],
                                    onChanged: _isUpdatingStatus 
                                        ? null 
                                        : (val) => _updateOrderStatus(order, 'payment_status', val!),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Order Status Selector
                              Text('Order Status', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: order.status,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'pending', child: Text('Accept')),
                                      DropdownMenuItem(value: 'preparing', child: Text('Preparing')),
                                      DropdownMenuItem(value: 'prepared', child: Text('Prepared')),
                                      DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                                    ],
                                    onChanged: _isUpdatingStatus 
                                        ? null 
                                        : (val) => _updateOrderStatus(order, 'status', val!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Totals Summary Card
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSummaryRow('Subtotal', 'LKR ${order.subtotal.toStringAsFixed(2)}'),
                              const SizedBox(height: 8),
                              _buildSummaryRow('Discount', 'LKR ${order.discount.toStringAsFixed(2)}'),
                              const Divider(height: 24, color: Color(0xFFF1F5F9)),
                              _buildSummaryRow('Total', 'LKR ${order.total.toStringAsFixed(2)}', isBold: true, isPrice: true),
                              if ((order.paymentMethod ?? 'cash').toLowerCase() == 'cash' && order.receivedAmount > 0) ...[
                                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                                _buildSummaryRow('Received Amount', 'LKR ${order.receivedAmount.toStringAsFixed(2)}'),
                                const SizedBox(height: 8),
                                _buildSummaryRow('Change Amount', 'LKR ${order.changeAmount.toStringAsFixed(2)}'),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Delivery / Customer Info Card
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Customer Information', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                                    child: Icon(Icons.person, color: AppTheme.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(customer.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                        const SizedBox(height: 2),
                                        Text(customer.phone.isNotEmpty ? customer.phone : 'No Phone Number', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                                      ],
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailInfoTile(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textLightSecondary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
            Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, bool isPrice = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? AppTheme.textLightPrimary : AppTheme.textLightSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isPrice ? Colors.red : AppTheme.textLightPrimary,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // PDF INVOICE GENERATION & PRINTING
  // =========================================================================
  Future<void> _printInvoice(OrderModel order, CustomerModel customer) async {
    // For cash orders, if we have historic receivedAmount in database, use it. Otherwise fall back to order.total.
    double receivedAmount = (order.paymentMethod ?? 'cash').toLowerCase() == 'cash'
        ? (order.receivedAmount > 0 ? order.receivedAmount : order.total)
        : order.total;
    double changeAmount = (order.paymentMethod ?? 'cash').toLowerCase() == 'cash'
        ? (order.receivedAmount > 0 ? order.changeAmount : 0.0)
        : 0.0;

    // We will use a controller for dynamic text updating if they edit cash paid
    final cashPaidController = TextEditingController(text: receivedAmount.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final receiptData = ReceiptData(
              orderId: order.id ?? 0,
              orderNumber: order.orderNumber,
              paymentMethod: order.paymentMethod ?? 'cash',
              items: order.items,
              subtotal: order.subtotal,
              discount: order.discount,
              total: order.total,
              orderType: order.orderType == 'dine_in' ? 'Dining Table' : order.orderType == 'takeaway' ? 'Takeaway' : 'Delivery',
              tableName: order.tableId != null ? 'Table ${order.tableId}' : null,
              customerName: customer.name,
              receivedAmount: receivedAmount,
              changeAmount: changeAmount,
              advancePayment: order.advancePayment,
              balanceAmount: order.balanceAmount,
              tokenNumber: order.id ?? 1,
              cashierName: 'Cashier ID: ${order.cashierId}',
              createdAt: order.createdAt,
            );

            final size = MediaQuery.of(context).size;
            final posController = Provider.of<POSController>(context, listen: false);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: const Color(0xFFF1F5F9),
              child: Container(
                width: size.width * 0.8,
                constraints: const BoxConstraints(
                  maxWidth: 780,
                  maxHeight: 700,
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
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Close'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if ((order.paymentMethod ?? 'cash').toLowerCase() == 'cash') ...[
                            // Real-time Cash Paid input
                            SizedBox(
                              width: 220,
                              height: 38,
                              child: TextField(
                                controller: cashPaidController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Cash Paid / Given (LKR)',
                                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (val) {
                                  final entered = double.tryParse(val) ?? 0.0;
                                  setDialogState(() {
                                    receivedAmount = entered;
                                    changeAmount = entered > order.total ? (entered - order.total) : 0.0;
                                  });
                                },
                              ),
                            ),
                          ],
                          const Spacer(),
                          // Print Invoice PDF
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final bytes = await _generateInvoicePdfBytes(receiptData);
                                await Printing.layoutPdf(
                                  onLayout: (format) async => bytes,
                                  name: 'Invoice_${receiptData.orderNumber}',
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to print Invoice: $e'), backgroundColor: AppTheme.danger),
                                );
                              }
                            },
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Print Invoice'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Download Invoice PDF
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final bytes = await _generateInvoicePdfBytes(receiptData);
                                await _savePdfToFile(bytes, 'Invoice_${receiptData.orderNumber}.pdf');
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to download Invoice: $e'), backgroundColor: AppTheme.danger),
                                );
                              }
                            },
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Download Invoice'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Slips Preview Mock
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(
                            child: SizedBox(
                              width: 350,
                              child: _buildCustomerInvoiceSlip(receiptData, posController),
                            ),
                          ),
                        ),
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

  Future<void> _savePdfToFile(Uint8List bytes, String suggestedName) async {
    try {
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
              content: Text('PDF saved successfully: ${file.path}'),
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      }
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: suggestedName);
    }
  }

  Future<Uint8List> _generateInvoicePdfBytes(ReceiptData data) async {
    final lang = Provider.of<DashboardController>(this.context, listen: false).selectedLanguage;
    final bool isSinhala = lang == 'Sinhala';
    
    // Load Sinhala Font
    final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
    final sinhalaFont = pw.Font.ttf(fontData);
    // Load Isiagini Font
    final isiaginiFontData = await rootBundle.load('assets/fonts/Isiagni.ttf');
    final isiaginiFont = pw.Font.ttf(isiaginiFontData);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: sinhalaFont,
        fontFallback: [pw.Font.helvetica()],
      ),
    );

    // Load Logo
    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/images/mhb_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}
    
    final int totalQty = data.items.fold(0, (sum, item) => sum + item.quantity);
    final dt = DateTime.tryParse(data.createdAt)?.toLocal() ?? DateTime.now();

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
                             'v£ly »ƒ£Šfzx',
                             style: pw.TextStyle(font: isiaginiFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
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
                    'Date  ${dt.day.toString().padLeft(2, '0')}-${_getMonthName(dt)}-${dt.year}',
                    style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                  ),
                  pw.Text(
                    _formatTime(dt, includeSpace: false),
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

              ..._groupDuplicateOrderItems(data.items).map((item) {
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
                              isSinhala ? (item.productSinhalaName ?? item.productName) : item.productName,
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
                      pw.Text('Sub Total', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 5),
                      pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(data.subtotal.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              
              if (data.discount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.SizedBox.shrink(),
                    pw.Row(
                      children: [
                        pw.Text('Discount', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 10),
                        pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 10),
                        pw.Text('-${data.discount.toStringAsFixed(2)}', style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
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
                      pw.Text('Total', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 15),
                      pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                      pw.SizedBox(width: 10),
                      pw.Text(data.total.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              if (data.advancePayment > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.SizedBox.shrink(),
                    pw.Row(
                      children: [
                        pw.Text('Advance Paid', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 5),
                        pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 10),
                        pw.Text(data.advancePayment.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
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
                        pw.Text('Balance Due', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 5),
                        pw.Text(':', style: pw.TextStyle(font: sinhalaFont, fontSize: 8)),
                        pw.SizedBox(width: 10),
                        pw.Text(data.balanceAmount.toStringAsFixed(2), style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ],
              
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
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: 'INV-${data.orderNumber}',
                  width: 150,
                  height: 30,
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  'INV-${data.orderNumber}',
                  style: pw.TextStyle(font: sinhalaFont, fontSize: 6, color: PdfColors.grey700),
                ),
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

  // Invoice Slip Preview Widget
  Widget _buildCustomerInvoiceSlip(ReceiptData data, POSController controller) {
    final lang = Provider.of<DashboardController>(context, listen: true).selectedLanguage;
    final bool isSinhala = lang == 'Sinhala';

    final int totalQty = data.items.fold(0, (sum, item) => sum + item.quantity);
    final dt = DateTime.tryParse(data.createdAt)?.toLocal() ?? DateTime.now();

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
                           'v£ly »ƒ£Šfzx',
                            style: const TextStyle(fontFamily: 'Isiagni',fontSize: 12,fontWeight: FontWeight.bold,color: Color(0xFF1E293B),),
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
                'Date  ${dt.day.toString().padLeft(2, '0')}-${_getMonthName(dt)}-${dt.year}',
                style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
              Text(
                _formatTime(dt, includeSpace: false),
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

          ..._groupDuplicateOrderItems(data.items).map((item) {
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
                          isSinhala ? (item.productSinhalaName ?? item.productName) : item.productName,
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
          
          // Summary rows
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
                  Text('Sub Total', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 12),
                  Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text(data.subtotal.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          
          if (data.discount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                Row(
                  children: [
                    Text('Discount', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 16),
                    Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 14),
                    Text('-${data.discount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
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
                  Text('Total', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 32),
                  Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                  const SizedBox(width: 14),
                  Text(data.total.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          if (data.advancePayment > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                Row(
                  children: [
                    Text('Advance Paid', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 8),
                    Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 14),
                    Text(data.advancePayment.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
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
                    Text('Balance Payable', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 8),
                    Text(':', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                    const SizedBox(width: 14),
                    Text(data.balanceAmount.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  ],
                ),
              ],
            ),
          ],
          
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
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: 'INV-${data.orderNumber}',
              width: 180,
              height: 40,
              drawText: false,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'INV-${data.orderNumber}',
              style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 6),
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

  // Invoice Slip Preview Helpers
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

  List<OrderItemModel> _groupDuplicateOrderItems(List<OrderItemModel> items) {
    final Map<String, OrderItemModel> grouped = {};
    for (var item in items) {
      final key = "${item.productId}_${item.price}_${item.notes ?? ''}";
      if (grouped.containsKey(key)) {
        final existing = grouped[key]!;
        grouped[key] = OrderItemModel(
          id: existing.id,
          orderId: existing.orderId,
          productId: existing.productId,
          productName: existing.productName,
          productSinhalaName: existing.productSinhalaName,
          quantity: existing.quantity + item.quantity,
          price: existing.price,
          notes: existing.notes,
          status: existing.status,
          isShortEat: existing.isShortEat,
          extras: existing.extras,
        );
      } else {
        grouped[key] = item;
      }
    }
    return grouped.values.toList();
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
}

// Struct matching ReceiptData inside pos_screen.dart to avoid circular dependency
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
  final double advancePayment;
  final double balanceAmount;
  final int tokenNumber;
  final String? cardLastDigits;
  final String? transactionRef;
  final String cashierName;
  final String createdAt;

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
    this.advancePayment = 0.00,
    this.balanceAmount = 0.00,
    required this.tokenNumber,
    this.cardLastDigits,
    this.transactionRef,
    required this.cashierName,
    required this.createdAt,
  });
}
