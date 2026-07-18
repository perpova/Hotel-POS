import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:hotel_pos/models/models.dart';
import 'package:hotel_pos/services/api_service.dart';
import 'package:hotel_pos/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

class POSController extends ChangeNotifier {
  static String appVersion = '0.0.0';

  final APIService _api = APIService.instance;
  final FlutterTts _tts = FlutterTts();

  // Master Data Cache
  List<CategoryModel> categories = [];
  List<ProductModel> products = [];
  List<DiningTableModel> diningTables = [];
  List<CustomerModel> customers = [];
  List<UserModel> waiters = [];
  List<IngredientModel> ingredients = [];

  int get lowStockIngredientsCount {
    return ingredients.where((i) => i.stockQty <= i.minStockLevel).length;
  }

  // Local System States
  bool isOnline = false;
  bool isLoading = false;
  ShiftModel? activeShift;
  
  // Active POS Transaction Cart States
  List<OrderItemModel> cart = [];
  DiningTableModel? selectedTable;
  CustomerModel? selectedCustomer;
  double activePreOrderAdvance = 0.00;
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
  List<dynamic> drawerLogs = [];

  // KOT Custom Sound Settings per Category
  // Map of categoryId -> { 'soundType': 'default'|'custom', 'soundBase64': '...', 'filename': '...' }
  Map<int, Map<String, dynamic>> categorySounds = {};

  // Audio Recording Process references
  Process? _recordingProcess;
  String? _recordingTempPath;

  bool get isRecording => _recordingProcess != null;

  // Pre-orders and Notifications States
  List<dynamic> preOrders = [];
  List<dynamic> notifications = [];
  int unreadNotificationCount = 0;
  int? activePreOrderId;
  int? requestedScreenIndex;

  void navigateToScreen(int index) {
    requestedScreenIndex = index;
    notifyListeners();
  }

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
    loadKotSoundSettings();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final activeLang = language ?? voiceLanguage;
      final bool isSinhala = activeLang == 'Sinhala' || RegExp(r'[\u0d80-\u0dff]').hasMatch(text);

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
            final response = await http.get(
              Uri.parse(url),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              },
            );
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
    });
  }

  Future<void> _playMp3Windows(String filePath) async {
    try {
      final tempDir = Directory.systemTemp;
      final playScriptFile = File('${tempDir.path}${Platform.pathSeparator}kot_play_${DateTime.now().millisecondsSinceEpoch}.ps1');
      
      final playScriptContent = 
        'Add-Type -AssemblyName presentationCore; '
        '\$m = New-Object System.Windows.Media.MediaPlayer; '
        '\$m.Open(\'$filePath\'); '
        '\$m.Play(); '
        'Start-Sleep -s 12; ';
        
      await playScriptFile.writeAsString(playScriptContent);
      await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', playScriptFile.path]);
      try {
        await playScriptFile.delete();
      } catch (_) {}
    } catch (e) {
      print('Error playing audio via PowerShell: $e');
    }
  }

  Future<void> loadKotSoundSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      categorySounds.clear();
      for (var key in keys) {
        if (key.startsWith('kot_sound_cat_')) {
          final parts = key.split('_');
          if (parts.length == 4) {
            final catId = int.tryParse(parts[3]);
            if (catId != null) {
              final jsonStr = prefs.getString(key);
              if (jsonStr != null) {
                categorySounds[catId] = Map<String, dynamic>.from(jsonDecode(jsonStr));
              }
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      print('Error loading KOT sound settings: $e');
    }
  }

  Future<void> saveKotSoundSetting(int categoryId, String soundType, {String? soundBase64, String? filename}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'kot_sound_cat_$categoryId';
      final Map<String, dynamic> setting = {
        'soundType': soundType,
        'soundBase64': soundBase64,
        'filename': filename,
      };
      categorySounds[categoryId] = setting;
      await prefs.setString(key, jsonEncode(setting));
      notifyListeners();
    } catch (e) {
      print('Error saving KOT sound setting: $e');
    }
  }

  Future<void> removeKotSoundSetting(int categoryId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'kot_sound_cat_$categoryId';
      categorySounds.remove(categoryId);
      await prefs.remove(key);
      notifyListeners();
    } catch (e) {
      print('Error removing KOT sound setting: $e');
    }
  }

  Future<void> playCustomSoundForCategory(int categoryId) async {
    final setting = categorySounds[categoryId];
    if (setting != null && setting['soundType'] == 'custom' && setting['soundBase64'] != null) {
      try {
        final tempDir = Directory.systemTemp;
        final filename = setting['filename']?.toString() ?? 'sound.wav';
        final extIndex = filename.lastIndexOf('.');
        final extension = extIndex != -1 ? filename.substring(extIndex) : '.wav';
        
        final tempFile = File('${tempDir.path}${Platform.pathSeparator}kot_cat_${categoryId}_${DateTime.now().millisecondsSinceEpoch}$extension');
        await tempFile.writeAsBytes(base64Decode(setting['soundBase64']));
        await _playMp3Windows(tempFile.path);
        
        Future.delayed(const Duration(seconds: 15), () async {
          try {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (_) {}
        });
      } catch (e) {
        print('Error playing custom category sound: $e');
      }
    }
  }

  Future<void> startRecording() async {
    try {
      final tempDir = Directory.systemTemp;
      _recordingTempPath = '${tempDir.path}${Platform.pathSeparator}kot_record.wav';
      final file = File(_recordingTempPath!);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final scriptFile = File('${tempDir.path}${Platform.pathSeparator}kot_recorder.ps1');
      final nativePath = _recordingTempPath!;
      final scriptContent = 
        '\$outputPath = \'$nativePath\';\n' +
        r'''
        $dynAssembly = New-Object System.Reflection.AssemblyName('Win32')
        $assemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($dynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
        $moduleBuilder = $assemblyBuilder.DefineDynamicModule('Win32')
        $typeBuilder = $moduleBuilder.DefineType('AudioRecorder', 'Public, Class')
        $mciSignature = $typeBuilder.DefineMethod('mciSendString', [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl', [long], [type[]]@([string], [System.Text.StringBuilder], [int], [IntPtr]))
        $dllImportAttr = [System.Runtime.InteropServices.DllImportAttribute].GetConstructor([string])
        $attrBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($dllImportAttr, @('winmm.dll'))
        $mciSignature.SetCustomAttribute($attrBuilder)
        $type = $typeBuilder.CreateType()

        $type::mciSendString("open new Type waveaudio Alias recsound", $null, 0, [IntPtr]::Zero)
        $type::mciSendString("record recsound", $null, 0, [IntPtr]::Zero)
        $null = Read-Host
        $type::mciSendString("save recsound `"$outputPath`"", $null, 0, [IntPtr]::Zero)
        $type::mciSendString("close recsound", $null, 0, [IntPtr]::Zero)
        ''';

      await scriptFile.writeAsString(scriptContent);
      _recordingProcess = await Process.start('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path]);
      notifyListeners();
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (_recordingProcess != null && _recordingTempPath != null) {
        _recordingProcess!.stdin.writeln();
        await _recordingProcess!.exitCode;
        _recordingProcess = null;
        notifyListeners();

        final file = File(_recordingTempPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          try {
            await file.delete();
          } catch (_) {}
          return base64Encode(bytes);
        }
      }
    } catch (e) {
      print('Error stopping recording: $e');
    }
    _recordingProcess = null;
    notifyListeners();
    return null;
  }

  String buildSinhalaKOTVoiceMessage(List<dynamic> items, {String? orderType, String? tableName}) {
    const Map<String, String> ingredientTranslations = {
      'egg': 'බිත්තර',
      'eggs': 'බිත්තර',
      'cheese': 'චීස්',
      'chicken': 'චිකන්',
      'sausage': 'සොසේජස්',
      'sausages': 'සොසේජස්',
      'fish': 'මාළු',
      'vegetable': 'එළවළු',
      'vegetables': 'එළවළු',
      'onion': 'ලූණු',
      'onions': 'ලූණු',
      'chilli': 'මිරිස්',
      'chili': 'මිරිස්',
      'tomato': 'තක්කාලි',
      'tomatoes': 'තක්කාලි',
    };

    String msg = 'නව මුළුතැන්ගෙයි ඇණවුම: ';
    if (orderType == 'dine_in' || orderType == 'Dining Table') {
      if (tableName != null) {
        final cleanTable = tableName.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanTable.isNotEmpty) {
          msg += "මේසය අංක $cleanTable, ";
        } else {
          msg += "මේසය $tableName, ";
        }
      } else {
        msg += "මේසය, ";
      }
    } else if (orderType == 'takeaway' || orderType == 'Takeaway') {
      msg += "ටේක් අවේ ඇණවුම, ";
    } else if (orderType == 'delivery' || orderType == 'Delivery') {
      msg += "ඩිලිවරි ඇණවුම, ";
    }
    for (var item in items) {
      final int productId = item is Map
          ? (int.tryParse(item['product_id']?.toString() ?? '') ?? 0)
          : item.productId;
      
      final p = products.firstWhere(
        (prod) => prod.id == productId,
        orElse: () => ProductModel(id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false),
      );
      
      final String name = p.id != 0 && p.sinhalaName != null && p.sinhalaName!.isNotEmpty
          ? p.sinhalaName!
          : (item is Map 
              ? (item['product_sinhala_name'] ?? item['product_name'] ?? '') 
              : (item.productSinhalaName ?? item.productName));
      
      final int qty = item is Map
          ? (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1)
          : item.quantity;
          
      final String? notes = item is Map
          ? item['notes']?.toString()
          : item.notes;

      String itemDetails = '';
      if (notes != null && notes.isNotEmpty) {
        final parts = notes.split(' | ');
        final List<String> detailsList = [];
        for (var part in parts) {
          if (part.startsWith('Size: ')) {
            final sizeVal = part.replaceFirst('Size: ', '');
            String sizeSinhala = sizeVal;
            if (sizeVal.toLowerCase() == 'large') sizeSinhala = 'ලොකු';
            else if (sizeVal.toLowerCase() == 'medium') sizeSinhala = 'මධ්‍යම';
            else if (sizeVal.toLowerCase() == 'small') sizeSinhala = 'කුඩා';
            detailsList.add("$sizeSinhala ප්‍රමාණය");
          } else if (part.startsWith('Extras: ')) {
            final extrasVal = part.replaceFirst('Extras: ', '');
            final regex = RegExp(r"^(.*?)\s*\(x(\d+)\)$");
            final match = regex.firstMatch(extrasVal);
            
            String extraName = extrasVal;
            int qtyVal = 1;
            if (match != null) {
              extraName = match.group(1) ?? extrasVal;
              qtyVal = int.tryParse(match.group(2) ?? '1') ?? 1;
            }
            
            final cleanExtraKey = extraName.trim().toLowerCase();
            final translatedName = ingredientTranslations[cleanExtraKey] ?? extraName;
            final qtySinhala = getSinhalaQuantityText(qtyVal);
            detailsList.add("$translatedName $qtySinhala වැඩිපුර");
          } else if (part.startsWith('Instructions: ')) {
            final instVal = part.replaceFirst('Instructions: ', '');
            detailsList.add(instVal);
          }
        }
        if (detailsList.isNotEmpty) {
          itemDetails = " (${detailsList.join(', ')})";
        }
      }

      final qtyText = getSinhalaQuantityText(qty);
      msg += "$name $qtyText$itemDetails, ";
    }
    return msg;
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
        ingredients = await _api.getIngredients();
        await _fetchActiveOrders();
        await fetchDrawerLogs();
        await fetchPreOrders();
        await fetchNotifications();
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
        case 'shift_updated':
        case 'ingredient_stock_updated':
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
          final orderType = data['orderType']?.toString();
          final tableName = data['tableName']?.toString();
          
          // Filter items by checking if the product is a KOT item AND is pending (newly added)
          final kotItems = items.where((i) {
            final productId = int.tryParse(i['product_id']?.toString() ?? '') ?? 0;
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
            final String itemStatus = i['status']?.toString() ?? 'pending';
            return p.id != 0 && p.isKotItem && itemStatus == 'pending';
          }).toList();
          
          if (kotItems.isNotEmpty) {
            final Map<int, List<dynamic>> itemsByCategory = {};
            for (var item in kotItems) {
              final productId = int.tryParse(item['product_id']?.toString() ?? '') ?? 0;
              final p = products.firstWhere((prod) => prod.id == productId, orElse: () => products.first);
              if (p.id != 0) {
                itemsByCategory.putIfAbsent(p.categoryId, () => []).add(item);
              }
            }

            final List<dynamic> ttsItems = [];
            
            Future.sync(() async {
              for (var entry in itemsByCategory.entries) {
                final catId = entry.key;
                final catItems = entry.value;
                final soundSetting = categorySounds[catId];
                if (soundSetting != null && soundSetting['soundType'] == 'custom' && soundSetting['soundBase64'] != null) {
                  await playCustomSoundForCategory(catId);
                } else {
                  ttsItems.addAll(catItems);
                }
              }

              if (ttsItems.isNotEmpty) {
                final msg = buildSinhalaKOTVoiceMessage(ttsItems, orderType: orderType, tableName: tableName);
                await speakVoiceMessage(msg);
              }
            });
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
        case 'new_notification':
        case 'notifications_read_all':
        case 'notification_read':
          fetchNotifications();
          break;
        case 'pre_order_created':
        case 'pre_order_updated':
        case 'pre_order_deleted':
          fetchPreOrders();
          break;
      }
    });
  }

  Future<void> _fetchActiveOrders() async {
    if (isOnline) {
      try {
        final ords = await _api.getOrders();
        // filter orders from today / active shifts
        final unfilteredActive = ords.where((o) => o.status != 'delivered' && o.status != 'cancelled').toList();
        
        // Fetch and populate order items for active orders
        activeOrders = await Future.wait(unfilteredActive.map((o) async {
          final items = await _api.getOrderItems(o.id!);
          return OrderModel(
            id: o.id,
            orderNumber: o.orderNumber,
            tableId: o.tableId,
            orderType: o.orderType,
            deliveryPlatform: o.deliveryPlatform,
            customerId: o.customerId,
            stewardName: o.stewardName,
            status: o.status,
            paymentStatus: o.paymentStatus,
            paymentMethod: o.paymentMethod,
            subtotal: o.subtotal,
            discount: o.discount,
            total: o.total,
            cashierId: o.cashierId,
            shiftId: o.shiftId,
            kotPrinted: o.kotPrinted,
            ackPrinted: o.ackPrinted,
            cardTxReference: o.cardTxReference,
            barcode: o.barcode,
            createdAt: o.createdAt,
            updatedAt: o.updatedAt,
            receivedAmount: o.receivedAmount,
            changeAmount: o.changeAmount,
            items: items,
          );
        }));
        
        // Restore Dine-In tables state from active unpaid orders (e.g. after a power cut or restart)
        final activeDineInOrders = activeOrders.where((o) => o.orderType == 'dine_in' && o.tableId != null).toList();
        
        // Track active table IDs to remove inactive ones
        final Set<int> activeTableIds = activeDineInOrders.map((o) => o.tableId!).toSet();
        
        // 1. Clear inactive tables (only if they were actually saved/active in DB earlier, keeping pure local drafts)
        final List<int> currentTableIds = tableCarts.keys.toList();
        for (var tid in currentTableIds) {
          if (tableActiveOrderIds[tid] != null && !activeTableIds.contains(tid)) {
            tableCarts.remove(tid);
            tableActiveOrderIds.remove(tid);
            tableStewards.remove(tid);
            tableStatuses[tid] = 'empty';
          }
        }
        
        // 2. Restore/Update active tables
        for (var o in activeDineInOrders) {
          final tid = o.tableId!;
          final hasLocalPending = tableCarts[tid]?.any((item) => item.status == 'pending') ?? false;
          
          if ((selectedTable?.id == tid && cart.isNotEmpty) || hasLocalPending) {
            tableActiveOrderIds[tid] = o.id!;
            tableStewards[tid] = o.stewardName;
            tableStatuses[tid] = o.ackPrinted ? 'billing' : 'seated';
          } else {
            tableCarts[tid] = o.items;
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
      if (activePreOrderId != null) {
        return sum + (item.price * item.quantity);
      }
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
    if (activePreOrderId != null) {
      double manualDiscountValue = 0.00;
      if (discountType == 'percent') {
        manualDiscountValue = cartSubtotal * (rawDiscountValue / 100.0);
      } else {
        manualDiscountValue = rawDiscountValue;
      }
      return manualDiscountValue;
    }

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
    
    // 1. Look for product-specific happy hour first
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

    // 2. Look for category-specific happy hour if no product-specific one is active
    for (var hp in happyHours) {
      final catId = hp['category_id'];
      final prodId = hp['product_id'];
      if (catId == product.categoryId && (prodId == null || prodId == 0 || prodId == '0') && hp['status'] == 'active') {
        final daysStr = hp['days_of_week']?.toString() ?? '1,2,3,4,5,6,7';
        final days = daysStr.split(',').map((e) => int.tryParse(e.trim())).toList();
        if (days.contains(currentDay)) {
          final startMin = _parseTimeToMinutes(hp['start_time']?.toString() ?? '');
          final endMin = _parseTimeToMinutes(hp['end_time']?.toString() ?? '');
          if (startMin != null && endMin != null) {
            if (currentMin >= startMin && currentMin <= endMin) {
              final discountPct = toDouble(hp['promo_price']);
              final activePrice = product.price * (1 - (discountPct / 100.0));
              return double.parse(activePrice.toStringAsFixed(2));
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
    activePreOrderAdvance = 0.00;
    activePreOrderId = null;
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

  Future<void> fetchDrawerLogs() async {
    if (activeShift != null) {
      try {
        drawerLogs = await _api.getDrawerLogs(activeShift!.id);
        notifyListeners();
      } catch (_) {}
    }
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

  Future<Map<String, double>> getShiftStatistics() async {
    if (activeShift == null) {
      return {
        'cash_sales': 0.0,
        'card_sales': 0.0,
        'qr_sales': 0.0,
        'credit_sales': 0.0,
        'credit_settlements': 0.0,
        'other_cash_in': 0.0,
        'supplier_payments': 0.0,
        'other_cash_out': 0.0,
        'expected_cash': 0.0,
        'total_sales': 0.0,
      };
    }

    try {
      final ords = await _api.getOrders();
      final shiftOrders = ords.where((o) => o.shiftId == activeShift!.id && o.paymentStatus == 'paid');

      double cashSales = 0.0;
      double cardSales = 0.0;
      double qrSales = 0.0;
      double creditSales = 0.0;

      for (var o in shiftOrders) {
        if (o.paymentMethod == 'cash') {
          cashSales += o.total;
        } else if (o.paymentMethod == 'card') {
          cardSales += o.total;
        } else if (o.paymentMethod == 'qr' || o.paymentMethod == 'lankaqr') {
          qrSales += o.total;
        } else if (o.paymentMethod == 'credit') {
          creditSales += o.total;
        }
      }

      double creditSettlements = 0.0;
      double otherCashIn = 0.0;
      double supplierPayments = 0.0;
      double otherCashOut = 0.0;

      final logs = await _api.getDrawerLogs(activeShift!.id);
      for (var log in logs) {
        final double amt = double.tryParse(log['amount']?.toString() ?? '0') ?? 0.0;
        if (log['type'] == 'cash_in') {
          if (log['reason']?.toString().contains('Credit Settlement:') ?? false) {
            creditSettlements += amt;
          } else {
            otherCashIn += amt;
          }
        } else if (log['type'] == 'cash_out') {
          if (log['reason']?.toString().contains('Supplier Payment:') ?? false) {
            supplierPayments += amt;
          } else {
            otherCashOut += amt;
          }
        }
      }

      final expectedCash = activeShift!.openingBalance + cashSales + creditSettlements + otherCashIn - supplierPayments - otherCashOut;
      final totalSales = cashSales + cardSales + qrSales + creditSales;

      return {
        'cash_sales': cashSales,
        'card_sales': cardSales,
        'qr_sales': qrSales,
        'credit_sales': creditSales,
        'credit_settlements': creditSettlements,
        'other_cash_in': otherCashIn,
        'supplier_payments': supplierPayments,
        'other_cash_out': otherCashOut,
        'expected_cash': expectedCash,
        'total_sales': totalSales,
      };
    } catch (_) {
      return {
        'cash_sales': 0.0,
        'card_sales': 0.0,
        'qr_sales': 0.0,
        'credit_sales': 0.0,
        'credit_settlements': 0.0,
        'other_cash_in': 0.0,
        'supplier_payments': 0.0,
        'other_cash_out': 0.0,
        'expected_cash': activeShift!.openingBalance,
        'total_sales': 0.0,
      };
    }
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
    int? customerId,
    int? preOrderId,
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
      customerId: customerId ?? selectedCustomer?.id ?? 1, // Default walking customer
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
      advancePayment: activePreOrderAdvance,
      balanceAmount: cartTotal - activePreOrderAdvance < 0 ? 0.00 : cartTotal - activePreOrderAdvance,
      preOrderId: preOrderId ?? activePreOrderId,
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
    
    // Convert associated pre-order if applicable
    if (isOnline && activePreOrderId != null) {
      try {
        await _api.updatePreOrder(activePreOrderId!, {'status': 'converted'});
      } catch (e) {
        print('Error converting pre-order: $e');
      }
      activePreOrderId = null;
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

  // ----------------------------------------------------
  // PRE-ORDERS & NOTIFICATIONS CONTROLLER METHODS
  // ----------------------------------------------------
  Future<void> fetchPreOrders() async {
    if (!isOnline) return;
    try {
      preOrders = await _api.getPreOrders();
      notifyListeners();
    } catch (e) {
      print('Error loading pre-orders: $e');
    }
  }

  Future<void> createPreOrder(Map<String, dynamic> data) async {
    if (!isOnline) return;
    await _api.createPreOrder(data);
    await fetchPreOrders();
  }

  Future<void> updatePreOrder(int id, Map<String, dynamic> data) async {
    if (!isOnline) return;
    await _api.updatePreOrder(id, data);
    await fetchPreOrders();
  }

  Future<void> deletePreOrder(int id) async {
    if (!isOnline) return;
    await _api.deletePreOrder(id);
    await fetchPreOrders();
  }

  Future<void> fetchNotifications() async {
    if (!isOnline) return;
    try {
      notifications = await _api.getNotifications();
      unreadNotificationCount = notifications.where((n) => n['is_read'] == 0 || n['is_read'] == false || n['is_read'] == '0' || n['is_read'] == 0.0).length;
      notifyListeners();
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }

  Future<void> readNotification(int id) async {
    if (!isOnline) return;
    try {
      await _api.markNotificationRead(id);
      final idx = notifications.indexWhere((n) => n['id'] == id);
      if (idx != -1) {
        notifications[idx]['is_read'] = 1;
        unreadNotificationCount = notifications.where((n) => n['is_read'] == 0 || n['is_read'] == false || n['is_read'] == '0' || n['is_read'] == 0.0).length;
        notifyListeners();
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> readAllNotifications() async {
    if (!isOnline) return;
    try {
      await _api.markAllNotificationsRead();
      for (var n in notifications) {
        n['is_read'] = 1;
      }
      unreadNotificationCount = 0;
      notifyListeners();
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  void loadPreOrderToCart(dynamic preOrder) {
    cart.clear();
    activePreOrderId = preOrder['id'];
    activePreOrderAdvance = double.parse(preOrder['advance_payment']?.toString() ?? '0.0');
    
    final custId = preOrder['customer_id'];
    if (custId != null) {
      final matchCust = customers.firstWhere((c) => c.id == custId, orElse: () => customers.first);
      selectedCustomer = matchCust;
    } else {
      selectedCustomer = null;
    }
    
    final itemsList = preOrder['items'] as List? ?? [];
    for (var item in itemsList) {
      final productId = item['product_id'];
      final prod = products.firstWhere(
        (p) => p.id == productId,
        orElse: () => ProductModel(
          id: productId,
          name: item['product_name'] ?? 'Product',
          categoryId: 0,
          price: double.parse(item['price']?.toString() ?? '0.0'),
          cost: 0,
          activePrice: double.parse(item['price']?.toString() ?? '0.0'),
          isHappyHour: false,
          stockQty: 0,
          minStockLevel: 0,
          isShortEat: false,
        ),
      );
      
      cart.add(OrderItemModel(
        productId: productId,
        productName: item['product_name'] ?? prod.name,
        productSinhalaName: item['product_sinhala_name'] ?? prod.sinhalaName,
        quantity: item['quantity'] ?? 1,
        price: double.parse(item['price']?.toString() ?? '0.0'),
        notes: item['notes'],
        status: 'pending',
        isShortEat: prod.isShortEat,
        extras: const [],
      ));
    }
    
    orderType = 'takeaway';
    stewardName = null;
    selectedTable = null;
    
    rawDiscountValue = double.parse(preOrder['discount']?.toString() ?? '0.0');
    discountType = 'fixed';
    
    notifyListeners();
  }
}
