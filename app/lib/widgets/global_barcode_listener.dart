import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../pos_controller.dart';
import '../controllers/app_settings_controller.dart';
import 'order_status_scan_dialog.dart';

class GlobalBarcodeListener extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const GlobalBarcodeListener({
    Key? key,
    required this.child,
    required this.navigatorKey,
  }) : super(key: key);

  @override
  State<GlobalBarcodeListener> createState() => _GlobalBarcodeListenerState();
}

class _GlobalBarcodeListenerState extends State<GlobalBarcodeListener> {
  String _barcodeBuffer = '';
  DateTime? _lastKeyPressTime;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      
      // If time between key presses exceeds 200ms, reset buffer
      if (_lastKeyPressTime != null && now.difference(_lastKeyPressTime!).inMilliseconds > 200) {
        _barcodeBuffer = '';
      }
      _lastKeyPressTime = now;

      final logicalKey = event.logicalKey;

      // Handle Enter Key (End of Barcode Scan)
      if (logicalKey == LogicalKeyboardKey.enter || logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_barcodeBuffer.trim().isNotEmpty) {
          final scannedBarcode = _barcodeBuffer.trim();
          _barcodeBuffer = '';
          _processScannedBarcode(scannedBarcode);
          return true;
        }
        _barcodeBuffer = '';
        return false;
      }

      // Buffer character keys
      final char = event.character;
      if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
        _barcodeBuffer += char;
      }
    }
    return false;
  }

  Future<void> _processScannedBarcode(String barcode) async {
    if (_isProcessing) return;
    _isProcessing = true;

    String cleanBarcode = barcode.trim();
    final upperBarcode = cleanBarcode.toUpperCase();

    // ── Table QR Code Scan Handling ──────────────────────────────────────────
    if (upperBarcode.startsWith('TABLE-') || upperBarcode.startsWith('TBL-')) {
      final tableStr = upperBarcode.startsWith('TABLE-')
          ? upperBarcode.substring(6)
          : upperBarcode.substring(4);
      
      final context = widget.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        try {
          final posController = Provider.of<POSController>(context, listen: false);
          
          DiningTableModel? foundTable;
          for (var t in posController.diningTables) {
            if (t.tableNumber.toUpperCase() == tableStr || t.id.toString() == tableStr) {
              foundTable = t;
              break;
            }
          }

          if (foundTable != null) {
            posController.requestedScreenIndex = 1;
            posController.handleScannedTable(foundTable);
            _showToast('Table ${foundTable.tableNumber} Scanned!');
          } else {
            _showToast('Table "$tableStr" not found in system', isError: true);
          }
        } catch (e) {
          _showToast('Error selecting scanned table: $e', isError: true);
        } finally {
          _isProcessing = false;
        }
      }
      return;
    }

    final context = widget.navigatorKey.currentContext;
    POSController? posController;
    AppSettingsController? appSettings;
    if (context != null && context.mounted) {
      try {
        posController = Provider.of<POSController>(context, listen: false);
        appSettings = Provider.of<AppSettingsController>(context, listen: false);
      } catch (_) {}
    }

    bool isKot = false;
    bool isInv = false;
    bool isPreOrder = false;

    final upper = cleanBarcode.toUpperCase();
    if (upper.startsWith('KOT-')) {
      cleanBarcode = cleanBarcode.substring(4);
      isKot = true;
    } else if (upper.startsWith('K-')) {
      cleanBarcode = cleanBarcode.substring(2);
      isKot = true;
    } else if (upper.startsWith('INV-')) {
      cleanBarcode = cleanBarcode.substring(4);
      isInv = true;
    } else if (upper.startsWith('I-P-')) {
      cleanBarcode = cleanBarcode.substring(4);
      isPreOrder = true;
    } else if (upper.startsWith('I-')) {
      cleanBarcode = cleanBarcode.substring(2);
      isInv = true;
    } else if (upper.startsWith('PRE-')) {
      cleanBarcode = cleanBarcode.substring(4);
      isPreOrder = true;
    } else if (upper.startsWith('P-')) {
      cleanBarcode = cleanBarcode.substring(2);
      isPreOrder = true;
    }

    // ── 1. PRE-ORDER BARCODE HANDLER ──────────────────────────────────────────
    if (isPreOrder || upper.startsWith('P-') || upper.startsWith('PRE-') || upper.startsWith('I-P-')) {
      try {
        final api = APIService.instance;
        List<dynamic> preOrdersList = posController?.preOrders ?? [];
        if (preOrdersList.isEmpty) {
          preOrdersList = await api.getPreOrders();
        }

        dynamic matchedPreOrder;
        for (var po in preOrdersList) {
          final poNum = (po['pre_order_number'] ?? '').toString().toUpperCase();
          final poId = (po['id'] ?? '').toString();
          final target = cleanBarcode.toUpperCase();
          if (poNum == target || poNum == 'P-$target' || poNum == 'PRE-$target' || poId == target || poNum.endsWith(target)) {
            matchedPreOrder = po;
            break;
          }
        }

        if (matchedPreOrder != null) {
          if (context != null && context.mounted && posController != null) {
            posController.loadPreOrderToCart(matchedPreOrder);
            posController.requestedScreenIndex = 1; // Open POS Screen with Cart loaded
            _showToast('Pre-Order ${matchedPreOrder['pre_order_number']} loaded into POS Cart!');
          }
          return;
        }
      } catch (e) {
        print('Pre-Order scan lookup error: $e');
      }
    }

    // ── 2. STANDARD ORDER BARCODE HANDLER ────────────────────────────────────
    try {
      final api = APIService.instance;
      OrderModel? order;

      // Try fetching order by order number first, then by prefixed variants, then by barcode
      try {
        order = await api.getOrderByNumber(cleanBarcode);
      } catch (_) {
        try {
          order = await api.getOrderByNumber('O-$cleanBarcode');
        } catch (_) {
          try {
            order = await api.getOrderByNumber('P-$cleanBarcode');
          } catch (_) {
            String legacy = cleanBarcode.replaceAll('26', '2026');
            try {
              order = await api.getOrderByNumber('ORD-$legacy');
            } catch (_) {
              try {
                order = await api.getOrderByNumber('PRE-$legacy');
              } catch (_) {
                try {
                  order = await api.getOrderByBarcode(cleanBarcode);
                } catch (_) {}
              }
            }
          }
        }
      }

      if (order == null) {
        _showToast('No order found with barcode: $barcode', isError: true);
        return;
      }

      final String oldStatus = order.status;
      String newStatus = oldStatus;
      bool statusChanged = false;

      // Calculate status transition logic
      if (isKot) {
        // KOT Scan Logic
        if (oldStatus == 'pending') {
          newStatus = 'preparing';
          statusChanged = true;
        } else if (oldStatus == 'preparing') {
          newStatus = 'prepared';
          statusChanged = true;
        }
      } else if (isInv) {
        // Invoice / Bill Scan Logic
        if (oldStatus == 'preparing') {
          newStatus = 'prepared';
          statusChanged = true;
        } else if (oldStatus == 'prepared') {
          newStatus = 'delivered';
          statusChanged = true;
        } else if (oldStatus == 'pending') {
          newStatus = 'delivered';
          statusChanged = true;
        }
      } else {
        // Generic barcode scan (No prefix)
        if (oldStatus == 'pending') {
          newStatus = 'preparing';
          statusChanged = true;
        } else if (oldStatus == 'preparing') {
          newStatus = 'prepared';
          statusChanged = true;
        } else if (oldStatus == 'prepared') {
          newStatus = 'delivered';
          statusChanged = true;
        }
      }

      final now = DateTime.now();
      final statusChangeTimeFormatted = DateFormat('yyyy-MM-dd hh:mm:ss a').format(now);
      final isoNow = now.toIso8601String();

      OrderModel updatedOrder = order;

      if (statusChanged) {
        await api.updateOrderOnline(order.id!, {
          'status': newStatus,
          'updated_at': isoNow,
        });

        updatedOrder = OrderModel(
          id: order.id,
          orderNumber: order.orderNumber,
          tableId: order.tableId,
          orderType: order.orderType,
          deliveryPlatform: order.deliveryPlatform,
          customerId: order.customerId,
          stewardName: order.stewardName,
          status: newStatus,
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
          updatedAt: isoNow,
          receivedAmount: order.receivedAmount,
          changeAmount: order.changeAmount,
          advancePayment: order.advancePayment,
          balanceAmount: order.balanceAmount,
          preOrderId: order.preOrderId,
          items: order.items,
        );
      }

      if (posController != null) {
        await posController.reloadEnvironment();
      }

      // Check if Kitchen / Silent Auto-Route applies
      final bool autoRouteKitchen = appSettings?.autoRouteKitchenBarcodes ?? true;
      final int currentScreenIndex = posController?.requestedScreenIndex ?? 0;
      final bool isKitchenScreen = currentScreenIndex == 3 || currentScreenIndex == 4; // KDS or Queue Screen

      if (autoRouteKitchen || isKot || isKitchenScreen) {
        // Kitchen / Silent Auto-Route Scan: Update status in backend silently with toast, DO NOT show Popup Dialog!
        _showToast('Order #${updatedOrder.orderNumber} status updated to ${newStatus.toUpperCase()}');
        return;
      }

      // Cashier Main POS Scanner Scan: Display popup modal
      if (context != null && context.mounted) {
        OrderStatusScanDialog.show(
          context: context,
          order: updatedOrder,
          oldStatus: oldStatus,
          newStatus: newStatus,
          statusChangeTime: statusChangeTimeFormatted,
          cashierName: api.currentUser?.name,
          stewardName: updatedOrder.stewardName,
        );
      }
    } catch (e) {
      _showToast('Barcode Scan Processing Error: $e', isError: true);
    } finally {
      _isProcessing = false;
    }
  }

  void _showToast(String message, {bool isError = false}) {
    final context = widget.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
