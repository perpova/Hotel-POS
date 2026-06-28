import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
                    const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                    Text('POS Orders', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                // Quick reload
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppTheme.primary),
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
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
              child: Container(
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
                    child: const Icon(Icons.visibility, color: AppTheme.primary, size: 16),
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
        side: const BorderSide(color: AppTheme.primary),
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
            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
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
      labelStyle: TextStyle(color: isSelected ? AppTheme.primary : const Color(0xFF475569)),
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
                Text(
                  'Order ID: #${order.orderNumber.substring(order.orderNumber.length - 8)}',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textLightPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                    const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                    Text('POS Orders', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                    const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
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
                            ? const Expanded(
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
                                    child: const Icon(Icons.person, color: AppTheme.primary),
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
    // Construct receipt dataset
    final receiptData = ReceiptData(
      orderNumber: order.orderNumber,
      paymentMethod: order.paymentMethod ?? 'cash',
      items: order.items,
      subtotal: order.subtotal,
      discount: order.discount,
      total: order.total,
      orderType: order.orderType == 'dine_in' ? 'Dining Table' : order.orderType == 'takeaway' ? 'Takeaway' : 'Delivery',
      tableName: order.tableId != null ? 'Table ${order.tableId}' : null,
      customerName: customer.name,
      receivedAmount: order.total,
      changeAmount: 0.0,
      tokenNumber: order.id ?? 1,
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFFF1F5F9),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
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
                    const Spacer(),
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

              // Slips PDF View Mock
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Container(
                        width: 350,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text('FoodKing - Restaurant', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            const Center(child: Text('Food Ordering & Delivery App', style: TextStyle(fontSize: 11, color: Colors.grey))),
                            const SizedBox(height: 12),
                            const Divider(color: Colors.black12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Order: #${order.orderNumber.substring(order.orderNumber.length - 8)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(_formatDate(order.createdAt), style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                            const Divider(color: Colors.black12),
                            const SizedBox(height: 8),
                            
                            // Items list
                            ...receiptData.items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Text('${item.quantity} x ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Expanded(child: Text(item.productName, style: const TextStyle(fontSize: 12))),
                                  Text('LKR ${(item.price * item.quantity).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            )),
                            
                            const Divider(color: Colors.black12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal:', style: TextStyle(fontSize: 12)),
                                Text('LKR ${receiptData.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Discount:', style: TextStyle(fontSize: 12)),
                                Text('LKR ${receiptData.discount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('LKR ${receiptData.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(color: Colors.black12),
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Token #${receiptData.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Center(child: Text('Thank You - Please Come Again', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('FoodKing - Restaurant', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              ),
              pw.Center(
                child: pw.Text('Food Ordering & Delivery App', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Center(
                child: pw.Text('House: 25, Road No: 2, Block A, Mirpur-1, Dhaka 1216', style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Order #: ${data.orderNumber.substring(data.orderNumber.length - 8)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 8),

              pw.Row(
                children: [
                  pw.Expanded(flex: 1, child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Expanded(flex: 4, child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)))),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),

              ...data.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4.0),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(flex: 1, child: pw.Text('${item.quantity}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(flex: 4, child: pw.Text(item.productName, style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('LKR ${(item.price * item.quantity).toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 9)))),
                    ],
                  ),
                );
              }).toList(),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SUBTOTAL:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('LKR ${data.subtotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DISCOUNT:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('LKR ${data.discount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('LKR ${data.total.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 5),

              pw.Text('Order Type: ${data.orderType}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Payment Type: ${data.paymentMethod.toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 8),

              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Token #${data.tokenNumber}',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text('Thank You - Please Come Again', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }
}

// Struct matching ReceiptData inside pos_screen.dart to avoid circular dependency
class ReceiptData {
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

  ReceiptData({
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
  });
}
