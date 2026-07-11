import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';
import 'package:intl/intl.dart';

class OrderQueueScreen extends StatefulWidget {
  const OrderQueueScreen({Key? key}) : super(key: key);

  @override
  State<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends State<OrderQueueScreen> {
  // Timers and autoplay states
  Timer? _cycleTimer;
  Timer? _promoSlideTimer;
  bool _isAutoplayPaused = false;
  bool _isFullScreenPromo = false;
  int _ticks = 0;
  
  // Carousel states
  int _bottomSlideIndex = 0;
  int _fullSlideIndex = 0;
  PageController? _bottomPageController;
  PageController? _fullPageController;

  @override
  void initState() {
    super.initState();
    _bottomPageController = PageController(initialPage: 0);
    _fullPageController = PageController(initialPage: 0);
    _startPromoSlideTimer();
    _startCycleTimer();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _promoSlideTimer?.cancel();
    _bottomPageController?.dispose();
    _fullPageController?.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  List<OfferModel> _getActiveBanners() {
    final controller = Provider.of<POSController>(context, listen: false);
    return controller.offers.where((o) => o.status == 'active').toList();
  }

  String _formatTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.isEmpty) return timeStr;
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      
      final isPm = hour >= 12;
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final displayMin = minute.toString().padLeft(2, '0');
      final suffix = isPm ? 'p.m.' : 'a.m.';
      
      return '$displayHour.$displayMin $suffix';
    } catch (_) {
      return timeStr;
    }
  }

  void _startCycleTimer() {
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_isAutoplayPaused) {
        if (_isFullScreenPromo) {
          setState(() {
            _isFullScreenPromo = false;
            _ticks = 0;
          });
        }
        // Force state updates to keep ready orders fresh even when paused
        if (DateTime.now().second % 30 == 0) {
          setState(() {});
        }
        return;
      }

      final controller = Provider.of<POSController>(context, listen: false);
      final activeBanners = _getActiveBanners();
      final hasPromos = activeBanners.isNotEmpty || controller.happyHours.isNotEmpty;

      _ticks++;
      if (_isFullScreenPromo) {
        // Return to normal split-view after 15 seconds
        if (_ticks >= 15 || !hasPromos) {
          setState(() {
            _isFullScreenPromo = false;
            _ticks = 0;
            _bottomSlideIndex = 0;
          });
          _bottomPageController = PageController(initialPage: 0);
        }
      } else {
        // Go full screen with promotions after 45 seconds
        if (_ticks >= 45 && hasPromos) {
          setState(() {
            _isFullScreenPromo = true;
            _ticks = 0;
            _fullSlideIndex = 0;
          });
          _fullPageController = PageController(initialPage: 0);
        } else if (_ticks >= 45 && !hasPromos) {
          _ticks = 0; // remain in normal split-view, reset counter
        }
      }

      // Rebuild periodically to evaluate relative timestamps for ready orders
      if (_ticks % 5 == 0) {
        setState(() {});
      }
    });
  }

  void _startPromoSlideTimer() {
    _promoSlideTimer?.cancel();
    _promoSlideTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isAutoplayPaused) return;

      final controller = Provider.of<POSController>(context, listen: false);
      final activeBanners = _getActiveBanners();
      final totalSlides = activeBanners.length + controller.happyHours.length;
      if (totalSlides <= 1) return;

      if (_isFullScreenPromo) {
        setState(() {
          _fullSlideIndex = (_fullSlideIndex + 1) % totalSlides;
        });
        _fullPageController?.animateToPage(
          _fullSlideIndex,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      } else {
        setState(() {
          _bottomSlideIndex = (_bottomSlideIndex + 1) % totalSlides;
        });
        _bottomPageController?.animateToPage(
          _bottomSlideIndex,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  ProductModel? _getProductByName(String name) {
    try {
      final controller = Provider.of<POSController>(context, listen: false);
      return controller.products.firstWhere(
        (p) => p.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  String _formatDateTimeString(String dateStr) {
    try {
      final dateTime = DateTime.tryParse(dateStr)?.toLocal();
      if (dateTime == null) return dateStr;
      final formatted = DateFormat('yyyy-MM-dd h.mm a').format(dateTime);
      return formatted.replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);

    // Sort preparing orders: newest first
    final preparingOrders = controller.activeOrders
        .where((o) => o.status == 'pending' || o.status == 'preparing')
        .toList();
    preparingOrders.sort((a, b) {
      final aTime = DateTime.tryParse(a.createdAt) ?? DateTime.now();
      final bTime = DateTime.tryParse(b.createdAt) ?? DateTime.now();
      return bTime.compareTo(aTime);
    });

    // Filter ready orders: only prepared orders that are less than 20 minutes old
    final now = DateTime.now();
    final readyOrders = controller.activeOrders.where((o) {
      if (o.status != 'prepared') return false;
      final timeStr = o.updatedAt ?? o.createdAt;
      final time = DateTime.tryParse(timeStr) ?? now;
      return now.difference(time).inMinutes < 20;
    }).toList();

    // Sort ready orders: newest first
    readyOrders.sort((a, b) {
      final aTime = DateTime.tryParse(a.updatedAt ?? a.createdAt) ?? now;
      final bTime = DateTime.tryParse(b.updatedAt ?? b.createdAt) ?? now;
      return bTime.compareTo(aTime);
    });

    final activeBanners = _getActiveBanners();
    final totalSlides = activeBanners.length + controller.happyHours.length;
    final hasPromos = totalSlides > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _isFullScreenPromo && hasPromos
            ? _buildPromotionsSlideshow(activeBanners)
            : _buildSplitLayout(preparingOrders, readyOrders, activeBanners, hasPromos),
      ),
    );
  }

  Widget _buildSplitLayout(List<OrderModel> preparingOrders, List<OrderModel> readyOrders, List<OfferModel> activeBanners, bool hasPromos) {
    return Column(
      key: const ValueKey('split_layout'),
      children: [
        // Order columns status view
        Expanded(
          child: _buildQueueScreen(preparingOrders, readyOrders),
        ),
        
        // Promotional bottom slideshow
        if (hasPromos) ...[
          const Divider(height: 1, color: Color(0xFF334155)),
          Container(
            height: 180,
            color: const Color(0xFF0F172A),
            child: _buildBottomSlideshow(activeBanners),
          ),
        ],
      ],
    );
  }

  Widget _buildQueueScreen(List<OrderModel> preparingOrders, List<OrderModel> readyOrders) {
    final controller = Provider.of<POSController>(context, listen: false);
    final activeBanners = _getActiveBanners();
    final hasPromos = activeBanners.isNotEmpty || controller.happyHours.isNotEmpty;

    return Column(
      children: [
        // Screen Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          color: const Color(0xFF1E293B),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CUSTOMER ORDER STATUS',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  if (hasPromos) ...[
                    IconButton(
                      icon: Icon(
                        _isAutoplayPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: _isAutoplayPaused ? AppTheme.primary : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() {
                          _isAutoplayPaused = !_isAutoplayPaused;
                        });
                      },
                    ),
                    Text(
                      _isAutoplayPaused ? 'RESUME SLIDESHOW' : 'PAUSE SLIDESHOW',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isAutoplayPaused ? AppTheme.primary : const Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                  Text(
                    'Please collect when your number is Ready',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Progress bar for transitions to full screen
        if (hasPromos && !_isAutoplayPaused)
          LinearProgressIndicator(
            value: _ticks / 45.0,
            backgroundColor: const Color(0xFF334155),
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            minHeight: 3,
          ),

        // Main Column Split
        Expanded(
          child: Row(
            children: [
              // Preparing Column (Left)
              Expanded(
                child: Container(
                  color: const Color(0xFF0F172A),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.warning, width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PREPARING / සකසමින් පවතී',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.warning,
                              ),
                            ),
                            Text(
                              '${preparingOrders.length}',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.warning),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: preparingOrders.isEmpty
                            ? Center(
                                child: Text(
                                  'No orders preparing.',
                                  style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                                ),
                              )
                            : GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.8,
                                ),
                                itemCount: preparingOrders.length,
                                itemBuilder: (context, index) {
                                  final o = preparingOrders[index];
                                  final tokenNum = _getQueueTokenNumber(o);
                                  return _buildQueueToken(tokenNum, false);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const VerticalDivider(width: 1, color: Color(0xFF334155)),
              
              // Ready Column (Right)
              Expanded(
                child: Container(
                  color: const Color(0xFF0F172A),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accent, width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'READY / සූදානම්',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                            Text(
                              '${readyOrders.length}',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: readyOrders.isEmpty
                            ? Center(
                                child: Text(
                                  'No orders ready for collection.',
                                  style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                                ),
                              )
                            : GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.8,
                                ),
                                itemCount: readyOrders.length,
                                itemBuilder: (context, index) {
                                  final o = readyOrders[index];
                                  final tokenNum = _getQueueTokenNumber(o);
                                  return _buildQueueToken(tokenNum, true);
                                },
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

  // --- SLIDESHOW BUILDERS ---

  Widget _buildBottomSlideshow(List<OfferModel> activeBanners) {
    final controller = Provider.of<POSController>(context, listen: false);
    final totalSlides = activeBanners.length + controller.happyHours.length;

    return Stack(
      children: [
        PageView.builder(
          controller: _bottomPageController,
          itemCount: totalSlides,
          onPageChanged: (index) {
            setState(() {
              _bottomSlideIndex = index;
            });
          },
          itemBuilder: (context, index) {
            if (index < activeBanners.length) {
              return _buildBottomBannerSlide(activeBanners[index]);
            } else {
              return _buildBottomHappyHourSlide(controller.happyHours[index - activeBanners.length]);
            }
          },
        ),

        // Indicator dots overlay
        if (totalSlides > 1)
          Positioned(
            bottom: 12,
            right: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(totalSlides, (idx) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: idx == _bottomSlideIndex ? AppTheme.primary : Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildPromotionsSlideshow(List<OfferModel> activeBanners) {
    final controller = Provider.of<POSController>(context, listen: false);
    final totalSlides = activeBanners.length + controller.happyHours.length;

    return Stack(
      key: const ValueKey('promo_slideshow'),
      children: [
        PageView.builder(
          controller: _fullPageController,
          itemCount: totalSlides,
          onPageChanged: (index) {
            setState(() {
              _fullSlideIndex = index;
            });
          },
          itemBuilder: (context, index) {
            if (index < activeBanners.length) {
              return _buildBannerSlide(activeBanners[index]);
            } else {
              return _buildHappyHourSlide(controller.happyHours[index - activeBanners.length]);
            }
          },
        ),

        // Indicator Bar / Close Button Overlay
        Positioned(
          top: 24,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(totalSlides, (idx) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: idx == _fullSlideIndex ? AppTheme.primary : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
              IconButton.filled(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B).withOpacity(0.8),
                  hoverColor: const Color(0xFF334155),
                ),
                onPressed: () {
                  setState(() {
                    _isFullScreenPromo = false;
                    _ticks = 0;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- SLIDE ITEMS BUILDERS ---

  Widget _buildBottomBannerSlide(OfferModel banner) {
    final hasImage = banner.imageBase64 != null && banner.imageBase64!.length > 200;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      color: const Color(0xFF1E293B), // Slate 800 matching header
      child: Row(
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 200,
                height: 148,
                child: Base64ImageWidget(
                  base64Str: banner.imageBase64,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 24),
          ] else ...[
            Container(
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(
                  Icons.local_offer_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(width: 24),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary, width: 1),
                  ),
                  child: Text(
                    'PROMOTION',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  banner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Valid until ${_formatDateTimeString(banner.endDate)}',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${banner.discountPercentage.toStringAsFixed(0)}%',
                  style: GoogleFonts.outfit(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'OFF',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBottomHappyHourSlide(Map<String, dynamic> promo) {
    final prodName = promo['product_name'] ?? '';
    final pModel = _getProductByName(prodName);
    final promoPrice = promo['promo_price'];
    final originalPrice = promo['original_price'];
    final start = promo['start_time'].toString().substring(0, 5);
    final end = promo['end_time'].toString().substring(0, 5);
    final daysStr = promo['days_of_week'] ?? '1,2,3,4,5,6,7';

    String daysDesc = 'EVERY DAY';
    if (daysStr == '1,2,3,4,5') {
      daysDesc = 'WEEKDAYS';
    } else if (daysStr == '6,7') {
      daysDesc = 'WEEKENDS';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      color: const Color(0xFF064E3B).withOpacity(0.3), // Emerald Green tint
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 200,
              height: 148,
              child: pModel != null && pModel.imageBase64 != null && pModel.imageBase64!.length > 200
                  ? Base64ImageWidget(
                      base64Str: pModel.imageBase64,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppTheme.accent.withOpacity(0.15),
                      child: const Center(
                        child: Icon(
                          Icons.restaurant_menu_rounded,
                          color: AppTheme.accent,
                          size: 44,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.accent, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.celebration, color: AppTheme.accent, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            promo['name'] != null && promo['name'].toString().isNotEmpty
                                ? promo['name'].toString().toUpperCase()
                                : 'HAPPY HOUR',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        daysDesc,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  prodName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                if (pModel?.sinhalaName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    pModel!.sinhalaName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Valid: ${_formatTimeString(start)} to ${_formatTimeString(end)}',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'LKR ${promoPrice.toString()}',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.warning,
                  ),
                ),
                Text(
                  'REG: LKR ${originalPrice.toString()}',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white70,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.red,
                    decorationThickness: 2.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBannerSlide(OfferModel banner) {
    final hasImage = banner.imageBase64 != null && banner.imageBase64!.length > 200;

    if (hasImage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Base64ImageWidget(
            base64Str: banner.imageBase64,
            fit: BoxFit.cover,
          ),
          ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
              child: Container(
                color: Colors.black.withOpacity(0.6),
              ),
            ),
          ),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 950),
              margin: const EdgeInsets.all(40),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1.1,
                        child: Base64ImageWidget(
                          base64Str: banner.imageBase64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'SPECIAL PROMOTION',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          banner.name,
                          style: GoogleFonts.outfit(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '${banner.discountPercentage.toStringAsFixed(0)}%',
                          style: GoogleFonts.outfit(
                            fontSize: 68,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OFF',
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            Text(
                              'ON FEATURED ITEMS',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155), height: 40),
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, color: AppTheme.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Valid: ${_formatDateTimeString(banner.startDate)} to ${_formatDateTimeString(banner.endDate)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFCBD5E1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
} else {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 750),
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_offer_rounded,
              color: Color(0xFFFF1B6B),
              size: 72,
            ),
            const SizedBox(height: 24),
            Text(
              'SPECIAL OFFER',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              banner.name,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${banner.discountPercentage.toStringAsFixed(0)}%',
                    style: GoogleFonts.outfit(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'DISCOUNT\nOFF',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Promotion Period: ${_formatDateTimeString(banner.startDate)} - ${_formatDateTimeString(banner.endDate)}',
              style: GoogleFonts.inter(
                fontSize: 18,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  }

  Widget _buildHappyHourSlide(Map<String, dynamic> promo) {
    final prodName = promo['product_name'] ?? '';
    final pModel = _getProductByName(prodName);
    final promoPrice = promo['promo_price'];
    final originalPrice = promo['original_price'];
    final start = promo['start_time'].toString().substring(0, 5);
    final end = promo['end_time'].toString().substring(0, 5);
    final daysStr = promo['days_of_week'] ?? '1,2,3,4,5,6,7';

    String daysDesc = 'EVERY DAY';
    if (daysStr == '1,2,3,4,5') {
      daysDesc = 'WEEKDAYS';
    } else if (daysStr == '6,7') {
      daysDesc = 'WEEKENDS';
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 950),
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.accent.withOpacity(0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: pModel != null && pModel.imageBase64 != null && pModel.imageBase64!.length > 200
                        ? Base64ImageWidget(
                            base64Str: pModel.imageBase64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppTheme.accent.withOpacity(0.15),
                            child: const Center(
                              child: Icon(
                                Icons.restaurant_menu_rounded,
                                color: AppTheme.accent,
                                size: 80,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: AppTheme.accent, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.celebration, color: AppTheme.accent, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                promo['name'] != null && promo['name'].toString().isNotEmpty
                                    ? promo['name'].toString().toUpperCase()
                                    : 'HAPPY HOUR',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            daysDesc,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFCBD5E1),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      prodName,
                      style: GoogleFonts.outfit(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (pModel?.sinhalaName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        pModel!.sinhalaName!,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HAPPY HOUR PRICE',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.warning,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              'LKR ${promoPrice.toString()}',
                              style: GoogleFonts.outfit(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.warning,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'LKR ${originalPrice.toString()}',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              color: Colors.white70,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.red,
                              decorationThickness: 2.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155), height: 40),
                    Row(
                      children: [
                        const Icon(Icons.access_time_filled, color: AppTheme.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Valid: ${_formatTimeString(start)} to ${_formatTimeString(end)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFCBD5E1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }

  Widget _buildQueueToken(String token, bool isReady) {
    return Container(
      decoration: BoxDecoration(
        color: isReady ? AppTheme.accent.withOpacity(0.1) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady ? AppTheme.accent : const Color(0xFF334155),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          token,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isReady ? AppTheme.accent : Colors.white,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // BARCODE SCANNING & TRANSITIONS (QUEUE SCREEN GLOBAL LISTENER)
  // =========================================================================
  String _barcodeBuffer = '';
  DateTime? _lastKeyPressTime;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      if (_lastKeyPressTime != null && now.difference(_lastKeyPressTime!).inMilliseconds > 200) {
        _barcodeBuffer = '';
      }
      _lastKeyPressTime = now;

      final logicalKey = event.logicalKey;
      if (logicalKey == LogicalKeyboardKey.enter) {
        if (_barcodeBuffer.isNotEmpty) {
          _processScannedBarcode(_barcodeBuffer.trim());
          _barcodeBuffer = '';
        }
        return true;
      }

      final char = event.character;
      if (char != null && char.isNotEmpty) {
        _barcodeBuffer += char;
      }
    }
    return false;
  }

  Future<void> _processScannedBarcode(String barcode) async {
    String cleanBarcode = barcode;
    bool isKot = false;
    bool isInv = false;

    if (barcode.toUpperCase().startsWith('KOT-')) {
      cleanBarcode = barcode.substring(4);
      isKot = true;
    } else if (barcode.toUpperCase().startsWith('INV-')) {
      cleanBarcode = barcode.substring(4);
      isInv = true;
    } else {
      cleanBarcode = barcode;
    }

    try {
      final api = APIService.instance;
      final order = await api.getOrderByNumber(cleanBarcode);
      
      String newStatus = order.status;
      bool statusChanged = false;

      if (isKot || (!isKot && !isInv)) {
        if (order.status == 'pending') {
          newStatus = 'preparing';
          statusChanged = true;
        } else if (order.status == 'preparing' && order.orderType == 'dine_in') {
          newStatus = 'prepared';
          statusChanged = true;
        }
      }

      if (isInv || (!isKot && !isInv)) {
        if (order.orderType != 'dine_in') {
          if (order.status == 'preparing') {
            newStatus = 'prepared';
            statusChanged = true;
          } else if (order.status == 'prepared') {
            newStatus = 'delivered';
            statusChanged = true;
          }
        }
      }

      if (statusChanged) {
        await api.updateOrderOnline(order.id!, {'status': newStatus});
        
        if (mounted) {
          final posController = Provider.of<POSController>(context, listen: false);
          await posController.reloadEnvironment();
          _showScanSuccessDialog(order.orderNumber, order.status, newStatus);
        }
      } else {
        _showOrderStatusDialog(order);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Barcode Scan Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showScanSuccessDialog(String orderNumber, String oldStatus, String newStatus) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
              const SizedBox(width: 12),
              Text(
                'Status Updated',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order $orderNumber status changed successfully:',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatusBadge(oldStatus),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  _buildStatusBadge(newStatus),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showOrderStatusDialog(OrderModel order) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              const Icon(Icons.info_rounded, color: Color(0xFF3B82F6), size: 28),
              const SizedBox(width: 12),
              Text(
                'Order Info',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order Number: ${order.orderNumber}',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Type: ${order.orderType.toUpperCase().replaceAll('_', ' ')}',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: LKR ${order.total.toStringAsFixed(2)}',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Current Status: ',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                  _buildStatusBadge(order.status),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = Colors.grey.withOpacity(0.2);
    Color txt = Colors.grey;
    String label = status.toUpperCase();

    if (status == 'pending') {
      bg = AppTheme.warning.withOpacity(0.2);
      txt = AppTheme.warning;
      label = 'ACCEPT';
    } else if (status == 'preparing') {
      bg = Colors.orange.withOpacity(0.2);
      txt = Colors.orange;
      label = 'PREPARING';
    } else if (status == 'prepared') {
      bg = AppTheme.accent.withOpacity(0.2);
      txt = AppTheme.accent;
      label = 'PREPARED';
    } else if (status == 'delivered') {
      bg = const Color(0xFF10B981).withOpacity(0.2);
      txt = const Color(0xFF10B981);
      label = 'DELIVERED';
    } else if (status == 'cancelled') {
      bg = Colors.red.withOpacity(0.2);
      txt = Colors.red;
      label = 'CANCELLED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: txt),
      ),
    );
  }

  String _getQueueTokenNumber(OrderModel order) {
    if (order.id == null) return '000';
    final idStr = order.id.toString();
    if (idStr.length >= 3) {
      return idStr.substring(idStr.length - 3);
    }
    return idStr.padLeft(3, '0');
  }
}
