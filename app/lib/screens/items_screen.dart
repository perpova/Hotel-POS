import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/sinhala_transliteration.dart';
import '../controllers/pos_controller.dart';
import '../theme.dart';
import '../widgets/image_helper.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({Key? key}) : super(key: key);

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final APIService _api = APIService.instance;
  
  List<ProductModel> _allProducts = [];
  List<CategoryModel> _categories = [];
  List<IngredientModel> _ingredients = [];
  bool _isLoading = false;

  // Search & Filter state
  String _searchQuery = '';
  int? _selectedCategoryId;
  String _selectedStatus = 'All'; // 'All', 'Active', 'Inactive'
  
  // Pagination
  int _rowsPerPage = 10;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final products = await _api.getAllProducts();
      final categories = await _api.getCategories();
      final ingredients = await _api.getIngredients();
      setState(() {
        _allProducts = products;
        _categories = categories;
        _ingredients = ingredients;
      });
    } catch (e) {
      _showSnackBar('Error loading items: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  List<ProductModel> get _filteredProducts {
    return _allProducts.where((p) {
      final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.sinhalaName != null && p.sinhalaName!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          (p.barcode != null && p.barcode!.contains(_searchQuery));
      
      final matchesCategory = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      
      final matchesStatus = _selectedStatus == 'All' ||
          (_selectedStatus == 'Active' && p.status == 'active') ||
          (_selectedStatus == 'Inactive' && p.status == 'inactive');

      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  // Excel Import Operation
  Future<void> _handleImportExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        setState(() => _isLoading = true);
        List<int> bytes;
        final file = result.files.single;
        
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          throw Exception('Could not read file bytes.');
        }

        await _api.importProductsExcel(bytes, file.name);
        _showSnackBar('Items imported and synchronized successfully!', AppTheme.accent);
        
        // Reload environment in provider and local screen state
        final posController = Provider.of<POSController>(context, listen: false);
        await posController.reloadEnvironment();
        await _fetchData();
      }
    } catch (e) {
      _showSnackBar('Excel Import Failed: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Excel Export Operation
  Future<void> _handleExportExcel() async {
    try {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Items Excel List',
        fileName: 'items_export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath != null) {
        setState(() => _isLoading = true);
        final bytes = await _api.downloadProductsExcel();
        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        
        _showSnackBar('Excel exported successfully to $outputPath!', AppTheme.accent);
      }
    } catch (e) {
      _showSnackBar('Excel Export Failed: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Delete/Inactivate Operation
  Future<void> _handleDeleteItem(ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete ${product.name}? If this item has existing sales history, it will be inactivated instead.'),
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
        await _api.deleteProduct(product.id);
        _showSnackBar('Product deleted/deactivated successfully.', AppTheme.accent);
        
        // Sync pos state and reload local list
        final posController = Provider.of<POSController>(context, listen: false);
        await posController.reloadEnvironment();
        await _fetchData();
      } catch (e) {
        _showSnackBar('Deletion failed: $e', Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  // Open Add/Edit Drawer Modal
  void _openItemFormDrawer({ProductModel? product}) {
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
              child: _ItemFormDrawer(
                product: product,
                categories: _categories,
                allProducts: _allProducts,
                ingredients: _ingredients,
                onSave: () async {
                  await _fetchData();
                  // Sync root pos state
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    final totalRows = filtered.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    final startIdx = (_currentPage - 1) * _rowsPerPage;
    final endIdx = startIdx + _rowsPerPage > totalRows ? totalRows : startIdx + _rowsPerPage;
    final paginatedList = totalRows > 0 ? filtered.sublist(startIdx, endIdx) : <ProductModel>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate background
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upper Controls Panel (Search, Filters, Export, Import, Add)
                  _buildControlsRow(),
                  const SizedBox(height: 24),
                  
                  // Main Table
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
                                      'CATEGORY',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'PRICE',
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
                                rows: paginatedList.map((product) {
                                  final cat = _categories.firstWhere(
                                    (c) => c.id == product.categoryId,
                                    orElse: () => CategoryModel(id: 0, name: 'Unknown'),
                                  );
                                  final isActive = product.status == 'active';
                                  
                                  return DataRow(
                                    cells: [
                                      // Product Name
                                      DataCell(
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: const Color(0xFFFFF0F5),
                                              child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
                                                  ? ClipOval(
                                                      child: Base64ImageWidget(
                                                        base64Str: product.imageBase64!,
                                                        width: 36,
                                                        height: 36,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    )
                                                  : Icon(Icons.fastfood_outlined, color: AppTheme.primary, size: 16),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              product.name,
                                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Category
                                      DataCell(
                                        Text(
                                          cat.name,
                                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
                                        ),
                                      ),
                                      // Price
                                      DataCell(
                                        Text(
                                          '${product.price.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                                        ),
                                      ),
                                      // Status Badge
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
                                      // Action Buttons
                                      DataCell(
                                        Row(
                                          children: [
                                            // View Action
                                            _buildActionIconButton(
                                              icon: Icons.remove_red_eye_outlined,
                                              bgColor: const Color(0xFFFFEBF5),
                                              iconColor: AppTheme.primary,
                                              onTap: () => _openItemFormDrawer(product: product),
                                            ),
                                            const SizedBox(width: 8),
                                            // Edit Action
                                            _buildActionIconButton(
                                              icon: Icons.edit_outlined,
                                              bgColor: const Color(0xFFE6FDF4),
                                              iconColor: const Color(0xFF10B981),
                                              onTap: () => _openItemFormDrawer(product: product),
                                            ),
                                            const SizedBox(width: 8),
                                            // Delete Action
                                            _buildActionIconButton(
                                              icon: Icons.delete_outline,
                                              bgColor: const Color(0xFFFEECEE),
                                              iconColor: AppTheme.danger,
                                              onTap: () => _handleDeleteItem(product),
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
                          // Pagination Controls
                          _buildPaginationFooter(totalRows, startIdx, endIdx, totalPages),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
        final isCompact = constraints.maxWidth < 1100;
        
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
                      hintText: 'Search Item...',
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
          
          // Category Filter Dropdown
          _buildDropdownFilter<int?>(
            value: _selectedCategoryId,
            hint: 'Category',
            items: [
              const DropdownMenuItem(value: null, child: Text('All Categories')),
              ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (val) {
              setState(() {
                _selectedCategoryId = val;
                _currentPage = 1;
              });
            },
          ),

          // Status Filter Dropdown
          _buildDropdownFilter<String>(
            value: _selectedStatus,
            hint: 'Status',
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

          // Limit Select Dropdown
          _buildDropdownFilter<int>(
            value: _rowsPerPage,
            hint: 'Limit',
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

          if (!isCompact) const Spacer(),

          // Export Excel Button
          ElevatedButton.icon(
            onPressed: _handleExportExcel,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF64748B),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(100, 40),
              textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),

          // Import Excel Button
          ElevatedButton.icon(
            onPressed: _handleImportExcel,
            icon: const Icon(Icons.download_for_offline_outlined, size: 16),
            label: const Text('Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF64748B),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(100, 40),
              textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),

          // Add Item Button
          ElevatedButton.icon(
            onPressed: () => _openItemFormDrawer(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Item'),
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

  Widget _buildDropdownFilter<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(int totalRows, int startIdx, int endIdx, int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Total Count Text
          Text(
            totalRows == 0
                ? 'Showing 0 to 0 of 0 entries'
                : 'Showing ${startIdx + 1} to $endIdx of $totalRows entries',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
          ),
          
          // Page Navigation Buttons
          if (totalPages > 1)
            Row(
              children: [
                // Prev
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                // Page numbers
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
                // Next
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

class _ItemFormDrawer extends StatefulWidget {
  final ProductModel? product;
  final List<CategoryModel> categories;
  final List<ProductModel> allProducts;
  final List<IngredientModel> ingredients;
  final VoidCallback onSave;

  const _ItemFormDrawer({
    Key? key,
    this.product,
    required this.categories,
    required this.allProducts,
    required this.ingredients,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_ItemFormDrawer> createState() => _ItemFormDrawerState();
}

class _ItemFormDrawerState extends State<_ItemFormDrawer> {
  final _formKey = GlobalKey<FormState>();
  final APIService _api = APIService.instance;

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _sinhalaNameController;
  late TextEditingController _priceController;
  late TextEditingController _taxController;
  late TextEditingController _cautionController;
  late TextEditingController _descriptionController;

  List<CategoryModel> _localCategories = [];
  int? _selectedCategoryId;
  String _itemType = 'Non Veg';
  bool _isFeatured = false;
  String _status = 'active';
  String? _imageBase64;
  bool _isSubmitting = false;

  bool _hasSizes = false;
  bool _hasExtras = false;
  bool _hasAddons = false;
  bool _trackStock = true;
  bool _isHappyHourEligible = true;
  bool _isKotItem = false;

  List<Map<String, dynamic>> _sizesList = [];
  List<Map<String, dynamic>> _extrasList = [];
  List<int> _selectedAddons = [];

  final FocusNode _sinhalaFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _localCategories = List.from(widget.categories);
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _sinhalaNameController = TextEditingController(text: p?.sinhalaName ?? '');
    _priceController = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _taxController = TextEditingController(text: p != null ? p.tax.toStringAsFixed(0) : '0');
    _cautionController = TextEditingController(text: p?.caution ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');

    _selectedCategoryId = p?.categoryId ?? (_localCategories.isNotEmpty ? _localCategories[0].id : null);
    _itemType = p?.itemType ?? 'Non Veg';
    _isFeatured = p?.isFeatured ?? false;
    _status = p?.status ?? 'active';
    _imageBase64 = p?.imageBase64;

    _hasSizes = p?.hasSizes ?? false;
    _hasExtras = p?.hasExtras ?? false;
    _hasAddons = p?.hasAddons ?? false;
    _trackStock = p?.trackStock ?? true;
    _isHappyHourEligible = p?.isHappyHourEligible ?? true;
    _isKotItem = p?.isKotItem ?? false;

    _sizesList = p?.sizes.map<Map<String, dynamic>>((s) => <String, dynamic>{'name': s.name, 'price': s.price}).toList() ?? <Map<String, dynamic>>[];
    _extrasList = p?.extras.map<Map<String, dynamic>>((e) => <String, dynamic>{
      'name': e.name,
      'price': e.price,
      'ingredient_id': e.ingredientId,
      'qty': e.qty,
    }).toList() ?? <Map<String, dynamic>>[];
    _selectedAddons = List<int>.from(p?.addons ?? []);
    _recipeIngredientsList = p?.ingredients.map<Map<String, dynamic>>((ing) => <String, dynamic>{
      'ingredient_id': ing.ingredientId,
      'qty': ing.qty,
      'size': ing.size,
    }).toList() ?? <Map<String, dynamic>>[];

    for (var s in _sizesList) {
      _sizeNameControllers.add(TextEditingController(text: s['name']));
      _sizePriceControllers.add(TextEditingController(text: s['price'] > 0 ? s['price'].toString() : ''));
    }
    for (var e in _extrasList) {
      _extraNameControllers.add(TextEditingController(text: e['name']));
      _extraPriceControllers.add(TextEditingController(text: e['price'] > 0 ? e['price'].toString() : ''));
      _extraQtyControllers.add(TextEditingController(text: e['qty'] != null ? e['qty'].toString() : '1'));
    }
    for (var ing in _recipeIngredientsList) {
      _recipeQtyControllers.add(TextEditingController(text: ing['qty'] > 0 ? ing['qty'].toString() : ''));
    }

    _sinhalaFocusNode.addListener(() {
      if (!_sinhalaFocusNode.hasFocus) {
        final englishText = _sinhalaNameController.text;
        final sinhalaText = SinhalaTransliteration.transliterate(englishText);
        if (sinhalaText.isNotEmpty && englishText.isNotEmpty) {
          setState(() {
            _sinhalaNameController.text = sinhalaText;
          });
        }
      }
    });
  }

  List<TextEditingController> _sizeNameControllers = [];
  List<TextEditingController> _sizePriceControllers = [];

  List<TextEditingController> _extraNameControllers = [];
  List<TextEditingController> _extraPriceControllers = [];
  List<TextEditingController> _extraQtyControllers = [];

  List<Map<String, dynamic>> _recipeIngredientsList = [];
  List<TextEditingController> _recipeQtyControllers = [];

  void _addSizeRow() {
    setState(() {
      _sizesList.add({'name': '', 'price': 0.0});
      _sizeNameControllers.add(TextEditingController());
      _sizePriceControllers.add(TextEditingController());
    });
  }

  void _removeSizeRow(int index) {
    setState(() {
      _sizesList.removeAt(index);
      _sizeNameControllers[index].dispose();
      _sizeNameControllers.removeAt(index);
      _sizePriceControllers[index].dispose();
      _sizePriceControllers.removeAt(index);
    });
  }

  void _addExtraRow() {
    setState(() {
      _extrasList.add({'name': '', 'price': 0.0, 'ingredient_id': null, 'qty': 1.0});
      _extraNameControllers.add(TextEditingController());
      _extraPriceControllers.add(TextEditingController());
      _extraQtyControllers.add(TextEditingController(text: '1'));
    });
  }

  void _removeExtraRow(int index) {
    setState(() {
      _extrasList.removeAt(index);
      _extraNameControllers[index].dispose();
      _extraNameControllers.removeAt(index);
      _extraPriceControllers[index].dispose();
      _extraPriceControllers.removeAt(index);
      _extraQtyControllers[index].dispose();
      _extraQtyControllers.removeAt(index);
    });
  }

  void _addRecipeIngredientRow() {
    setState(() {
      _recipeIngredientsList.add({'ingredient_id': null, 'qty': 0.0, 'size': null});
      _recipeQtyControllers.add(TextEditingController());
    });
  }

  void _removeRecipeIngredientRow(int index) {
    setState(() {
      _recipeIngredientsList.removeAt(index);
      _recipeQtyControllers[index].dispose();
      _recipeQtyControllers.removeAt(index);
    });
  }

  List<String> _getActiveSizeNames() {
    final names = <String>[];
    for (int i = 0; i < _sizesList.length; i++) {
      if (i < _sizeNameControllers.length) {
        final name = _sizeNameControllers[i].text.trim();
        if (name.isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sinhalaNameController.dispose();
    _priceController.dispose();
    _taxController.dispose();
    _cautionController.dispose();
    _descriptionController.dispose();
    _sinhalaFocusNode.dispose();
    for (var c in _sizeNameControllers) c.dispose();
    for (var c in _sizePriceControllers) c.dispose();
    for (var c in _extraNameControllers) c.dispose();
    for (var c in _extraPriceControllers) c.dispose();
    for (var c in _extraQtyControllers) c.dispose();
    for (var c in _recipeQtyControllers) c.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        List<int> bytes;
        final file = result.files.single;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          return;
        }
        setState(() {
          _imageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddCategoryDialog() {
    final TextEditingController categoryNameController = TextEditingController();
    String? categoryImageBase64;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Create Category', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: categoryNameController,
                decoration: const InputDecoration(
                  hintText: 'Enter category name',
                  labelText: 'Category Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Category Image',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: categoryImageBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Base64ImageWidget(
                              base64Str: categoryImageBase64!,
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.category_outlined, color: Color(0xFF94A3B8), size: 30),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (result != null) {
                              List<int> bytes;
                              final file = result.files.single;
                              if (file.bytes != null) {
                                bytes = file.bytes!;
                              } else if (file.path != null) {
                                bytes = await File(file.path!).readAsBytes();
                              } else {
                                return;
                              }
                              setStateDialog(() {
                                categoryImageBase64 = base64Encode(bytes);
                              });
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                        icon: const Icon(Icons.image_search, size: 16),
                        label: const Text('Pick Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF64748B),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      if (categoryImageBase64 != null) ...[
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () {
                            setStateDialog(() {
                              categoryImageBase64 = null;
                            });
                          },
                          icon: const Icon(Icons.delete_outline, size: 14, color: AppTheme.danger),
                          label: const Text('Remove', style: TextStyle(fontSize: 12, color: AppTheme.danger)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        ),
                      ],
                    ],
                  ),
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
              onPressed: () async {
                final name = categoryNameController.text.trim();
                if (name.isEmpty) return;
                try {
                  final newCat = await _api.createCategory({
                    'name': name,
                    'image_base64': categoryImageBase64,
                  });
                  setState(() {
                    _localCategories.add(newCat);
                    _selectedCategoryId = newCat.id;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category "$name" created successfully!'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create category: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Category'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    double productPrice = 0.0;
    if (_hasSizes) {
      if (_sizePriceControllers.isNotEmpty) {
        productPrice = double.tryParse(_sizePriceControllers[0].text) ?? 0.0;
      }
    } else {
      productPrice = double.tryParse(_priceController.text) ?? 0.0;
    }

    final sizes = <Map<String, dynamic>>[];
    if (_hasSizes) {
      for (int i = 0; i < _sizesList.length; i++) {
        sizes.add({
          'name': _sizeNameControllers[i].text.trim(),
          'price': double.tryParse(_sizePriceControllers[i].text) ?? 0.0,
        });
      }
    }

    final extras = <Map<String, dynamic>>[];
    if (_hasExtras) {
      for (int i = 0; i < _extrasList.length; i++) {
        extras.add({
          'name': _extraNameControllers[i].text.trim(),
          'price': double.tryParse(_extraPriceControllers[i].text) ?? 0.0,
          'ingredient_id': _extrasList[i]['ingredient_id'],
          'qty': double.tryParse(_extraQtyControllers[i].text) ?? 1.0,
        });
      }
    }

    final recipeIngredients = <Map<String, dynamic>>[];
    for (int i = 0; i < _recipeIngredientsList.length; i++) {
      final ing = _recipeIngredientsList[i];
      if (ing['ingredient_id'] != null) {
        recipeIngredients.add({
          'ingredient_id': ing['ingredient_id'],
          'qty': double.tryParse(_recipeQtyControllers[i].text) ?? 0.0,
          'size': ing['size'],
        });
      }
    }

    final payload = {
      'name': _nameController.text.trim(),
      'sinhala_name': _sinhalaNameController.text.trim().isEmpty ? null : _sinhalaNameController.text.trim(),
      'category_id': _selectedCategoryId,
      'price': productPrice,
      'cost': productPrice * 0.6, // auto cost
      'tax': double.tryParse(_taxController.text) ?? 0.0,
      'item_type': _itemType,
      'is_featured': _isFeatured ? 1 : 0,
      'status': _status,
      'caution': _cautionController.text.trim().isEmpty ? null : _cautionController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'image_base64': _imageBase64,
      'has_sizes': _hasSizes ? 1 : 0,
      'has_extras': _hasExtras ? 1 : 0,
      'has_addons': _hasAddons ? 1 : 0,
      'track_stock': _trackStock ? 1 : 0,
      'is_happy_hour_eligible': _isHappyHourEligible ? 1 : 0,
      'is_kot_item': _isKotItem ? 1 : 0,
      'sizes': sizes,
      'extras': extras,
      'addons': _hasAddons ? _selectedAddons : [],
      'ingredients': recipeIngredients,
    };

    try {
      if (widget.product != null) {
        // Edit mode
        await _api.updateProduct(widget.product!.id, payload);
      } else {
        // Add mode
        await _api.createProduct(payload);
      }
      widget.onSave();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save product: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('NAME *'),
        TextFormField(
          controller: _nameController,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _buildInputDecoration('Enter product name'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
        ),
      ],
    );
  }

  Widget _buildSinhalaNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('SINHALA NAME (SINGLISH PHONETIC TYPE-ON-THE-FLY)'),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _sinhalaNameController,
          builder: (context, value, _) {
            final preview = SinhalaTransliteration.transliterate(value.text);
            final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(value.text);
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _sinhalaNameController,
                  focusNode: _sinhalaFocusNode,
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _buildInputDecoration(
                    'e.g. Type "koththu" here to get "කොත්තු"',
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.translate, size: 16),
                      tooltip: 'Convert to Sinhala now',
                      onPressed: () {
                        final englishText = _sinhalaNameController.text;
                        final sinhalaText = SinhalaTransliteration.transliterate(englishText);
                        if (sinhalaText.isNotEmpty) {
                          setState(() {
                            _sinhalaNameController.text = sinhalaText;
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (hasEnglish && preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Sinhala Preview: ',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      Text(
                        preview,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('PRICE *'),
        TextFormField(
          controller: _priceController,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _buildInputDecoration('Enter price'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if (_hasSizes) return null;
            if (v == null || v.trim().isEmpty) return 'Price is required';
            if (double.tryParse(v) == null) return 'Invalid number';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('CATEGORY *'),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedCategoryId,
                    hint: const Text('Select category', style: TextStyle(fontSize: 13)),
                    isExpanded: true,
                    items: _localCategories.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name, style: GoogleFonts.inter(fontSize: 13)));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCategoryId = val;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 16),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(12),
              ),
              tooltip: 'Add New Category',
              onPressed: () => _showAddCategoryDialog(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaxField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('TAX (INCLUDING)'),
        TextFormField(
          controller: _taxController,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _buildInputDecoration('Enter tax %'),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
              return 'Invalid number';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildImageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('IMAGE'),
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFF1F5F9),
              child: _imageBase64 != null && _imageBase64!.isNotEmpty
                  ? ClipOval(
                      child: Base64ImageWidget(
                        base64Str: _imageBase64!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(Icons.image_outlined, color: Color(0xFF64748B), size: 24),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: _pickImage,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Choose File', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomizationOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('POS CUSTOMIZATION OPTIONS'),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _hasSizes,
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() => _hasSizes = val ?? false);
                  },
                ),
                Text('Sizes', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _hasExtras,
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() => _hasExtras = val ?? false);
                  },
                ),
                Text('Extras', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _hasAddons,
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() => _hasAddons = val ?? false);
                  },
                ),
                Text('Addons', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInventorySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('POS INVENTORY SETTINGS'),
        Row(
          children: [
            Checkbox(
              value: _trackStock,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                setState(() => _trackStock = val ?? false);
              },
            ),
            Text('Track Stock Level in POS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildHappyHourSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('HAPPY HOUR SETTINGS'),
        Row(
          children: [
            Checkbox(
              value: _isHappyHourEligible,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                setState(() => _isHappyHourEligible = val ?? true);
              },
            ),
            Text('Available for Happy Hour Offer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildKOTSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('KOT SETTINGS'),
        Row(
          children: [
            Checkbox(
              value: _isKotItem,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                setState(() => _isKotItem = val ?? false);
              },
            ),
            Text('Prepare in Kitchen (Show in KOT)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildItemTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('ITEM TYPE'),
        Row(
          children: [
            _buildRadioButton('Veg', _itemType == 'Veg', (val) {
              setState(() => _itemType = 'Veg');
            }),
            const SizedBox(width: 24),
            _buildRadioButton('Non Veg', _itemType == 'Non Veg', (val) {
              setState(() => _itemType = 'Non Veg');
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildIsFeaturedField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('IS FEATURED'),
        Row(
          children: [
            _buildRadioButton('Yes', _isFeatured == true, (val) {
              setState(() => _isFeatured = true);
            }),
            const SizedBox(width: 24),
            _buildRadioButton('No', _isFeatured == false, (val) {
              setState(() => _isFeatured = false);
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('STATUS'),
        Row(
          children: [
            _buildRadioButton('Active', _status == 'active', (val) {
              setState(() => _status = 'active');
            }),
            const SizedBox(width: 24),
            _buildRadioButton('Inactive', _status == 'inactive', (val) {
              setState(() => _status = 'inactive');
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildCautionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('CAUTION'),
        TextFormField(
          controller: _cautionController,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _buildInputDecoration('Enter caution guidelines'),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('DESCRIPTION'),
        TextFormField(
          controller: _descriptionController,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _buildInputDecoration('Enter description'),
          maxLines: 3,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 900;
    final drawerWidth = isWide ? size.width * 0.5 : (size.width > 500 ? 460.0 : size.width * 0.85);

    return Container(
      width: drawerWidth,
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
                    widget.product != null ? 'Edit Product' : 'Add Product',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Drawer Scrollable Form Fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildNameField(),
                                const SizedBox(height: 16),
                                _buildSinhalaNameField(),
                                const SizedBox(height: 16),
                                _buildCategoryField(),
                                const SizedBox(height: 16),
                                _buildImageField(),
                                const SizedBox(height: 16),
                                _buildItemTypeField(),
                                const SizedBox(height: 16),
                                _buildIsFeaturedField(),
                                const SizedBox(height: 16),
                                _buildStatusField(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Right Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!_hasSizes) ...[
                                  _buildPriceField(),
                                  const SizedBox(height: 16),
                                ],
                                _buildTaxField(),
                                const SizedBox(height: 16),
                                _buildCustomizationOptions(),
                                const SizedBox(height: 16),
                                _buildInventorySettings(),
                                const SizedBox(height: 16),
                                _buildKOTSettings(),
                                const SizedBox(height: 16),
                                _buildHappyHourSettings(),
                                const SizedBox(height: 16),
                                _buildCautionField(),
                                const SizedBox(height: 16),
                                _buildDescriptionField(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildNameField(),
                      const SizedBox(height: 16),
                      _buildSinhalaNameField(),
                      const SizedBox(height: 16),
                      if (!_hasSizes) ...[
                        _buildPriceField(),
                        const SizedBox(height: 16),
                      ],
                      _buildCategoryField(),
                      const SizedBox(height: 16),
                      _buildTaxField(),
                      const SizedBox(height: 16),
                      _buildImageField(),
                      const SizedBox(height: 16),
                      _buildCustomizationOptions(),
                      const SizedBox(height: 16),
                      _buildInventorySettings(),
                      const SizedBox(height: 16),
                      _buildKOTSettings(),
                      const SizedBox(height: 16),
                      _buildHappyHourSettings(),
                      const SizedBox(height: 16),
                      _buildItemTypeField(),
                      const SizedBox(height: 16),
                      _buildIsFeaturedField(),
                      const SizedBox(height: 16),
                      _buildStatusField(),
                      const SizedBox(height: 16),
                      _buildCautionField(),
                      const SizedBox(height: 16),
                      _buildDescriptionField(),
                    ],
                    
                    const SizedBox(height: 16),

                    if (_hasSizes) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLabel('SIZES CONFIGURATION'),
                          TextButton.icon(
                            onPressed: _addSizeRow,
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add Size', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      if (_sizesList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No sizes added. Click "Add Size" to configure.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        ...List.generate(_sizesList.length, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _sizeNameControllers[index],
                                    style: GoogleFonts.inter(fontSize: 12),
                                    decoration: _buildInputDecoration('Size Name (e.g. Regular)'),
                                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _sizePriceControllers[index],
                                    style: GoogleFonts.inter(fontSize: 12),
                                    decoration: _buildInputDecoration('Price (e.g. 500)'),
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Required';
                                      if (double.tryParse(v) == null) return 'Invalid';
                                      return null;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                  onPressed: () => _removeSizeRow(index),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                    ],

                    if (_hasExtras) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLabel('EXTRAS CONFIGURATION'),
                          TextButton.icon(
                            onPressed: _addExtraRow,
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add Extra', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      if (_extrasList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No extras added. Click "Add Extra" to configure.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        ...List.generate(_extrasList.length, (index) {
                          final ex = _extrasList[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: _extraNameControllers[index],
                                        style: GoogleFonts.inter(fontSize: 12),
                                        decoration: _buildInputDecoration('Extra Name (e.g. Extra Egg)'),
                                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _extraPriceControllers[index],
                                        style: GoogleFonts.inter(fontSize: 12),
                                        decoration: _buildInputDecoration('Price (e.g. 100)'),
                                        keyboardType: TextInputType.number,
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return 'Required';
                                          if (double.tryParse(v) == null) return 'Invalid';
                                          return null;
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                      onPressed: () => _removeExtraRow(index),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Container(
                                        height: 38,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFCBD5E1)),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<int?>(
                                            value: ex['ingredient_id'],
                                            hint: const Text('No Linked Ingredient', style: TextStyle(fontSize: 11)),
                                            isExpanded: true,
                                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF1E293B)),
                                            items: [
                                              const DropdownMenuItem<int?>(
                                                value: null,
                                                child: Text('No Linked Ingredient', style: TextStyle(fontSize: 11)),
                                              ),
                                              ...widget.ingredients.map((ing) {
                                                return DropdownMenuItem<int?>(
                                                  value: ing.id,
                                                  child: Text('${ing.name} (${ing.unit})', style: const TextStyle(fontSize: 11)),
                                                );
                                              }),
                                            ],
                                            onChanged: (val) {
                                              setState(() {
                                                ex['ingredient_id'] = val;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _extraQtyControllers[index],
                                        style: GoogleFonts.inter(fontSize: 12),
                                        decoration: _buildInputDecoration('Qty to deduct'),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        validator: (v) {
                                          if (ex['ingredient_id'] != null) {
                                            if (v == null || v.trim().isEmpty) return 'Required';
                                            if (double.tryParse(v) == null) return 'Invalid';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 32), // space aligning with delete button
                                  ],
                                ),
                                const Divider(height: 12, color: Color(0xFFE2E8F0)),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                    ],

                    if (_hasAddons) ...[
                      _buildLabel('SELECT DRINK ADDONS'),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                           color: const Color(0xFFF8FAFC),
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: () {
                            final drinksCat = widget.categories.firstWhere(
                              (c) => c.name.toLowerCase() == 'drinks',
                              orElse: () => CategoryModel(id: 0, name: ''),
                            );
                            final drinksProducts = widget.allProducts.where((p) => p.categoryId == drinksCat.id).toList();
                            if (drinksProducts.isEmpty) {
                              return [
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text('No drink items found in catalog.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic)),
                                )
                              ];
                            }
                            return drinksProducts.map((p) {
                              final isChecked = _selectedAddons.contains(p.id);
                              return CheckboxListTile(
                                title: Text(p.name, style: GoogleFonts.inter(fontSize: 12)),
                                secondary: Text('LKR ${p.price.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                value: isChecked,
                                activeColor: AppTheme.primary,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedAddons.add(p.id);
                                    } else {
                                      _selectedAddons.remove(p.id);
                                    }
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                dense: true,
                              );
                            }).toList();
                          }(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildLabel('PRODUCT RECIPE (RAW MATERIALS)'),
                        TextButton.icon(
                          onPressed: _addRecipeIngredientRow,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Ingredient', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    if (_recipeIngredientsList.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No ingredients linked. Click "Add Ingredient" to configure recipe.',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                        ),
                      )
                    else
                      ...List.generate(_recipeIngredientsList.length, (index) {
                        final item = _recipeIngredientsList[index];
                        final activeSizes = _getActiveSizeNames();
                        final String? currentSize = item['size'];
                        final dropdownItems = [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Sizes', style: TextStyle(fontSize: 11)),
                          ),
                          ...activeSizes.map((name) {
                            return DropdownMenuItem<String?>(
                              value: name,
                              child: Text(name, style: const TextStyle(fontSize: 11)),
                            );
                          }),
                        ];
                        if (currentSize != null && !activeSizes.contains(currentSize)) {
                          dropdownItems.add(
                            DropdownMenuItem<String?>(
                              value: currentSize,
                              child: Text(currentSize, style: const TextStyle(fontSize: 11)),
                            )
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      value: item['ingredient_id'],
                                      hint: const Text('Select Ingredient', style: TextStyle(fontSize: 11)),
                                      isExpanded: true,
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)),
                                      items: widget.ingredients.map((ing) {
                                        return DropdownMenuItem<int?>(
                                          value: ing.id,
                                          child: Text('${ing.name} (${ing.unit})', style: const TextStyle(fontSize: 11)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          item['ingredient_id'] = val;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (_hasSizes) ...[
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String?>(
                                        value: currentSize,
                                        hint: const Text('All Sizes', style: TextStyle(fontSize: 11)),
                                        isExpanded: true,
                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)),
                                        items: dropdownItems,
                                        onChanged: (val) {
                                          setState(() {
                                            item['size'] = val;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _recipeQtyControllers[index],
                                  style: GoogleFonts.inter(fontSize: 11),
                                  decoration: _buildInputDecoration('Qty (e.g. 0.2)'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (v) {
                                    if (item['ingredient_id'] != null) {
                                      if (v == null || v.trim().isEmpty) return 'Req';
                                      if (double.tryParse(v) == null) return 'Inv';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                onPressed: () => _removeRecipeIngredientRow(index),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            
            // Drawer Footer Action Buttons
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
