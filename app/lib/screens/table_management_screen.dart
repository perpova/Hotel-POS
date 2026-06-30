import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({Key? key}) : super(key: key);

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  final APIService _api = APIService.instance;
  bool _isLoading = false;
  bool _isListView = true; // Default to List View (Management Mode)

  // Filters state
  String _searchQuery = '';
  String _selectedStatus = 'All'; // 'All', 'Active', 'Inactive'
  
  // Pagination
  int _rowsPerPage = 10;
  int _currentPage = 1;

  Color _getTableColor(String status) {
    switch (status) {
      case 'empty':
        return AppTheme.accent; // Green
      case 'seated':
        return AppTheme.danger; // Red
      case 'billing':
        return AppTheme.warning; // Yellow
      default:
        return AppTheme.accent;
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Delete Table
  Future<void> _handleDeleteTable(DiningTableModel table) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Table', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete ${table.tableNumber}? If this table has active or past orders, it will be inactivated instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _api.deleteTable(table.id);
        _showSnackBar('Table deleted/inactivated successfully.', AppTheme.accent);
        
        final posController = Provider.of<POSController>(context, listen: false);
        await posController.reloadEnvironment();
      } catch (e) {
        _showSnackBar('Deletion failed: $e', Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  // Open Add/Edit Drawer Modal
  void _openTableFormDrawer({DiningTableModel? table}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Form',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: const Offset(0, 0),
            ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeInOut)),
            child: Material(
              color: Colors.transparent,
              child: _TableFormDrawer(
                table: table,
                onSave: () async {
                  final posController = Provider.of<POSController>(context, listen: false);
                  await posController.reloadEnvironment();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // Show Seating Bottom Sheet (From original layout)
  void _showTableActionBottomSheet(BuildContext context, DiningTableModel table, POSController controller) {
    final stewardController = TextEditingController();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions for ${table.tableNumber}',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Seating Status: ${table.status.toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: _getTableColor(table.status)),
            ),
            const Divider(height: 24),
            
            if (table.status == 'empty') ...[
              Text(
                'Assign Steward to Table',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stewardController,
                decoration: const InputDecoration(
                  labelText: 'Steward Name',
                  hintText: 'Enter steward name...',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (stewardController.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  try {
                    await _api.updateTableStatus(
                      table.id,
                      'seated',
                      stewardName: stewardController.text.trim(),
                    );
                    await controller.reloadEnvironment();
                  } catch (e) {
                    _showSnackBar('Seating failed: $e', Colors.red);
                  }
                },
                child: const Text('Seat Customers / Seated'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  controller.setOrderType('dine_in');
                  controller.selectTable(table);
                  controller.setStewardName(table.stewardName);
                  _showSnackBar('Table ${table.tableNumber} selected. Open POS System to add items.', AppTheme.accent);
                },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Add Items (Go to POS)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await _api.updateTableStatus(table.id, 'empty');
                    await controller.reloadEnvironment();
                  } catch (e) {
                    _showSnackBar('Clearing failed: $e', Colors.red);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Table (Release Seated)'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    
    // Filter logic
    final filtered = controller.diningTables.where((t) {
      final matchesSearch = t.tableNumber.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus = _selectedStatus == 'All' ||
          (_selectedStatus == 'Active' && t.activeStatus == 'active') ||
          (_selectedStatus == 'Inactive' && t.activeStatus == 'inactive');
      return matchesSearch && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _isListView
              ? _buildListView(filtered)
              : _buildGridView(controller),
    );
  }

  // 1. List View (Table management)
  Widget _buildListView(List<DiningTableModel> filtered) {
    final totalRows = filtered.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    final startIdx = (_currentPage - 1) * _rowsPerPage;
    final endIdx = startIdx + _rowsPerPage > totalRows ? totalRows : startIdx + _rowsPerPage;
    final paginatedList = totalRows > 0 ? filtered.sublist(startIdx, endIdx) : <DiningTableModel>[];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Controls Panel (Search, Status Filter, Export, Add Table, Layout Toggle)
          _buildControlsRow(),
          const SizedBox(height: 24),
          
          // Main Table Card
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 60,
                        columns: [
                          DataColumn(
                            label: Text(
                              'NAME',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'SIZE',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'STATUS',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'ACTION',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                        rows: paginatedList.map((table) {
                          final isActive = table.activeStatus == 'active';
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  table.tableNumber,
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${table.capacity}',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF475569)),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    // Grid Seating Action (opens Seating dialog or toggles to Grid view)
                                    _buildActionIconButton(
                                      icon: Icons.grid_view_outlined,
                                      bgColor: const Color(0xFFFFF9E6),
                                      iconColor: const Color(0xFFFFB300),
                                      onTap: () {
                                        if (isActive) {
                                          _showTableActionBottomSheet(context, table, Provider.of<POSController>(context, listen: false));
                                        } else {
                                          _showSnackBar('Inactive tables cannot be assigned seating.', Colors.red);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    // View Detail Action
                                    _buildActionIconButton(
                                      icon: Icons.remove_red_eye_outlined,
                                      bgColor: const Color(0xFFFFEBF5),
                                      iconColor: AppTheme.primary,
                                      onTap: () => _openTableFormDrawer(table: table),
                                    ),
                                    const SizedBox(width: 8),
                                    // Edit Action
                                    _buildActionIconButton(
                                      icon: Icons.edit_outlined,
                                      bgColor: const Color(0xFFE6FDF4),
                                      iconColor: const Color(0xFF10B981),
                                      onTap: () => _openTableFormDrawer(table: table),
                                    ),
                                    const SizedBox(width: 8),
                                    // Delete Action
                                    _buildActionIconButton(
                                      icon: Icons.delete_outline,
                                      bgColor: const Color(0xFFFEECEE),
                                      iconColor: AppTheme.danger,
                                      onTap: () => _handleDeleteTable(table),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  _buildPaginationFooter(totalRows, startIdx, endIdx, totalPages),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Grid View (Visual Seating Layout)
  Widget _buildGridView(POSController controller) {
    // Only display active tables in Seating Layout
    final activeTables = controller.diningTables.where((t) => t.activeStatus == 'active').toList();
    final isDesktop = MediaQuery.of(context).size.width > 950;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dining Seating Layout',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isListView = true),
                icon: const Icon(Icons.list_alt_outlined, size: 16),
                label: const Text('Back to List'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Status Legend Row
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem('Empty Table', AppTheme.accent),
                  _buildLegendItem('Customers Seated', AppTheme.danger),
                  _buildLegendItem('Processing Bill', AppTheme.warning),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Grid list of tables
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: isDesktop ? 1.25 : 1.15,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: activeTables.length,
              itemBuilder: (context, index) {
                final table = activeTables[index];
                final tableColor = _getTableColor(table.status);
                
                return InkWell(
                  onTap: () => _showTableActionBottomSheet(context, table, controller),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tableColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: tableColor.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              table.tableNumber,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightPrimary,
                              ),
                            ),
                            Icon(
                              Icons.chair_alt,
                              color: tableColor,
                              size: 24,
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (table.status != 'empty') ...[
                              Text(
                                'Steward: ${table.stewardName ?? "N/A"}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textLightPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              table.status.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: tableColor,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Capacity: ${table.capacity}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textLightSecondary,
                              ),
                            ),
                            if (table.currentOrderId != null)
                              const Icon(
                                Icons.receipt_long,
                                size: 16,
                                color: AppTheme.textLightSecondary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
        ),
      ],
    );
  }

  Widget _buildActionIconButton({required IconData icon, required Color bgColor, required Color iconColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: iconColor, size: 16),
      ),
    );
  }

  Widget _buildControlsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        
        final children = [
          // Search Input
          Container(
            width: isCompact ? double.infinity : 260,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
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
                    decoration: const InputDecoration(
                      hintText: 'Search Table...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _currentPage = 1;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Status dropdown filter
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStatus,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All Statuses')),
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedStatus = val;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
          ),

          // Limit row dropdown filter
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10 Rows')),
                  DropdownMenuItem(value: 25, child: Text('25 Rows')),
                  DropdownMenuItem(value: 50, child: Text('50 Rows')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _rowsPerPage = val;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
          ),

          const Spacer(),

          // Seating Grid View Toggle Button
          ElevatedButton.icon(
            onPressed: () => setState(() => _isListView = false),
            icon: const Icon(Icons.grid_view_outlined, size: 16),
            label: const Text('Grid Layout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF64748B),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(120, 40),
              textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),

          // Add Table Button
          ElevatedButton.icon(
            onPressed: () => _openTableFormDrawer(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Tables'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(120, 40),
              textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ];

        if (isCompact) {
          children.removeWhere((w) => w is Spacer);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          );
        } else {
          return Row(
            children: children,
          );
        }
      },
    );
  }

  Widget _buildPaginationFooter(int totalRows, int startIdx, int endIdx, int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            totalRows == 0
                ? 'Showing 0 to 0 of 0 entries'
                : 'Showing ${startIdx + 1} to $endIdx of $totalRows entries',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
          ),
          if (totalPages > 1)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                Row(
                  children: List.generate(totalPages, (index) {
                    final p = index + 1;
                    final isSelected = p == _currentPage;
                    return InkWell(
                      onTap: () => setState(() => _currentPage = p),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFFF0F5) : Colors.transparent,
                          border: isSelected ? Border.all(color: AppTheme.primary, width: 1) : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$p',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppTheme.primary : Color(0xFF64748B),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TableFormDrawer extends StatefulWidget {
  final DiningTableModel? table;
  final VoidCallback onSave;

  const _TableFormDrawer({
    Key? key,
    this.table,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_TableFormDrawer> createState() => _TableFormDrawerState();
}

class _TableFormDrawerState extends State<_TableFormDrawer> {
  final _formKey = GlobalKey<FormState>();
  final APIService _api = APIService.instance;

  late TextEditingController _nameController;
  late TextEditingController _sizeController;
  String _activeStatus = 'active';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final t = widget.table;
    _nameController = TextEditingController(text: t?.tableNumber ?? '');
    _sizeController = TextEditingController(text: t != null ? t.capacity.toString() : '');
    _activeStatus = t?.activeStatus ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final payload = {
      'table_number': _nameController.text.trim(),
      'capacity': int.parse(_sizeController.text),
      'active_status': _activeStatus,
    };

    try {
      if (widget.table != null) {
        await _api.updateTable(widget.table!.id, payload);
      } else {
        await _api.createTable(payload);
      }
      widget.onSave();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save table: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      width: size.width > 500 ? 460 : size.width * 0.85,
      height: size.height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(-4, 0)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.table != null ? 'Edit Table' : 'Add Table',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Drawer Scrollable Fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Table Name
                    _buildLabel('NAME *'),
                    TextFormField(
                      controller: _nameController,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _buildInputDecoration('Enter table name (e.g. Table 1)'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Table name is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Table Size
                    _buildLabel('SIZE *'),
                    TextFormField(
                      controller: _sizeController,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _buildInputDecoration('Enter capacity size (number of seats)'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Size is required';
                        final val = int.tryParse(v);
                        if (val == null || val <= 0) return 'Must be a positive number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Status (Active / Inactive)
                    _buildLabel('STATUS *'),
                    Row(
                      children: [
                        _buildRadioButton('Active', _activeStatus == 'active', (val) {
                          setState(() => _activeStatus = 'active');
                        }),
                        const SizedBox(width: 24),
                        _buildRadioButton('Inactive', _activeStatus == 'inactive', (val) {
                          setState(() => _activeStatus = 'inactive');
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Footer buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitForm,
                      icon: _isSubmitting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        minimumSize: const Size.fromHeight(44),
                        textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(80, 44),
                    ),
                    child: Text('Close', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
      ),
    );
  }

  Widget _buildRadioButton(String label, bool isSelected, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<bool>(
          value: true,
          groupValue: isSelected ? true : null,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.primary),
      ),
    );
  }
}
