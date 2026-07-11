import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:hotel_pos/models/models.dart';
import 'package:hotel_pos/services/api_service.dart';
import 'package:hotel_pos/services/local_db.dart';

class POSController extends ChangeNotifier {
  final APIService _api = APIService.instance;
  final FlutterTts _tts = FlutterTts();

  // Master Data Cache
  List<CategoryModel> categories = [];
  List<ProductModel> products = [];
  List<DiningTableModel> diningTables = [];
  List<CustomerModel> customers = [];
  List<UserModel> waiters = [];

  // Local System States
  bool isOnline = false;
  bool isLoading = false;
  ShiftModel? activeShift;
  
  // Active POS Transaction Cart States
  List<OrderItemModel> cart = [];
  DiningTableModel? selectedTable;
  CustomerModel? selectedCustomer;
  String? stewardName;
  String orderType = 'takeaway'; // 'dine_in', 'takeaway', 'delivery'
  String? deliveryPlatform;     // 'uber_eats', 'pickme', 'phone', 'direct'
  
  // Discount States
  double rawDiscountValue = 0.00;
  String discountType = 'percent'; // 'percent', 'fixed'
  List<OfferModel> offers = [];
  List<Map<String, dynamic>> happyHours = [];
  
  String searchWord = '';
  int? activeCategoryId;
  
  // Real-time operations
  String? cardTerminalStatus; // 'idle', 'processing', 'approved', 'declined'
  String? cardTerminalTxRef;
  String? activeLankaQR;
  
  // KDS & Orders status lists
  List<OrderModel> activeOrders = [];
  String voiceLanguage = 'English';

  // Table persistent orders state
  Map<int, List<OrderItemModel>> tableCarts = {};
  Map<int, String> tableStatuses = {};
  Map<int, String?> tableStewards = {};
  Map<int, int> tableActiveOrderIds = {};

  void setVoiceLanguage(String lang) {
    if (voiceLanguage != lang) {
      voiceLanguage = lang;
      notifyListeners();
    }
  }

  String getTableStatus(DiningTableModel table) {
    if (tableCarts.containsKey(table.id) && tableCarts[table.id]!.isNotEmpty) {
      return tableStatuses[table.id] ?? 'seated';
    }
    return table.status;
  }

  void setTableStatus(int tableId, String status) async {
    tableStatuses[tableId] = status;
    if (isOnline) {
      try {
        await _api.updateTableStatus(tableId, status, stewardName: stewardName);
      } catch (_) {}
    }
    notifyListeners();
  }

  void markKotItemsAsSent() {
    for (int i = 0; i < cart.length; i++) {
      if (cart[i].status == 'pending') {
        final old = cart[i];
        cart[i] = OrderItemModel(
          id: old.id,
          orderId: old.orderId,
          productId: old.productId,
          productName: old.productName,
          productSinhalaName: old.productSinhalaName,
          quantity: old.quantity,
          price: old.price,
          notes: old.notes,
          status: 'preparing',
          isShortEat: old.isShortEat,
          extras: old.extras,
        );
      }
    }
    // Save updated cart to the table
    if (selectedTable != null) {
      final tid = selectedTable!.id;
      tableCarts[tid] = List.from(cart);
      tableStewards[tid] = stewardName;
      if (tableStatuses[tid] != 'billing') {
        tableStatuses[tid] = 'seated';
      }
      if (isOnline) {
        _api.updateTableStatus(tid, tableStatuses[tid]!, stewardName: stewardName);
      }
    }
    notifyListeners();
  }
  
  // Constructor
  POSController() {
    _initTts();
  }

  void _initTts() async {
    try {
      final List<dynamic> langs = await _tts.getLanguages;
      
      String targetLang = "si-LK";
      for (var l in langs) {
        if (l.toString().toLowerCase().startsWith("si")) {
          targetLang = l.toString();
          break;
        }
      }
      
      await _tts.setLanguage(targetLang);
    } catch (e) {
      print('TTS Language set error: $e');
      await _tts.setLanguage("en-US");
    }
    await _tts.setSpeechRate(0.55);
    await _tts.setVolume(1.0);
  }

  Future<void> speakVoiceMessage(String text, {String? language}) async {
    final activeLang = language ?? voiceLanguage;
    final bool isSinhala = activeLang == 'Sinhala';

    if (isSinhala) {
      // Check if Sinhala is supported locally on the OS
      bool localSinhalaSupported = false;
      try {
        final List<dynamic> langs = await _tts.getLanguages;
        for (var l in langs) {
          if (l.toString().toLowerCase().startsWith("si")) {
            localSinhalaSupported = true;
            break;
          }
        }
      } catch (_) {}

      if (localSinhalaSupported) {
        try {
          await _tts.setLanguage("si-LK");
          await _tts.speak(text);
        } catch (e) {
          print('TTS Error: $e');
        }
      } else {
        // Fallback: Online Google TTS API played via native Windows MediaPlayer
        try {
          final encodedText = Uri.encodeComponent(text);
          final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=si&client=tw-ob&q=$encodedText';
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            final tempDir = Directory.systemTemp;
            final tempFile = File('${tempDir.path}${Platform.pathSeparator}tts_speech.mp3');
            await tempFile.writeAsBytes(response.bodyBytes);
            await _playMp3Windows(tempFile.path);
          } else {
            print('Google TTS Request failed: ${response.statusCode}');
          }
        } catch (e) {
          print('Google TTS Fallback Error: $e');
          // Final fallback: try standard TTS anyway
          try {
            await _tts.speak(text);
          } catch (_) {}
        }
      }
    } else {
      // English TTS voice
      try {
        await _tts.setLanguage("en-US");
        await _tts.speak(text);
      } catch (e) {
        print('English TTS Error: $e');
      }
    }
  }

  Future<void> _playMp3Windows(String filePath) async {
    try {
      // Escape backslashes for PowerShell double quotes
      final escapedPath = filePath.replaceAll(r'\', r'\\');
      final script = 'Add-Type -AssemblyName presentationCore; \$m = New-Object System.Windows.Media.MediaPlayer; \$m.Open("$escapedPath"); \$m.Play(); Start-Sleep -s 12';
      await Process.run('powershell', ['-c', script]);
    } catch (e) {
      print('Error playing audio via PowerShell: $e');
    }
  }

  String getSinhalaQuantityText(int qty) {
    switch (qty) {
      case 1: return "එකක්";
      case 2: return "දෙකක්";
      case 3: return "තුනක්";
      case 4: return "හතරක්";
      case 5: return "පහක්";
      case 6: return "හයක්";
      case 7: return "හතක්";
      case 8: return "අටක්";
      case 9: return "නමයක්";
      case 10: return "දහයක්";
      default: return "$qty ක්";
    }
  }

  // Load and refresh POS local environment
  Future<void> reloadEnvironment() async {
    isLoading = true;
    notifyListeners();

    isOnline = await _api.checkOnline();
    
    // Sync offline logs first if online
    if (isOnline) {
      final syncResult = await _api.syncOfflineData();
      if (syncResult != null) {
        print('Background synchronization complete!');
      }
    }

    try {
      if (isOnline) {
        categories = await _api.getCategories();
        products = await _api.getProducts();
        diningTables = await _api.getTables();
        customers = await _api.getCustomers();
        waiters = await _api.getUsers(role: 'waiter');
        activeShift = await _api.getCurrentShift();
        offers = await _api.getOffers();
        happyHours = await _api.getHappyHours();
        await _fetchActiveOrders();
      } else {
        // Fallback: If completely offline in LAN-first mode,
        // we can fetch last cached settings from SharedPreferences
        // or local SQLite databases.
        print('Offline mode. Using local caching elements.');
      }
    } catch (e, stackTrace) {
      print('Environment load error: $e');
      print(stackTrace);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Set up listener for WebSocket Events
  void setupEventSubscription() {
    _api.eventStream.listen((event) {
      print('POS Event Received: ${event['type']}');
      switch (event['type']) {
        case 'table_status_changed':
        case 'happy_hour_updated':
        case 'database_synchronized':
          reloadEnvironment();
          break;
        case 'stock_updated':
          final data = event['data'];
          final pIndex = products.indexWhere((p) => p.id == data['productId']);
          if (pIndex != -1) {
            final old = products[pIndex];
            products[pIndex] = ProductModel(
              id: old.id,
              name: old.name,
              sinhalaName: old.sinhalaName,
              description: old.description,
              categoryId: old.categoryId,
              price: old.price,
              cost: old.cost,
              activePrice: old.activePrice,
              isHappyHour: old.isHappyHour,
              barcode: old.barcode,
              stockQty: data['stock_qty'],
              minStockLevel: old.minStockLevel,
              isShortEat: old.isShortEat,
              imageBase64: old.imageBase64,
              status: old.status,
              itemType: old.itemType,
              tax: old.tax,
              isFeatured: old.isFeatured,
              caution: old.caution,
              hasSizes: old.hasSizes,
              hasExtras: old.hasExtras,
              hasAddons: old.hasAddons,
              sizes: old.sizes,
              extras: old.extras,
              addons: old.addons,
            );
            notifyListeners();
          }
          break;
        case 'card_machine_status':
          final data = event['data'];
          cardTerminalStatus = data['state'];
          notifyListeners();
          break;
        case 'card_machine_feedback':
          final data = event['data'];
          if (data['success']) {
            cardTerminalStatus = 'approved';
            cardTerminalTxRef = data['approval_code'];
          } else {
            cardTerminalStatus = 'declined';
            cardTerminalTxRef = null;
          }
          notifyListeners();
          break;
        case 'kot_trigger_voice':
          // Synthesize voice message to chefs
          final data = event['data'];
          final items = data['items'] as List;
          
          // Filter items by checking if the product is a KOT item
          final kotItems = items.where((i) {
            final productId = i['product_id'];
            final p = products.firstWhere(
              (prod) => prod.id == productId,
              orElse: () => ProductModel(
                id: 0,
                name: '',
                categoryId: 0,
                price: 0,
                cost: 0,
                activePrice: 0,
                isHappyHour: false,
                stockQty: 0,
                minStockLevel: 0,
                isShortEat: false,
                isKotItem: false,
              ),
            );
            return p.id != 0 && p.isKotItem;
          }).toList();
          
          if (kotItems.isNotEmpty) {
            String msg = "නව මුළුතැන්ගෙයි ඇණවුම: ";
            for (var k in kotItems) {
              final productId = k['product_id'];
              final p = products.firstWhere(
                (prod) => prod.id == productId,
                orElse: () => ProductModel(
                  id: 0,
                  name: k['product_name'] ?? '',
                  sinhalaName: k['product_sinhala_name'] ?? k['product_name'] ?? '',
                  categoryId: 0,
                  price: 0,
                  cost: 0,
                  activePrice: 0,
                  isHappyHour: false,
                  stockQty: 0,
                  minStockLevel: 0,
                  isShortEat: false,
                  isKotItem: false,
                ),
              );
              final itemName = p.sinhalaName != null && p.sinhalaName!.isNotEmpty
                  ? p.sinhalaName
                  : p.name;
              final qtyVal = int.tryParse(k['quantity'].toString()) ?? 1;
              final qtyText = getSinhalaQuantityText(qtyVal);
              msg += "$itemName $qtyText. ";
            }
            speakVoiceMessage(msg);
          }
          break;
        case 'order_created':
        case 'order_updated':
          _fetchActiveOrders();
          break;
        case 'offer_created':
        case 'offer_updated':
        case 'offer_deleted':
          reloadEnvironment();
          break;
      }
    });
  }

  Future<void> _fetchActiveOrders() async {
    if (isOnline) {
      try {
        final ords = await _api.getOrders();
        // filter orders from today / active shifts
        activeOrders = ords.where((o) => o.status != 'delivered' && o.status != 'cancelled').toList();
        
        // Restore Dine-In tables state from active unpaid orders (e.g. after a power cut or restart)
        final activeDineInOrders = activeOrders.where((o) => o.orderType == 'dine_in' && o.tableId != null).toList();
        for (var o in activeDineInOrders) {
          final tid = o.tableId!;
          if (!tableCarts.containsKey(tid) || tableCarts[tid]!.isEmpty) {
            final items = await _api.getOrderItems(o.id!);
            tableCarts[tid] = items;
            tableActiveOrderIds[tid] = o.id!;
            tableStewards[tid] = o.stewardName;
            tableStatuses[tid] = o.ackPrinted ? 'billing' : 'seated';
          }
        }
        notifyListeners();
      } catch (_) {}
    }
  }

  // ----------------------------------------------------
  // CART ACTIONS
  // ----------------------------------------------------

  double get cartSubtotal {
    return cart.fold(0.00, (sum, item) {
      ProductModel? p;
      for (var prod in products) {
        if (prod.id == item.productId) {
          p = prod;
          break;
        }
      }
      double diff = 0.0;
      if (p != null && !p.hasSizes) {
        final activePrice = getProductActivePrice(p);
        if (activePrice < p.price) {
          diff = p.price - activePrice;
        }
      }
      final originalPrice = item.price + diff;
      return sum + (originalPrice * item.quantity);
    });
  }

  double get discount {
    // 1. Calculate Happy Hour discount
    double hhDiscount = cart.fold(0.00, (sum, item) {
      ProductModel? p;
      for (var prod in products) {
        if (prod.id == item.productId) {
          p = prod;
          break;
        }
      }
      double diff = 0.0;
      if (p != null && !p.hasSizes) {
        final activePrice = getProductActivePrice(p);
        if (activePrice < p.price) {
          diff = p.price - activePrice;
        }
      }
      return sum + (diff * item.quantity);
    });

    // 2. Calculate manual discount on the remaining subtotal
    double subtotalAfterHh = cartSubtotal - hhDiscount;
    double manualDiscountValue = 0.00;
    if (discountType == 'percent') {
      manualDiscountValue = subtotalAfterHh * (rawDiscountValue / 100.0);
    } else {
      manualDiscountValue = rawDiscountValue;
    }

    return hhDiscount + manualDiscountValue;
  }

  double get cartTotal {
    final sub = cartSubtotal;
    final tot = sub - discount;
    return tot < 0 ? 0.00 : tot;
  }

  void setOrderType(String type) {
    if (orderType == 'dine_in' && selectedTable != null) {
      final oldTid = selectedTable!.id;
      if (cart.isNotEmpty) {
        tableCarts[oldTid] = List.from(cart);
        tableStewards[oldTid] = stewardName;
        if (tableStatuses[oldTid] != 'billing') {
          tableStatuses[oldTid] = 'seated';
        }
        if (isOnline) {
          _api.updateTableStatus(oldTid, tableStatuses[oldTid]!, stewardName: stewardName);
        }
      } else {
        tableCarts.remove(oldTid);
        tableStewards.remove(oldTid);
        tableStatuses[oldTid] = 'empty';
        if (isOnline) {
          _api.updateTableStatus(oldTid, 'empty');
        }
      }
    }

    orderType = type;
    if (type != 'dine_in') {
      selectedTable = null;
      stewardName = null;
      cart = [];
    } else {
      cart = [];
    }
    notifyListeners();
  }

  void setDeliveryPlatform(String? platform) {
    deliveryPlatform = platform;
    notifyListeners();
  }

  void selectTable(DiningTableModel? table) {
    if (orderType == 'dine_in' && selectedTable != null) {
      final oldTid = selectedTable!.id;
      if (cart.isNotEmpty) {
        tableCarts[oldTid] = List.from(cart);
        tableStewards[oldTid] = stewardName;
        if (tableStatuses[oldTid] != 'billing') {
          tableStatuses[oldTid] = 'seated';
        }
        if (isOnline) {
          _api.updateTableStatus(oldTid, tableStatuses[oldTid]!, stewardName: stewardName);
        }
      } else {
        tableCarts.remove(oldTid);
        tableStewards.remove(oldTid);
        tableStatuses[oldTid] = 'empty';
        if (isOnline) {
          _api.updateTableStatus(oldTid, 'empty');
        }
      }
    }

    selectedTable = table;

    if (table != null) {
      cart = List.from(tableCarts[table.id] ?? []);
      stewardName = tableStewards[table.id] ?? table.stewardName;
      if (cart.isEmpty) {
        rawDiscountValue = 0.00;
        discountType = 'percent';
      } else {
        autoApplyActiveOffer();
      }
    } else {
      cart = [];
      stewardName = null;
    }
    notifyListeners();
  }

  void selectCustomer(CustomerModel? customer) {
    selectedCustomer = customer;
    notifyListeners();
  }

  void setStewardName(String? name) {
    stewardName = name;
    notifyListeners();
  }

  void setDiscount(double amount) {
    rawDiscountValue = amount;
    discountType = 'fixed';
    notifyListeners();
  }

  void updateDiscount(double value, String type) {
    rawDiscountValue = value;
    discountType = type;
    notifyListeners();
  }

  void autoApplyActiveOffer() {
    OfferModel? activeOffer;
    for (var o in offers) {
      if (o.status == 'active') {
        activeOffer = o;
        break;
      }
    }

    if (activeOffer != null) {
      rawDiscountValue = activeOffer.discountPercentage;
      discountType = 'percent';
    } else {
      rawDiscountValue = 0.00;
      discountType = 'percent';
    }
  }

  double getProductActivePrice(ProductModel product) {
    final now = DateTime.now();
    final currentDay = now.weekday; // 1=Mon, 7=Sun
    final currentMin = now.hour * 60 + now.minute;
    
    for (var hp in happyHours) {
      if (hp['product_id'] == product.id && hp['status'] == 'active') {
        final daysStr = hp['days_of_week']?.toString() ?? '1,2,3,4,5,6,7';
        final days = daysStr.split(',').map((e) => int.tryParse(e.trim())).toList();
        if (days.contains(currentDay)) {
          final startMin = _parseTimeToMinutes(hp['start_time']?.toString() ?? '');
          final endMin = _parseTimeToMinutes(hp['end_time']?.toString() ?? '');
          if (startMin != null && endMin != null) {
            if (currentMin >= startMin && currentMin <= endMin) {
              return toDouble(hp['promo_price']);
            }
          }
        }
      }
    }
    return product.price;
  }

  int? _parseTimeToMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.isEmpty) return null;
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return hour * 60 + minute;
    } catch (_) {
      return null;
    }
  }

  void setSearchWord(String word) {
    searchWord = word;
    notifyListeners();
  }

  void filterCategory(int? categoryId) {
    activeCategoryId = categoryId;
    notifyListeners();
  }

  void addToCart(ProductModel product, {int quantity = 1, String? notes, List<ProductExtra> extras = const [], double? customPrice}) {
    final currentPrice = customPrice ?? getProductActivePrice(product);
    final wasEmpty = cart.isEmpty;
    
    // Check if product is already in the cart with status 'pending'
    final index = cart.indexWhere((item) => item.productId == product.id && item.notes == notes && item.status == 'pending');
    
    if (index != -1) {
      final oldItem = cart[index];
      cart[index] = OrderItemModel(
        id: oldItem.id,
        orderId: oldItem.orderId,
        productId: oldItem.productId,
        productName: oldItem.productName,
        productSinhalaName: oldItem.productSinhalaName,
        quantity: oldItem.quantity + quantity,
        price: currentPrice,
        notes: oldItem.notes,
        status: 'pending',
        isShortEat: oldItem.isShortEat,
        extras: oldItem.extras.isNotEmpty ? oldItem.extras : extras,
      );
    } else {
      cart.add(OrderItemModel(
        productId: product.id,
        productName: product.name,
        productSinhalaName: product.sinhalaName,
        quantity: quantity,
        price: currentPrice,
        notes: notes,
        status: 'pending',
        isShortEat: product.isShortEat,
        extras: extras,
      ));
    }

    if (wasEmpty) {
      autoApplyActiveOffer();
    }

    notifyListeners();
  }

  void updateCartQuantity(int index, int quantity) {
    if (quantity <= 0) {
      cart.removeAt(index);
      if (cart.isEmpty) {
        rawDiscountValue = 0.00;
        discountType = 'percent';
      }
    } else {
      final old = cart[index];
      cart[index] = OrderItemModel(
        id: old.id,
        orderId: old.orderId,
        productId: old.productId,
        productName: old.productName,
        productSinhalaName: old.productSinhalaName,
        quantity: quantity,
        price: old.price,
        notes: old.notes,
        status: old.status,
        isShortEat: old.isShortEat,
        extras: old.extras,
      );
    }
    notifyListeners();
  }

  void updateCartNotes(int index, String? notes) {
    final old = cart[index];
    cart[index] = OrderItemModel(
      id: old.id,
      orderId: old.orderId,
      productId: old.productId,
      productName: old.productName,
      productSinhalaName: old.productSinhalaName,
      quantity: old.quantity,
      price: old.price,
      notes: notes,
      status: old.status,
      isShortEat: old.isShortEat,
      extras: old.extras,
    );
    notifyListeners();
  }

  void clearCart() {
    if (selectedTable != null) {
      final tid = selectedTable!.id;
      tableCarts.remove(tid);
      tableStewards.remove(tid);
      tableStatuses[tid] = 'empty';
      if (isOnline) {
        _api.updateTableStatus(tid, 'empty');
      }
    }
    cart.clear();
    selectedTable = null;
    selectedCustomer = null;
    stewardName = null;
    deliveryPlatform = null;
    rawDiscountValue = 0.00;
    discountType = 'percent';
    activeLankaQR = null;
    cardTerminalStatus = null;
    cardTerminalTxRef = null;
    notifyListeners();
  }

  // ----------------------------------------------------
  // TRANSACTION SUBMISSIONS & FLOWS
  // ----------------------------------------------------

  // 1. Shift actions
  Future<void> openNewShift(double openingBalance) async {
    if (isOnline) {
      activeShift = await _api.openShift(openingBalance);
    } else {
      final s = ShiftModel(
        id: DateTime.now().millisecondsSinceEpoch,
        userId: _api.currentUser?.id ?? 1,
        startTime: DateTime.now().toIso8601String(),
        openingBalance: openingBalance,
        closingBalance: 0,
        actualClosingBalance: 0,
        status: 'open',
      );
      await LocalDB.instance.saveShiftOffline(s);
      activeShift = s;
      await LocalDB.instance.saveAuditOffline('modify_bill', 'shifts', s.id, 'Offline Shift opened', _api.currentUser?.id ?? 1);
    }
    notifyListeners();
  }

  Future<void> closeActiveShift(double closingBalance, double actualClosingBalance) async {
    if (activeShift == null) return;
    
    if (isOnline) {
      await _api.closeShift(activeShift!.id, closingBalance, actualClosingBalance);
    } else {
      final s = ShiftModel(
        id: activeShift!.id,
        userId: activeShift!.userId,
        startTime: activeShift!.startTime,
        endTime: DateTime.now().toIso8601String(),
        openingBalance: activeShift!.openingBalance,
        closingBalance: closingBalance,
        actualClosingBalance: actualClosingBalance,
        status: 'closed',
      );
      await LocalDB.instance.saveShiftOffline(s);
      await LocalDB.instance.saveAuditOffline('modify_bill', 'shifts', s.id, 'Offline Shift closed', _api.currentUser?.id ?? 1);
    }
    activeShift = null;
    notifyListeners();
  }

  Future<double> getShiftCashSales() async {
    if (activeShift == null) return 0.0;
    try {
      final ords = await _api.getOrders();
      final shiftOrders = ords.where((o) => 
          o.shiftId == activeShift!.id && 
          o.paymentStatus == 'paid' && 
          o.paymentMethod == 'cash'
      );
      return shiftOrders.fold<double>(0.0, (sum, o) => sum + o.total);
    } catch (_) {
      return 0.0;
    }
  }

  Future<double> getExpectedDrawerBalance() async {
    if (activeShift == null) return 0.0;
    double balance = activeShift!.openingBalance;
    
    // 1. Fetch cash sales
    try {
      final ords = await _api.getOrders();
      final shiftOrders = ords.where((o) => 
          o.shiftId == activeShift!.id && 
          o.paymentStatus == 'paid' && 
          o.paymentMethod == 'cash'
      );
      final cashSales = shiftOrders.fold<double>(0.0, (sum, o) => sum + o.total);
      balance += cashSales;
    } catch (_) {}

    // 2. Fetch adjustments
    try {
      final logs = await _api.getDrawerLogs(activeShift!.id);
      for (var log in logs) {
        final double amt = double.tryParse(log['amount']?.toString() ?? '0') ?? 0.0;
        if (log['type'] == 'cash_in') {
          balance += amt;
        } else if (log['type'] == 'cash_out') {
          balance -= amt;
        }
      }
    } catch (_) {}
    
    return balance;
  }

  // 2. Place order (Dine-in, Takeaway, Delivery)
  Future<Map<String, dynamic>> placeOrder({
    required bool printKOT,
    required bool printAck,
    required String status, // 'pending', 'preparing'
    required String paymentStatus, // 'unpaid', 'paid'
    String? paymentMethod,
    double receivedAmount = 0.00,
    double changeAmount = 0.00,
    bool clearCartAfter = true,
  }) async {
    if (cart.isEmpty) throw Exception('Cart is empty');
    if (activeShift == null) throw Exception('No active shift. Please open a shift.');
    
    // Generate order number for offline fallback
    final dateStr = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final offlineOrderNum = 'ORD-$dateStr-$timestamp';

    final order = OrderModel(
      orderNumber: offlineOrderNum,
      tableId: selectedTable?.id,
      orderType: orderType,
      deliveryPlatform: deliveryPlatform,
      customerId: selectedCustomer?.id ?? 1, // Default walking customer
      stewardName: stewardName,
      status: status,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      subtotal: cartSubtotal,
      discount: discount,
      total: cartTotal,
      cashierId: _api.currentUser?.id ?? 1,
      shiftId: activeShift!.id,
      kotPrinted: printKOT,
      ackPrinted: printAck,
      cardTxReference: cardTerminalTxRef,
      barcode: offlineOrderNum,
      createdAt: DateTime.now().toIso8601String(),
      receivedAmount: receivedAmount,
      changeAmount: changeAmount,
      items: cart,
    );

    int orderId = 0;
    String orderNum = offlineOrderNum;

    if (isOnline) {
      final res = await _api.placeOrderOnline(order);
      orderId = res['orderId'] ?? 0;
      orderNum = res['order_number'] ?? offlineOrderNum;
      print('Order placed online successfully: $orderNum');
    } else {
      // Offline implementation
      orderId = await LocalDB.instance.saveOrderOffline(order);
      await LocalDB.instance.saveAuditOffline('modify_bill', 'orders', null, 'Offline order created: $offlineOrderNum', _api.currentUser?.id ?? 1);
      
      // Stock adjustment offline mock
      for (var item in cart) {
        await LocalDB.instance.saveStockLogOffline(item.productId, -item.quantity, 'sale', 'Offline sale $offlineOrderNum', _api.currentUser?.id ?? 1);
      }
      
      // Credit settlement outstanding balance offline mock
      if (paymentMethod == 'credit' && selectedCustomer != null) {
        final custIndex = customers.indexWhere((c) => c.id == selectedCustomer!.id);
        if (custIndex != -1) {
          final old = customers[custIndex];
          customers[custIndex] = CustomerModel(
            id: old.id,
            name: old.name,
            phone: old.phone,
            birthday: old.birthday,
            favoriteItems: old.favoriteItems,
            creditLimit: old.creditLimit,
            outstandingBalance: old.outstandingBalance + order.total,
          );
        }
      }
      print('Order saved offline successfully: $orderNum');
    }
    
    // Clear and reload
    if (clearCartAfter) {
      clearCart();
    }
    await reloadEnvironment();

    return {
      'orderId': orderId,
      'orderNumber': orderNum,
    };
  }

  // 3. Process Card machine charge
  Future<void> chargeCardMachine() async {
    if (cart.isEmpty) return;
    cardTerminalStatus = 'processing';
    cardTerminalTxRef = null;
    notifyListeners();
    
    final mockOrderNum = 'TX-${DateTime.now().millisecondsSinceEpoch}';
    if (isOnline) {
      await _api.initiateCardPayment(cartTotal, mockOrderNum);
    } else {
      // Simulate offline card flow approval after 3 seconds
      Timer(const Duration(seconds: 3), () {
        cardTerminalStatus = 'approved';
        cardTerminalTxRef = 'OFFLINE-APP-1234';
        notifyListeners();
      });
    }
  }

  // 4. Generate LankaQR EmvCo string
  Future<void> generateLankaQR() async {
    if (cart.isEmpty) return;
    final mockOrderNum = 'QR-${DateTime.now().millisecondsSinceEpoch}';
    if (isOnline) {
      final qr = await _api.getLankaQR(cartTotal, mockOrderNum);
      activeLankaQR = qr['payload'];
    } else {
      // Offline LankaQR generation fallback
      activeLankaQR = '00020101021226500013lk.lankaqr.pay011112345678901020499995204581253031445407${cartTotal}5802LK5911HotelPOS-LK6007Colombo62230111$mockOrderNum-OFFLINE';
    }
    notifyListeners();
  }

  // List of filtered products based on search word and selected category
  List<ProductModel> get filteredProducts {
    return products.where((p) {
      final matchSearch = p.name.toLowerCase().contains(searchWord.toLowerCase()) || 
                          (p.sinhalaName != null && p.sinhalaName!.toLowerCase().contains(searchWord.toLowerCase())) ||
                          (p.barcode != null && p.barcode == searchWord);
      
      final matchCategory = activeCategoryId == null || p.categoryId == activeCategoryId;
      
      return matchSearch && matchCategory;
    }).toList();
  }
}
