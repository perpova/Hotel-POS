import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/image_helper.dart';

class UsersScreen extends StatefulWidget {
  final String userType; // 'Administrators', 'Delivery Boys', 'Customers', 'Employees', 'Waiters', 'Chefs'
  
  const UsersScreen({Key? key, required this.userType}) : super(key: key);

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _items = []; // Can be List<UserModel> or List<CustomerModel>
  List<CategoryModel> _categories = [];
  Map<int, String> _ingredientNames = {};
  bool _isLoading = false;
  String _errorMessage = '';

  // Search & Advanced Filters
  String _searchQuery = '';
  bool _isFilterExpanded = false;
  final _filterNameController = TextEditingController();
  final _filterEmailController = TextEditingController();
  final _filterPhoneController = TextEditingController();
  String _filterStatus = '--'; // '--', 'active', 'inactive'

  // Applied Filters State
  String _appliedName = '';
  String _appliedEmail = '';
  String _appliedPhone = '';
  String _appliedStatus = '--';

  // Drawer / Form State
  bool _isDrawerOpen = false;
  dynamic _editingItem; // UserModel or CustomerModel, null means adding new

  // Profile Detail Viewing State
  dynamic _viewingItem; // UserModel or CustomerModel, null means showing list
  int _activeTab = 0; // 0 = Profile, 1 = Security, 2 = Address, 3 = My Orders
  List<AddressModel> _addresses = [];
  bool _loadingAddresses = false;
  List<OrderModel> _userOrders = [];
  List<OrderModel> _rawUserOrders = [];
  List<Map<String, dynamic>> _preparedItems = [];
  bool _loadingOrders = false;

  // Orders history filters
  String _ordersFilterPreset = 'all'; // 'all', 'daily', 'weekly', 'monthly', 'single', 'custom'
  DateTime? _ordersFilterStartDate;
  DateTime? _ordersFilterEndDate;
  DateTime? _ordersFilterSingleDate;

  // Form Keys
  final _userFormKey = GlobalKey<FormState>();
  final _customerFormKey = GlobalKey<FormState>();

  // System User Controllers
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _roleVal = 'admin';
  String _statusVal = 'active';
  String _branchVal = 'current'; // 'current' or 'all'
  int? _selectedCategoryId;

  // Customer Controllers
  final _custNameController = TextEditingController();
  final _custPhoneController = TextEditingController();
  final _custEmailController = TextEditingController();
  final _custBirthdayController = TextEditingController();
  final _custCreditLimitController = TextEditingController();
  final _custBalanceController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant UsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userType != widget.userType) {
      _closeDrawer();
      _viewingItem = null;
      _loadData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _custNameController.dispose();
    _custPhoneController.dispose();
    _custEmailController.dispose();
    _custBirthdayController.dispose();
    _custCreditLimitController.dispose();
    _custBalanceController.dispose();
    _filterNameController.dispose();
    _filterEmailController.dispose();
    _filterPhoneController.dispose();
    super.dispose();
  }

  bool get _isCustomerType => widget.userType == 'Customers';

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      try {
        _categories = await APIService.instance.getCategories();
      } catch (_) {}
      try {
        final ings = await APIService.instance.getIngredients();
        _ingredientNames = {for (var i in ings) i.id: i.name};
      } catch (_) {}

      if (_isCustomerType) {
        final custs = await APIService.instance.getCustomers();
        if (mounted) {
          setState(() {
            _items = custs;
            _isLoading = false;
          });
        }
      } else {
        // Map userType to role filter
        String? roleFilter;
        if (widget.userType == 'Administrators') {
          roleFilter = 'admin_owner';
        } else if (widget.userType == 'Delivery Boys') {
          roleFilter = 'delivery';
        } else if (widget.userType == 'Employees') {
          roleFilter = 'cashier';
        } else if (widget.userType == 'Waiters') {
          roleFilter = 'waiter';
        } else if (widget.userType == 'Chefs') {
          roleFilter = 'kitchen';
        }

        final users = await APIService.instance.getUsers(role: roleFilter);
        if (mounted) {
          setState(() {
            _items = users;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Load addresses for a user/customer
  Future<void> _loadAddresses(dynamic item) async {
    setState(() {
      _loadingAddresses = true;
      _addresses = [];
    });
    try {
      final isCust = item is CustomerModel;
      final id = isCust ? item.id : (item as UserModel).id;
      final addrs = await APIService.instance.getAddresses(id, isCustomer: isCust);
      if (mounted) {
        setState(() {
          _addresses = addrs;
          _loadingAddresses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAddresses = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load addresses: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Load orders for a user/customer
  Future<void> _loadOrders(dynamic item) async {
    setState(() {
      _loadingOrders = true;
      _userOrders = [];
      _rawUserOrders = [];
      _preparedItems = [];
      _ordersFilterPreset = 'all';
      _ordersFilterStartDate = null;
      _ordersFilterEndDate = null;
      _ordersFilterSingleDate = null;
    });
    try {
      final isCust = item is CustomerModel;
      final id = isCust ? item.id : (item as UserModel).id;
      
      if (!isCust && (item as UserModel).role.toLowerCase() == 'kitchen') {
        final prepared = await APIService.instance.getPreparedItems(id);
        if (mounted) {
          setState(() {
            _preparedItems = prepared;
            _loadingOrders = false;
          });
        }
      } else {
        final allOrders = await APIService.instance.getOrders();
        final filtered = allOrders.where((o) {
          if (isCust) {
            return o.customerId == id;
          } else {
            final user = item as UserModel;
            if (user.role.toLowerCase() == 'waiter') {
              return o.stewardName != null && o.stewardName!.toLowerCase() == user.name.toLowerCase();
            }
            return o.cashierId == id;
          }
        }).toList();
        
        if (mounted) {
          setState(() {
            _rawUserOrders = filtered;
            _userOrders = filtered;
            _loadingOrders = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingOrders = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load orders: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Open Add/Edit Drawer
  void _openDrawer([dynamic item]) {
    setState(() {
      _editingItem = item;
      _isDrawerOpen = true;
      _selectedCategoryId = null;

      if (_isCustomerType) {
        if (item != null && item is CustomerModel) {
          _custNameController.text = item.name;
          _custPhoneController.text = item.phone;
          _custEmailController.text = item.email ?? '';
          _custBirthdayController.text = item.birthday ?? '';
          _custCreditLimitController.text = item.creditLimit.toStringAsFixed(0);
          _custBalanceController.text = item.outstandingBalance.toStringAsFixed(0);
        } else {
          _custNameController.clear();
          _custPhoneController.clear();
          _custEmailController.clear();
          _custBirthdayController.clear();
          _custCreditLimitController.text = '0';
          _custBalanceController.text = '0';
        }
      } else {
        if (item != null && item is UserModel) {
          _nameController.text = item.name;
          _usernameController.text = item.username;
          _emailController.text = item.email ?? '';
          _phoneController.text = item.phone ?? '';
          _passwordController.clear();
          _roleVal = item.role;
          _statusVal = item.status;
          _branchVal = item.branch;
          _selectedCategoryId = item.categoryId;
        } else {
          _nameController.clear();
          _usernameController.clear();
          _emailController.clear();
          _phoneController.clear();
          _passwordController.clear();
          _statusVal = 'active';
          _branchVal = 'current';
          
          // Set default role based on userType
          if (widget.userType == 'Administrators') {
            _roleVal = 'admin';
          } else if (widget.userType == 'Delivery Boys') {
            _roleVal = 'delivery';
          } else if (widget.userType == 'Employees') {
            _roleVal = 'cashier';
          } else if (widget.userType == 'Waiters') {
            _roleVal = 'waiter';
          } else if (widget.userType == 'Chefs') {
            _roleVal = 'kitchen';
          }
        }
      }
    });
  }

  // Close Drawer
  void _closeDrawer() {
    setState(() {
      _isDrawerOpen = false;
      _editingItem = null;
    });
  }

  // Save changes
  Future<void> _save() async {
    if (_isCustomerType) {
      if (!_customerFormKey.currentState!.validate()) return;
      
      setState(() => _isSaving = true);
      
      final payload = {
        'name': _custNameController.text.trim(),
        'phone': _custPhoneController.text.trim(),
        'email': _custEmailController.text.trim().isEmpty ? null : _custEmailController.text.trim(),
        'birthday': _custBirthdayController.text.trim().isEmpty ? null : _custBirthdayController.text.trim(),
        'credit_limit': double.tryParse(_custCreditLimitController.text) ?? 0.0,
        'outstanding_balance': double.tryParse(_custBalanceController.text) ?? 0.0,
      };

      try {
        if (_editingItem == null) {
          await APIService.instance.createCustomer(payload);
        } else if (_editingItem is CustomerModel) {
          await APIService.instance.updateCustomer(_editingItem.id, payload);
        }
        _closeDrawer();
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer saved successfully'), backgroundColor: AppTheme.accent),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      } finally {
        setState(() => _isSaving = false);
      }
    } else {
      if (!_userFormKey.currentState!.validate()) return;
      
      setState(() => _isSaving = true);

      final payload = {
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'role': _roleVal,
        'status': _statusVal,
        'branch': _branchVal,
        'category_id': _selectedCategoryId,
      };

      if (_editingItem == null) {
        payload['password'] = _passwordController.text;
      }

      try {
        if (_editingItem == null) {
          await APIService.instance.createUser(payload);
        } else if (_editingItem is UserModel) {
          await APIService.instance.updateUser(_editingItem.id, payload);
        }
        _closeDrawer();
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User saved successfully'), backgroundColor: AppTheme.accent),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  // Delete/Deactivate
  Future<void> _deleteItem(dynamic item) async {
    String name = '';
    bool isUser = true;
    if (item is CustomerModel) {
      name = item.name;
      isUser = false;
    } else if (item is UserModel) {
      name = item.name;
      isUser = true;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isUser ? 'Deactivate User' : 'Delete Customer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to ${isUser ? "deactivate" : "delete"} "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(isUser ? 'Deactivate' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (item is CustomerModel) {
          await APIService.instance.deleteCustomer(item.id);
        } else if (item is UserModel) {
          await APIService.instance.deleteUser(item.id);
        }
        await _loadData();
        if (_viewingItem != null) {
          setState(() {
            _viewingItem = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully completed action'), backgroundColor: AppTheme.accent),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Export to CSV file
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Name,Email,Phone,Status\n';
      for (var item in _filteredItems) {
        String name = '';
        String email = '';
        String phone = '';
        String status = '';
        if (item is CustomerModel) {
          name = item.name;
          email = item.email ?? 'N/A';
          phone = item.phone;
          status = 'Active';
        } else if (item is UserModel) {
          name = item.name;
          email = item.email ?? item.username;
          phone = item.phone ?? 'N/A';
          status = item.status;
        }
        // Clean formatting
        name = name.replaceAll(',', ' ');
        email = email.replaceAll(',', ' ');
        phone = phone.replaceAll(',', ' ');
        csvContent += '$name,$email,$phone,$status\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Users List',
        fileName: '${widget.userType.replaceAll(" ", "_")}_list.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsString(csvContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported successfully to: $resultPath'), backgroundColor: AppTheme.accent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Export PDF file download
  Future<void> _exportToPDF() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Name', 'Email', 'Phone', 'Status'];
      final data = _filteredItems.map((item) {
        if (item is CustomerModel) {
          return [item.name, item.email ?? 'N/A', item.phone, 'Active'];
        } else {
          final u = item as UserModel;
          return [u.name, u.email ?? u.username, u.phone ?? 'N/A', u.status];
        }
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  widget.userType,
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 30,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF Report',
        fileName: '${widget.userType.replaceAll(" ", "_")}_list.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsBytes(await doc.save());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF saved successfully to: $resultPath'), backgroundColor: AppTheme.accent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export PDF failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Print list table to PDF layout
  Future<void> _printList() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Name', 'Email', 'Phone', 'Status'];
      final data = _filteredItems.map((item) {
        if (item is CustomerModel) {
          return [item.name, item.email ?? 'N/A', item.phone, 'Active'];
        } else {
          final u = item as UserModel;
          return [u.name, u.email ?? u.username, u.phone ?? 'N/A', u.status];
        }
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  widget.userType,
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 30,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '${widget.userType.replaceAll(" ", "_")}_list',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Handle viewing item details
  void _viewDetails(dynamic item) {
    setState(() {
      _viewingItem = item;
      _activeTab = 0;
    });
    _loadAddresses(item);
    _loadOrders(item);
  }

  // Pick Profile Picture
  Future<void> _uploadProfilePicture() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);

        setState(() {
          _isSaving = true;
        });

        if (_viewingItem is CustomerModel) {
          final updated = await APIService.instance.updateCustomer(
            _viewingItem.id,
            {'image_base64': base64Str},
          );
          setState(() {
            _viewingItem = updated;
          });
        } else if (_viewingItem is UserModel) {
          final updated = await APIService.instance.updateUser(
            _viewingItem.id,
            {'image_base64': base64Str},
          );
          setState(() {
            _viewingItem = updated;
          });
        }
        
        await _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully.'), backgroundColor: AppTheme.accent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload photo: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Reset password dialog for system users
  Future<void> _showPasswordResetDialog(UserModel user) async {
    final passwordController = TextEditingController();
    final resetFormKey = GlobalKey<FormState>();
    bool isResetting = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Reset Password for ${user.username}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Form(
              key: resetFormKey,
              child: TextFormField(
                controller: passwordController,
                obscureText: true,
                validator: (val) => val == null || val.length < 4 ? 'Password must be at least 4 characters' : null,
                decoration: const InputDecoration(labelText: 'New Secure Password'),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isResetting ? null : () async {
                  if (!resetFormKey.currentState!.validate()) return;
                  setDialogState(() => isResetting = true);
                  try {
                    await APIService.instance.resetUserPassword(user.id, passwordController.text);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password updated successfully'), backgroundColor: AppTheme.accent),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  } finally {
                    setDialogState(() => isResetting = false);
                  }
                },
                child: isResetting 
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Reset Password'),
              ),
            ],
          );
        }
      ),
    );
  }

  // Select Date picker for Customer Birthday
  Future<void> _selectBirthday() async {
    DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 25));
    if (_custBirthdayController.text.isNotEmpty) {
      initial = DateTime.tryParse(_custBirthdayController.text) ?? initial;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _custBirthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Add Address Dialog using Google Static Map location finder
  void _showAddAddressDialog() {
    final searchController = TextEditingController(text: 'Matara, Sri Lanka');
    final detailController = TextEditingController();
    String searchLocation = 'Matara, Sri Lanka';
    String labelValue = 'Home';
    bool isSavingAddress = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final staticMapUrl = 'https://maps.googleapis.com/maps/api/staticmap'
              '?center=${Uri.encodeComponent(searchLocation)}'
              '&zoom=15'
              '&size=500x300'
              '&markers=color:red%7C${Uri.encodeComponent(searchLocation)}'
              '&key=AIzaSyBWaQI-_zWwmwazesDM7M6FReCVtixiTuc';

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 550,
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add Location / Address', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(height: 24),
                    
                    // Search Bar
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: 'Enter a location',
                              hintText: 'e.g. Matara, Sri Lanka',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (searchController.text.trim().isNotEmpty) {
                              setDialogState(() {
                                searchLocation = searchController.text.trim();
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Map Container
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        color: Colors.grey[200],
                        child: Image.network(
                          staticMapUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Text('Map Loading...'));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Apartment
                    TextFormField(
                      controller: detailController,
                      validator: (val) => val == null || val.isEmpty ? 'Address is required' : null,
                      decoration: const InputDecoration(
                        labelText: 'APARTMENT / STREET ADDRESS *',
                        hintText: 'e.g. Apartment 4B, Matara, Sri Lanka',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Label Radio buttons
                    _buildFieldLabel('LABEL *'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Radio<String>(
                          value: 'Home',
                          groupValue: labelValue,
                          activeColor: AppTheme.primary,
                          onChanged: (val) => setDialogState(() => labelValue = val!),
                        ),
                        Text('Home', style: GoogleFonts.inter(fontSize: 13)),
                        const SizedBox(width: 20),
                        Radio<String>(
                          value: 'Work',
                          groupValue: labelValue,
                          activeColor: AppTheme.primary,
                          onChanged: (val) => setDialogState(() => labelValue = val!),
                        ),
                        Text('Work', style: GoogleFonts.inter(fontSize: 13)),
                        const SizedBox(width: 20),
                        Radio<String>(
                          value: 'Other',
                          groupValue: labelValue,
                          activeColor: AppTheme.primary,
                          onChanged: (val) => setDialogState(() => labelValue = val!),
                        ),
                        Text('Other', style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: isSavingAddress ? null : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() => isSavingAddress = true);
                            try {
                              final isCust = _viewingItem is CustomerModel;
                              final id = isCust ? _viewingItem.id : (_viewingItem as UserModel).id;
                              
                              await APIService.instance.saveAddress(id, {
                                'label': labelValue,
                                'address_line': detailController.text.trim(),
                                'latitude': 23.8041,
                                'longitude': 90.3625,
                              }, isCustomer: isCust);
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Address saved successfully.'), backgroundColor: AppTheme.accent),
                                );
                              }
                              _loadAddresses(_viewingItem);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                                );
                              }
                            } finally {
                              setDialogState(() => isSavingAddress = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                          child: isSavingAddress 
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  // Delete Address
  Future<void> _deleteAddress(AddressModel addr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await APIService.instance.deleteAddress(addr.id);
        _loadAddresses(_viewingItem);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Filtered List items
  List<dynamic> get _filteredItems {
    return _items.where((item) {
      String name = '';
      String phone = '';
      String email = '';
      String status = 'active';

      if (item is CustomerModel) {
        name = item.name;
        phone = item.phone;
        email = item.email ?? '';
        status = 'active';
      } else if (item is UserModel) {
        name = item.name;
        phone = item.phone ?? '';
        email = item.email ?? item.username;
        status = item.status;
      }
      
      // Top search query match
      final query = _searchQuery.toLowerCase();
      final matchQuery = name.toLowerCase().contains(query) || 
                          phone.toLowerCase().contains(query) || 
                          email.toLowerCase().contains(query);

      // Advanced filters match
      final matchName = _appliedName.isEmpty || name.toLowerCase().contains(_appliedName);
      final matchEmail = _appliedEmail.isEmpty || email.toLowerCase().contains(_appliedEmail);
      final matchPhone = _appliedPhone.isEmpty || phone.contains(_appliedPhone);
      final matchStatus = _appliedStatus == '--' || status == _appliedStatus;

      return matchQuery && matchName && matchEmail && matchPhone && matchStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Row(
        children: [
          // Main Panel
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _viewingItem != null 
                  ? _buildDetailView()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title and actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.userType,
                                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                                    Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                                    Text(widget.userType, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(icon: Icon(Icons.refresh, color: AppTheme.primary), onPressed: _loadData),
                                const SizedBox(width: 8),
                                _buildOutlineButton(
                                  icon: Icons.filter_alt_outlined,
                                  label: 'Filter',
                                  onTap: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
                                ),
                                const SizedBox(width: 12),
                                // Export Dropdown Popup Button
                                PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'PDF') {
                                      _exportToPDF();
                                    } else if (val == 'Print') {
                                      _printList();
                                    } else if (val == 'XLS') {
                                      _exportToCSV();
                                    }
                                  },
                                  offset: const Offset(0, 45),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'PDF',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Color(0xFF64748B)),
                                          const SizedBox(width: 8),
                                          Text('Export PDF', style: GoogleFonts.inter(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'Print',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.print_outlined, size: 16, color: Color(0xFF64748B)),
                                          const SizedBox(width: 8),
                                          Text('Print Report', style: GoogleFonts.inter(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'XLS',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.table_view_outlined, size: 16, color: Color(0xFF64748B)),
                                          const SizedBox(width: 8),
                                          Text('Export CSV', style: GoogleFonts.inter(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppTheme.primary),
                                      borderRadius: BorderRadius.circular(8),
                                      color: AppTheme.cardLight,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Row(
                                      children: [
                                        Icon(Icons.download_outlined, size: 14, color: AppTheme.primary),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Export',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.primary),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _openDrawer(),
                                  icon: const Icon(Icons.add_circle_outline, size: 16),
                                  label: Text('Add ${_getSingleName(widget.userType)}'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Advanced Filter Row Panel
                        if (_isFilterExpanded) ...[
                          _buildFilterSection(),
                          const SizedBox(height: 16),
                        ],

                        // Search Bar
                        Card(
                          elevation: 0,
                          color: AppTheme.cardLight,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.bgLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.borderLight),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.search, color: AppTheme.textLightSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      onChanged: (val) => setState(() => _searchQuery = val),
                                      decoration: InputDecoration(
                                        hintText: 'Search by name, email, or phone...',
                                        hintStyle: TextStyle(color: AppTheme.textLightSecondary),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                      ),
                                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // List Card Table
                        Expanded(
                          child: Card(
                            elevation: 0,
                            color: AppTheme.cardLight,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: _isLoading
                                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                                : _errorMessage.isNotEmpty
                                    ? Center(child: Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)))
                                    : filtered.isEmpty
                                        ? _buildEmptyState()
                                        : _buildTable(filtered),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // Drawer Form on right
          if (_isDrawerOpen) _buildDrawer(),
        ],
      ),
    );
  }

  // Advanced Filters panel builder
  Widget _buildFilterSection() {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('NAME'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterNameController,
                        decoration: const InputDecoration(hintText: 'Enter name'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterEmailController,
                        decoration: const InputDecoration(hintText: 'Enter email'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('PHONE'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterPhoneController,
                        decoration: const InputDecoration(hintText: 'Enter phone'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('STATUS'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _filterStatus,
                        items: const [
                          DropdownMenuItem(value: '--', child: Text('--')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                        ],
                        onChanged: (val) => setState(() => _filterStatus = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _appliedName = _filterNameController.text.trim().toLowerCase();
                      _appliedEmail = _filterEmailController.text.trim().toLowerCase();
                      _appliedPhone = _filterPhoneController.text.trim();
                      _appliedStatus = _filterStatus;
                    });
                  },
                  icon: const Icon(Icons.search, size: 14),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _filterNameController.clear();
                      _filterEmailController.clear();
                      _filterPhoneController.clear();
                      _filterStatus = '--';
                      
                      _appliedName = '';
                      _appliedEmail = '';
                      _appliedPhone = '';
                      _appliedStatus = '--';
                    });
                  },
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF475569),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineButton({required IconData icon, required String label, required VoidCallback onTap}) {
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

  String _getSingleName(String title) {
    if (title == 'Administrators') return 'Administrator';
    if (title == 'Delivery Boys') return 'Delivery Boy';
    if (title == 'Employees') return 'Employee';
    if (title == 'Waiters') return 'Waiter';
    if (title == 'Chefs') return 'Chef';
    return 'Customer';
  }

  // Empty Folder sad state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF0F5), Color(0xFFFFE4E6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Column(
                children: [
                  const Icon(Icons.folder_open, size: 54, color: Color(0xFFFDA4AF)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 12,
                    height: 2,
                    color: const Color(0xFFE11D48),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'No data available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
          ),
        ],
      ),
    );
  }

  // Main table list
  Widget _buildTable(List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          color: AppTheme.bgLight,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildTableHeaderText('NAME')),
              Expanded(flex: 3, child: _buildTableHeaderText('EMAIL')),
              Expanded(flex: 3, child: _buildTableHeaderText('PHONE')),
              Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
              Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
            itemBuilder: (context, index) {
              final item = items[index];
              
              String name = '';
              String email = '';
              String phone = '';
              String status = 'active';
              String? imageBase64;

              if (item is CustomerModel) {
                name = item.name;
                email = item.email ?? 'N/A';
                phone = item.phone;
                status = 'active';
                imageBase64 = item.imageBase64;
              } else if (item is UserModel) {
                name = item.name;
                email = item.email ?? item.username;
                phone = item.phone ?? 'N/A';
                status = item.status;
                imageBase64 = item.imageBase64;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    // NAME & Image Preview
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          if (imageBase64 != null && imageBase64.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 36,
                                height: 36,
                                color: AppTheme.bgLight,
                                child: Base64ImageWidget(base64Str: imageBase64, fit: BoxFit.cover),
                              ),
                            )
                          else
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(18)),
                              child: Icon(Icons.person_outline, color: AppTheme.primary, size: 18),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EMAIL
                    Expanded(
                      flex: 3,
                      child: Text(
                        email,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // PHONE
                    Expanded(
                      flex: 3,
                      child: Text(
                        phone,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // STATUS
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildStatusBadge(status),
                      ),
                    ),
                    // ACTION
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          // View Details eye icon
                          GestureDetector(
                            onTap: () => _viewDetails(item),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                              child: Icon(Icons.visibility_outlined, color: AppTheme.primary, size: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (item is UserModel) ...[
                            GestureDetector(
                              onTap: () => _showPasswordResetDialog(item),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.vpn_key_outlined, color: Colors.blue, size: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          GestureDetector(
                            onTap: () => _openDrawer(item),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                              child: Icon(Icons.edit, color: AppTheme.primary, size: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _deleteItem(item),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                              child: Icon(
                                item is CustomerModel ? Icons.delete : Icons.block,
                                color: AppTheme.danger,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF137333) : const Color(0xFFC5221F)),
      ),
    );
  }

  // ----------------------------------------------------
  // HIGH FIDELITY PROFILE DETAILS PAGE VIEW
  // ----------------------------------------------------
  Widget _buildDetailView() {
    final name = _viewingItem is CustomerModel ? (_viewingItem as CustomerModel).name : (_viewingItem as UserModel).name;
    final role = _viewingItem is CustomerModel ? 'CUSTOMER' : (_viewingItem as UserModel).role.toUpperCase();
    final imageBase64 = _viewingItem is CustomerModel ? (_viewingItem as CustomerModel).imageBase64 : (_viewingItem as UserModel).imageBase64;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumbs
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.userType,
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                      Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                      Text(widget.userType, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                      Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                      Text('View', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _viewingItem = null),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Back to List'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.primary),
                  foregroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // User Header Card
          Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // Photo Avatar
                  if (imageBase64 != null && imageBase64.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Container(
                        width: 80,
                        height: 80,
                        color: AppTheme.bgLight,
                        child: Base64ImageWidget(base64Str: imageBase64, fit: BoxFit.cover),
                      ),
                    )
                  else
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(40)),
                      child: Icon(Icons.person, color: AppTheme.primary, size: 40),
                    ),
                  const SizedBox(width: 24),
                  
                  // Text Detail
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getRoleBadgeColor(role),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          role,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _uploadProfilePicture,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 14),
                        label: const Text('Upload New Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Tab Selection Row
          Row(
            children: [
              _buildTabButton(0, Icons.person_outline, 'Profile'),
              const SizedBox(width: 12),
              _buildTabButton(1, Icons.lock_outline, 'Security'),
              const SizedBox(width: 12),
              _buildTabButton(2, Icons.location_on_outlined, 'Address'),
              const SizedBox(width: 12),
              _buildTabButton(3, Icons.shopping_bag_outlined, 'My Orders'),
            ],
          ),
          const SizedBox(height: 20),

          // Tab content block
          Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleBadgeColor(String role) {
    if (role == 'ADMIN' || role == 'OWNER') return const Color(0xFFEAB308);
    if (role == 'DELIVERY') return const Color(0xFF3B82F6);
    if (role == 'WAITER') return const Color(0xFF8B5CF6);
    if (role == 'KITCHEN') return const Color(0xFFEF4444);
    if (role == 'CUSTOMER') return AppTheme.primary;
    return const Color(0xFF6B7280);
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final active = _activeTab == index;
    return ElevatedButton.icon(
      onPressed: () => setState(() => _activeTab = index),
      icon: Icon(icon, size: 14, color: active ? Colors.white : AppTheme.textLightSecondary),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? AppTheme.primary : AppTheme.cardLight,
        foregroundColor: active ? Colors.white : AppTheme.textLightSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: active ? BorderSide.none : BorderSide(color: AppTheme.borderLight),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 0:
        return _buildProfileTab();
      case 1:
        return _buildSecurityTab();
      case 2:
        return _buildAddressTab();
      case 3:
        return _buildOrdersTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // TAB 0: Profile Tab content
  Widget _buildProfileTab() {
    String email = 'N/A';
    String phone = 'N/A';
    String status = 'active';

    if (_viewingItem is CustomerModel) {
      final cust = _viewingItem as CustomerModel;
      email = cust.email ?? 'N/A';
      phone = cust.phone;
      status = 'active';
    } else if (_viewingItem is UserModel) {
      final user = _viewingItem as UserModel;
      email = user.email ?? user.username;
      phone = user.phone ?? 'N/A';
      status = user.status;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Basic Information', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 20),
        
        // Data layout
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(3),
          },
          children: [
            _buildProfileTableRow('Email', email),
            _buildProfileTableRow('Phone', phone),
            _buildProfileTableRowWidget('Status', _buildStatusBadge(status)),
            if (_viewingItem is UserModel) 
              _buildProfileTableRow('Branch Privilege', (_viewingItem as UserModel).branch == 'all' ? 'All Branch Access' : 'Current Branch Only'),
          ],
        ),
      ],
    );
  }

  TableRow _buildProfileTableRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textLightPrimary)),
        ),
      ],
    );
  }
 
  TableRow _buildProfileTableRowWidget(String label, Widget widget) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Align(alignment: Alignment.centerLeft, child: widget),
        ),
      ],
    );
  }

  // TAB 1: Security Tab content
  Widget _buildSecurityTab() {
    if (_viewingItem is CustomerModel) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Security options are not available for customers.',
            style: GoogleFonts.inter(color: const Color(0xFF64748B)),
          ),
        ),
      );
    }

    final formKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool isSavingSec = false;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Password', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
          const SizedBox(height: 20),
          
          _buildFieldLabel('NEW PASSWORD *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: passCtrl,
            obscureText: true,
            validator: (val) => val == null || val.length < 4 ? 'Password must be at least 4 characters' : null,
            decoration: const InputDecoration(hintText: 'Enter new secure password'),
          ),
          const SizedBox(height: 20),

          _buildFieldLabel('PASSWORD CONFIRMATION *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: confirmCtrl,
            obscureText: true,
            validator: (val) {
              if (val != passCtrl.text) return 'Passwords do not match';
              return null;
            },
            decoration: const InputDecoration(hintText: 'Re-enter new secure password'),
          ),
          const SizedBox(height: 24),

          StatefulBuilder(
            builder: (context, setSecState) {
              return ElevatedButton(
                onPressed: isSavingSec ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  setSecState(() => isSavingSec = true);
                  try {
                    await APIService.instance.resetUserPassword((_viewingItem as UserModel).id, passCtrl.text);
                    passCtrl.clear();
                    confirmCtrl.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password changed successfully'), backgroundColor: AppTheme.accent),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  } finally {
                    setSecState(() => isSavingSec = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: isSavingSec 
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Password'),
              );
            }
          ),
        ],
      ),
    );
  }

  // TAB 2: Address Tab content
  Widget _buildAddressTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Addresses', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            ElevatedButton.icon(
              onPressed: _showAddAddressDialog,
              icon: const Icon(Icons.add_location_alt_outlined, size: 14),
              label: const Text('Add Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_loadingAddresses)
          Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else if (_addresses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                'No saved addresses.',
                style: GoogleFonts.inter(color: AppTheme.textLightSecondary),
              ),
            ),
          )
        else
          // Addresses table list
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppTheme.bgLight,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: _buildTableHeaderText('LABEL')),
                    Expanded(flex: 6, child: _buildTableHeaderText('ADDRESS')),
                    Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _addresses.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                itemBuilder: (context, index) {
                  final addr = _addresses[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            addr.label,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Text(
                            addr.addressLine,
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => _deleteAddress(addr),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.delete, color: AppTheme.danger, size: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  List<OrderModel> get _filteredUserOrders {
    final now = DateTime.now();
    return _rawUserOrders.where((o) {
      final orderDate = DateTime.tryParse(o.createdAt)?.toLocal() ?? DateTime.now();
      
      if (_ordersFilterPreset == 'daily') {
        return orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day;
      } else if (_ordersFilterPreset == 'weekly') {
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return orderDate.isAfter(sevenDaysAgo);
      } else if (_ordersFilterPreset == 'monthly') {
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        return orderDate.isAfter(thirtyDaysAgo);
      } else if (_ordersFilterPreset == 'single' && _ordersFilterSingleDate != null) {
        return orderDate.year == _ordersFilterSingleDate!.year &&
               orderDate.month == _ordersFilterSingleDate!.month &&
               orderDate.day == _ordersFilterSingleDate!.day;
      } else if (_ordersFilterPreset == 'custom') {
        bool match = true;
        if (_ordersFilterStartDate != null) {
          final startOfDay = DateTime(_ordersFilterStartDate!.year, _ordersFilterStartDate!.month, _ordersFilterStartDate!.day);
          match = match && (orderDate.isAfter(startOfDay) || orderDate.isAtSameMomentAs(startOfDay));
        }
        if (_ordersFilterEndDate != null) {
          final endOfDay = DateTime(_ordersFilterEndDate!.year, _ordersFilterEndDate!.month, _ordersFilterEndDate!.day, 23, 59, 59);
          match = match && (orderDate.isBefore(endOfDay) || orderDate.isAtSameMomentAs(endOfDay));
        }
        return match;
      }
      return true; // all
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredPreparedItems {
    final now = DateTime.now();
    return _preparedItems.where((item) {
      final itemDate = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      
      if (_ordersFilterPreset == 'daily') {
        return itemDate.year == now.year && itemDate.month == now.month && itemDate.day == now.day;
      } else if (_ordersFilterPreset == 'weekly') {
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return itemDate.isAfter(sevenDaysAgo);
      } else if (_ordersFilterPreset == 'monthly') {
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        return itemDate.isAfter(thirtyDaysAgo);
      } else if (_ordersFilterPreset == 'single' && _ordersFilterSingleDate != null) {
        return itemDate.year == _ordersFilterSingleDate!.year &&
               itemDate.month == _ordersFilterSingleDate!.month &&
               itemDate.day == _ordersFilterSingleDate!.day;
      } else if (_ordersFilterPreset == 'custom') {
        bool match = true;
        if (_ordersFilterStartDate != null) {
          final startOfDay = DateTime(_ordersFilterStartDate!.year, _ordersFilterStartDate!.month, _ordersFilterStartDate!.day);
          match = match && (itemDate.isAfter(startOfDay) || itemDate.isAtSameMomentAs(startOfDay));
        }
        if (_ordersFilterEndDate != null) {
          final endOfDay = DateTime(_ordersFilterEndDate!.year, _ordersFilterEndDate!.month, _ordersFilterEndDate!.day, 23, 59, 59);
          match = match && (itemDate.isBefore(endOfDay) || itemDate.isAtSameMomentAs(endOfDay));
        }
        return match;
      }
      return true; // all
    }).toList();
  }

  Future<void> _printOrdersHistoryReport(List<OrderModel> orders) async {
    final name = _viewingItem is CustomerModel ? (_viewingItem as CustomerModel).name : (_viewingItem as UserModel).name;
    final role = _viewingItem is CustomerModel ? 'CUSTOMER' : (_viewingItem as UserModel).role.toUpperCase();

    final doc = pw.Document();
    double totalSum = orders.fold(0.0, (sum, o) => sum + o.total);

    final headers = ['Order Number', 'Date & Time', 'Status', 'Amount'];
    final data = orders.map((o) {
      final dateFormatted = DateFormat('yyyy-MM-dd hh:mm a').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
      return [
        o.orderNumber,
        dateFormatted,
        o.status.toUpperCase(),
        'LKR ${o.total.toStringAsFixed(2)}',
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'MATARA HOTEL',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Orders History Report',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Staff Member: $name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Role: $role'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Exported On: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                      pw.Text('Total Served: ${orders.length} orders'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              
              pw.Table.fromTextArray(
                headers: headers,
                data: data,
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Grand Total: LKR ${totalSum.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Orders_Report_${name.replaceAll(" ", "_")}',
    );
  }

  Future<void> _printPreparedItemsReport(List<Map<String, dynamic>> prepared) async {
    final name = (_viewingItem as UserModel).name;
    final role = (_viewingItem as UserModel).role.toUpperCase();

    final doc = pw.Document();
    double totalQty = prepared.fold(0.0, (sum, item) => sum + (double.tryParse(item['quantity']?.toString() ?? '1') ?? 1.0));

    final headers = ['Item Name', 'Invoice / Type', 'Date & Time', 'Qty', 'Ingredients Used'];
    final data = prepared.map((item) {
      final dateFormatted = DateFormat('yyyy-MM-dd hh:mm a').format((DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now()).toLocal());
      final isSale = item['source_type'] == 'sale';
      final orderNum = item['order_number']?.toString() ?? '';
      final double qty = double.tryParse(item['quantity']?.toString() ?? '1') ?? 1.0;
      
      // Parse size if kottu etc has notes like Size: Large
      String? selectedSize;
      final notes = item['notes']?.toString() ?? '';
      if (notes.contains('Size: ')) {
        final match = RegExp(r'Size:\s*([^|]+)').firstMatch(notes);
        if (match != null && match.group(1) != null) {
          selectedSize = match.group(1)!.trim();
        }
      }

      final List ingList = item['ingredients'] ?? [];
      final ingStrings = <String>[];
      for (var ing in ingList) {
        final ingId = ing['ingredient_id'] != null ? int.tryParse(ing['ingredient_id'].toString()) : null;
        final ingQty = ing['qty'] != null ? double.tryParse(ing['qty'].toString()) : null;
        final ingSize = ing['size']?.toString();
        if (ingId != null && ingQty != null) {
          if (ingSize != null && ingSize != selectedSize) {
            continue;
          }
          final name = _ingredientNames[ingId] ?? 'Ingredient #$ingId';
          final totalDeduct = ingQty * qty;
          ingStrings.add('$name: ${totalDeduct.toStringAsFixed(1)}');
        }
      }
      final ingredientsDisplay = ingStrings.isEmpty ? 'N/A' : ingStrings.join(', ');

      return [
        item['product_name']?.toString() ?? 'Unknown Product',
        isSale ? orderNum : 'Stock Addition',
        dateFormatted,
        qty.toStringAsFixed(0),
        ingredientsDisplay,
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'MATARA HOTEL',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Chef Prepared Items History Report',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Chef Member: $name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Role: $role'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Exported On: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                      pw.Text('Total Items Prepared: ${totalQty.toStringAsFixed(0)} items'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              
              pw.Table.fromTextArray(
                headers: headers,
                data: data,
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerLeft,
                },
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Prepared_Items_Report_${name.replaceAll(" ", "_")}',
    );
  }

  // TAB 3: My Orders Tab content
  Widget _buildOrdersTab() {
    final isChef = _viewingItem is UserModel && (_viewingItem as UserModel).role.toLowerCase() == 'kitchen';
    final orders = isChef ? <OrderModel>[] : _filteredUserOrders;
    final prepared = isChef ? _filteredPreparedItems : <Map<String, dynamic>>[];
    final bool isEmpty = isChef ? prepared.isEmpty : orders.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isChef ? 'Prepared Items History' : 'Orders History', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 20),

        // Filters Row
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _ordersFilterPreset,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Time')),
                    DropdownMenuItem(value: 'daily', child: Text('Daily (Today)')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly (Last 7 Days)')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly (Last 30 Days)')),
                    DropdownMenuItem(value: 'single', child: Text('Single Date')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom Range')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _ordersFilterPreset = val!;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            if (_ordersFilterPreset == 'single') ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _ordersFilterSingleDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _ordersFilterSingleDate = picked;
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(
                  _ordersFilterSingleDate == null
                      ? 'Select Date'
                      : DateFormat('yyyy-MM-dd').format(_ordersFilterSingleDate!),
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ),
            ] else if (_ordersFilterPreset == 'custom') ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _ordersFilterStartDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _ordersFilterStartDate = picked;
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(
                  _ordersFilterStartDate == null
                      ? 'Start Date'
                      : DateFormat('yyyy-MM-dd').format(_ordersFilterStartDate!),
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text('to', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _ordersFilterEndDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _ordersFilterEndDate = picked;
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(
                  _ordersFilterEndDate == null
                      ? 'End Date'
                      : DateFormat('yyyy-MM-dd').format(_ordersFilterEndDate!),
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ),
            ],
            
            const Spacer(),
            
            ElevatedButton.icon(
              onPressed: isEmpty ? null : () {
                if (isChef) {
                  _printPreparedItemsReport(prepared);
                } else {
                  _printOrdersHistoryReport(orders);
                }
              },
              icon: const Icon(Icons.picture_as_pdf, size: 14),
              label: const Text('Export PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_loadingOrders)
          Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else if (isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                isChef ? 'No prepared items found matching the filter.' : 'No orders found matching the filter.',
                style: GoogleFonts.inter(color: AppTheme.textLightSecondary),
              ),
            ),
          )
        else if (isChef)
          // Prepared items table layout
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _buildTableHeaderText('ITEM NAME')),
                      Expanded(flex: 1, child: _buildTableHeaderText('QTY')),
                      Expanded(flex: 3, child: _buildTableHeaderText('DATE & TIME')),
                      Expanded(flex: 3, child: _buildTableHeaderText('INVOICE / TYPE')),
                      Expanded(flex: 5, child: _buildTableHeaderText('INGREDIENTS USED')),
                      Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: prepared.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                  itemBuilder: (context, index) {
                    final item = prepared[index];
                    final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now()).toLocal());
                    
                    // Format ingredients
                    final List ingList = item['ingredients'] ?? [];
                    final double qty = double.tryParse(item['quantity']?.toString() ?? '1') ?? 1.0;
                    
                    // Parse size if kottu etc has notes like Size: Large
                    String? selectedSize;
                    final notes = item['notes']?.toString() ?? '';
                    if (notes.contains('Size: ')) {
                      final match = RegExp(r'Size:\s*([^|]+)').firstMatch(notes);
                      if (match != null && match.group(1) != null) {
                        selectedSize = match.group(1)!.trim();
                      }
                    }

                    final ingStrings = <String>[];
                    for (var ing in ingList) {
                      final ingId = ing['ingredient_id'] != null ? int.tryParse(ing['ingredient_id'].toString()) : null;
                      final ingQty = ing['qty'] != null ? double.tryParse(ing['qty'].toString()) : null;
                      final ingSize = ing['size']?.toString();
                      if (ingId != null && ingQty != null) {
                        if (ingSize != null && ingSize != selectedSize) {
                          continue;
                        }
                        final name = _ingredientNames[ingId] ?? 'Ingredient #$ingId';
                        final totalDeduct = ingQty * qty;
                        ingStrings.add('$name: ${totalDeduct.toStringAsFixed(1)}');
                      }
                    }
                    final ingredientsDisplay = ingStrings.isEmpty ? 'N/A' : ingStrings.join(', ');

                    final orderNum = item['order_number']?.toString() ?? '';
                    final isSale = item['source_type'] == 'sale';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              item['product_name']?.toString() ?? 'Unknown Product',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${qty.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              dateFormatted,
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              isSale ? orderNum : 'Stock Addition',
                              style: GoogleFonts.inter(
                                fontSize: 12, 
                                fontWeight: FontWeight.w600,
                                color: isSale ? Colors.indigo : Colors.teal,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Text(
                              ingredientsDisplay,
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary, fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: isSale
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: GestureDetector(
                                      onTap: () async {
                                        try {
                                          final fullOrder = await APIService.instance.getOrderByNumber(orderNum);
                                          if (mounted) {
                                            _showUserOrderDetailDialog(fullOrder);
                                          }
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Icon(Icons.visibility_outlined, color: AppTheme.primary, size: 14),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          )
        else
          // General orders table layout
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _buildTableHeaderText('ORDER ID')),
                      Expanded(flex: 4, child: _buildTableHeaderText('DATE & TIME')),
                      Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
                      Expanded(flex: 3, child: _buildTableHeaderText('TOTAL')),
                      Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: orders.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                  itemBuilder: (context, index) {
                    final o = orders[index];
                    final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              '#${o.orderNumber.length > 12 ? o.orderNumber.substring(o.orderNumber.length - 8) : o.orderNumber}',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              dateFormatted,
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildOrderBadge(o.status),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'LKR ${o.total.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showUserOrderDetailDialog(o),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Icon(Icons.visibility_outlined, color: AppTheme.primary, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOrderBadge(String status) {
    Color bg = AppTheme.isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    Color fg = AppTheme.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    if (status == 'delivered') {
      bg = const Color(0xFFE6F4EA);
      fg = const Color(0xFF137333);
    } else if (status == 'preparing') {
      bg = const Color(0xFFE8F0FE);
      fg = const Color(0xFF1A73E8);
    } else if (status == 'pending') {
      bg = const Color(0xFFFEF7E0);
      fg = const Color(0xFFB06000);
    } else if (status == 'cancelled') {
      bg = const Color(0xFFFCE8E6);
      fg = const Color(0xFFC5221F);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  void _showUserOrderDetailDialog(OrderModel order) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: FutureBuilder<List<OrderItemModel>>(
                future: APIService.instance.getOrderItems(order.id!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    );
                  }
                  
                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 200,
                      child: Center(child: Text('Error loading details: ${snapshot.error}')),
                    );
                  }

                  final items = snapshot.data ?? [];
                  
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order Details',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 18, color: AppTheme.textLightSecondary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      Divider(height: 20, color: AppTheme.dividerColor),
                      Text(
                        'Order Number: #${order.orderNumber}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Date: ${DateFormat('yyyy-MM-dd hh:mm a').format((DateTime.tryParse(order.createdAt) ?? DateTime.now()).toLocal())}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                      const SizedBox(height: 16),
                      
                      Text(
                        'Items Ordered',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.borderLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, idx) => Divider(height: 1, color: AppTheme.dividerColor),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            return ListTile(
                              dense: true,
                              title: Text(item.productName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
                              subtitle: item.notes != null && item.notes!.isNotEmpty
                                  ? Text('Notes: ${item.notes}', style: GoogleFonts.inter(fontSize: 10, fontStyle: FontStyle.italic, color: AppTheme.textLightSecondary))
                                  : null,
                              trailing: Text(
                                '${item.quantity} x LKR ${item.price.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Totals
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                          Text('LKR ${order.subtotal.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (order.discount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Discount:', style: GoogleFonts.inter(fontSize: 12, color: Colors.red)),
                            Text('-LKR ${order.discount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (order.advancePayment > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Advance Paid:', style: GoogleFonts.inter(fontSize: 12, color: Colors.green)),
                          Text('LKR ${order.advancePayment.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Amount:', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                        Text('LKR ${order.total.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ),
        );
      },
    );
  }

  // Slide-out Drawer Panel on Right
  Widget _buildDrawer() {
    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        border: Border(left: BorderSide(color: AppTheme.borderLight)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(-4, 0)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: _isCustomerType ? _buildCustomerForm() : _buildUserForm(),
    );
  }

  // System User Drawer Form (includes Branch selection)
  Widget _buildUserForm() {
    return Form(
      key: _userFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingItem == null ? 'Add ${_getSingleName(widget.userType)}' : 'Edit ${_getSingleName(widget.userType)}',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              IconButton(icon: Icon(Icons.close, size: 18, color: AppTheme.textLightSecondary), onPressed: _closeDrawer),
            ],
          ),
          Divider(height: 24, color: AppTheme.dividerColor),
          const SizedBox(height: 12),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('NAME *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameController,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter a name' : null,
                    decoration: const InputDecoration(hintText: 'Enter name'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('USERNAME (LOGIN ID) *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _usernameController,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter username' : null,
                    decoration: const InputDecoration(hintText: 'Enter login username'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('EMAIL'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'Enter email address'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('PHONE'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: 'Enter phone number'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  if (_editingItem == null) ...[
                    _buildFieldLabel('PASSWORD *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      validator: (val) => val == null || val.length < 4 ? 'Password must be at least 4 characters' : null,
                      decoration: const InputDecoration(hintText: 'Enter login password'),
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                  ],

                  _buildFieldLabel('ROLE'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _roleVal,
                    dropdownColor: AppTheme.cardLight,
                    style: TextStyle(color: AppTheme.textLightPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                      DropdownMenuItem(value: 'owner', child: Text('Hotel Owner')),
                      DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                      DropdownMenuItem(value: 'kitchen', child: Text('Chef / Kitchen')),
                      DropdownMenuItem(value: 'delivery', child: Text('Delivery Rider')),
                      DropdownMenuItem(value: 'waiter', child: Text('Steward / Waiter')),
                    ],
                    onChanged: (val) => setState(() {
                      _roleVal = val!;
                      if (_roleVal != 'kitchen') {
                        _selectedCategoryId = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 20),

                  if (_roleVal == 'kitchen') ...[
                    _buildFieldLabel('ASSIGNED CATEGORY'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      value: _selectedCategoryId,
                      dropdownColor: AppTheme.cardLight,
                      style: TextStyle(color: AppTheme.textLightPrimary, fontSize: 13),
                      hint: Text('Select category (e.g. Koththu)', style: TextStyle(color: AppTheme.textLightSecondary)),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('None', style: TextStyle(color: AppTheme.textLightSecondary)),
                        ),
                        ..._categories.map((c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name, style: TextStyle(color: AppTheme.textLightPrimary)),
                            )),
                      ],
                      onChanged: (val) => setState(() => _selectedCategoryId = val),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Branch selector for Administrators only
                  if (widget.userType == 'Administrators') ...[
                    _buildFieldLabel('BRANCH *'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Radio<String>(
                          value: 'current',
                          groupValue: _branchVal,
                          activeColor: AppTheme.primary,
                          onChanged: (val) => setState(() => _branchVal = val!),
                        ),
                        Text('Current Branch', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                        const SizedBox(width: 20),
                        Radio<String>(
                          value: 'all',
                          groupValue: _branchVal,
                          activeColor: AppTheme.primary,
                          onChanged: (val) => setState(() => _branchVal = val!),
                        ),
                        Text('All Branch', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  _buildFieldLabel('STATUS'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'active',
                        groupValue: _statusVal,
                        activeColor: AppTheme.primary,
                        onChanged: (val) => setState(() => _statusVal = val!),
                      ),
                      Text('Active', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                      const SizedBox(width: 20),
                      Radio<String>(
                        value: 'inactive',
                        groupValue: _statusVal,
                        activeColor: AppTheme.primary,
                        onChanged: (val) => setState(() => _statusVal = val!),
                      ),
                      Text('Inactive', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(height: 1, color: AppTheme.dividerColor),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _closeDrawer,
                  icon: Icon(Icons.close, size: 16, color: AppTheme.textLightSecondary),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.borderLight),
                    foregroundColor: AppTheme.textLightSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Customer Drawer Form
  Widget _buildCustomerForm() {
    return Form(
      key: _customerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingItem == null ? 'Add Customer' : 'Edit Customer',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              IconButton(icon: Icon(Icons.close, size: 18, color: AppTheme.textLightSecondary), onPressed: _closeDrawer),
            ],
          ),
          Divider(height: 24, color: AppTheme.dividerColor),
          const SizedBox(height: 12),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('NAME *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custNameController,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter customer name' : null,
                    decoration: const InputDecoration(hintText: 'Enter customer name'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('PHONE NUMBER *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custPhoneController,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter phone number' : null,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: 'Enter phone number'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('EMAIL ADDRESS'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'Enter email address'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('BIRTHDAY'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custBirthdayController,
                    readOnly: true,
                    onTap: _selectBirthday,
                    decoration: InputDecoration(
                      hintText: 'yyyy-mm-dd',
                      suffixIcon: Icon(Icons.calendar_today, size: 16, color: AppTheme.textLightSecondary),
                    ),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('CREDIT LIMIT (LKR)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custCreditLimitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Enter credit limit'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('OUTSTANDING BALANCE (LKR)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custBalanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Enter outstanding balance'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(height: 1, color: AppTheme.dividerColor),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _closeDrawer,
                  icon: Icon(Icons.close, size: 16, color: AppTheme.textLightSecondary),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.borderLight),
                    foregroundColor: AppTheme.textLightSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
    );
  }
}
