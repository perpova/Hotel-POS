import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../pos_controller.dart';
import '../controllers/app_settings_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';
import 'package:intl/intl.dart';

class OrderQueueScreen extends StatefulWidget {
  final bool isSeparateWindow;
  const OrderQueueScreen({Key? key, this.isSeparateWindow = false}) : super(key: key);

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

  VideoPlayerController? _videoPlayerController;
  String? _currentVideoPath;
  String? _initializingVideoPath;
  StreamSubscription<List<int>>? _downloadSubscription;
  String? _downloadProgressPercent;

  int _batchIndex = 0;
  static const int _batchSize = 4;

  String? _getYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    return (match != null && match.groupCount >= 2) ? match.group(2) : null;
  }

  List<dynamic> _getCombinedActivePromos() {
    final activeBanners = _getActiveBanners();
    final activeHappyHours = _getActiveHappyHours();
    return [...activeBanners, ...activeHappyHours];
  }

  List<dynamic> _getCurrentBatchPromos() {
    final allPromos = _getCombinedActivePromos();
    if (allPromos.isEmpty) return [];
    
    final int numBatches = (allPromos.length / _batchSize).ceil();
    final currentBatch = _batchIndex % numBatches;
    final sliceStart = currentBatch * _batchSize;
    final sliceEnd = (sliceStart + _batchSize).clamp(0, allPromos.length);
    return allPromos.sublist(sliceStart, sliceEnd);
  }

  void _logDebug(String message) {
    try {
      final file = File('debug_log.txt');
      file.writeAsStringSync('${DateTime.now().toIso8601String()}: $message\n', mode: FileMode.append);
    } catch (e) {
      print('Failed to write debug log: $e');
    }
  }

  void _initializeBackgroundVideo() async {
    _logDebug('--- _initializeBackgroundVideo started ---');
    final appSettings = Provider.of<AppSettingsController>(context, listen: false);
    final type = appSettings.queueBgType;
    final source = appSettings.queueBgVideoSource;
    final path = appSettings.queueBgVideoPath;
    final url = appSettings.queueBgVideoUrl;

    _logDebug('BgType: $type, Source: $source, Path: $path, Url: $url');

    if (type != 'video') {
      _logDebug('BgType is not video, disposing controller');
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
      _currentVideoPath = null;
      _initializingVideoPath = null;
      return;
    }

    if (source == 'file' && path != null && path.isNotEmpty) {
      _logDebug('Source is file. Path: $path');
      if (_downloadSubscription != null) {
        _logDebug('Cancelling YouTube download due to source change to file.');
        _downloadSubscription!.cancel();
        _downloadSubscription = null;
      }
      _downloadProgressPercent = null;
      _initializingVideoPath = path;
      final file = File(path);
      if (file.existsSync()) {
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        
        String playPath = path;
        if (widget.isSeparateWindow) {
          try {
            final dir = file.parent;
            final name = p.basenameWithoutExtension(file.path);
            final ext = p.extension(file.path);
            final copyFile = File('${dir.path}${Platform.pathSeparator}${name}_extend$ext');
            if (!copyFile.existsSync() || copyFile.lengthSync() != file.lengthSync()) {
              file.copySync(copyFile.path);
            }
            playPath = copyFile.path;
            _logDebug('Copied local file for separate window: $playPath');
          } catch (e) {
            _logDebug('Failed to copy file for separate window: $e');
          }
        }

        _logDebug('Initializing local file controller with path: $playPath...');
        _videoPlayerController = VideoPlayerController.file(File(playPath))
          ..initialize().then((_) {
            _logDebug('Local file initialized successfully.');
            if (mounted && _initializingVideoPath == path) {
              _currentVideoPath = path;
              _initializingVideoPath = null;
              _videoPlayerController!.setLooping(true);
              _videoPlayerController!.setVolume(0.0);
              _videoPlayerController!.play();
              _logDebug('Local file playback started.');
              setState(() {});
            }
          }).catchError((e) {
            _logDebug('Error initializing local file: $e');
            if (mounted && _initializingVideoPath == path) {
              setState(() {
                _videoPlayerController = null;
                _currentVideoPath = null;
                _initializingVideoPath = null;
              });
            }
          });
      } else {
        _logDebug('Local file does not exist at path: $path');
        if (mounted && _initializingVideoPath == path) {
          setState(() {
            _initializingVideoPath = null;
          });
        }
      }
    } else if (source == 'link' && url != null && url.isNotEmpty) {
      final cacheKey = 'link_$url';
      _logDebug('Source is link. CacheKey: $cacheKey');

      _logDebug('Disposing old controller and initializing for link...');
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
      if (_downloadSubscription != null) {
        _logDebug('Cancelling active YouTube download due to link change.');
        _downloadSubscription!.cancel();
        _downloadSubscription = null;
      }
      _downloadProgressPercent = null;
      _initializingVideoPath = cacheKey;
      setState(() {});

      final youtubeId = _getYoutubeId(url);
      _logDebug('Extracted YouTube ID: $youtubeId');
      String? streamUrl;

      if (youtubeId != null) {
        final tempDir = Directory.systemTemp;
        // Use v4 prefix to clear any corrupted v3 cache files!
        final targetFile = File('${tempDir.path}${Platform.pathSeparator}queue_background_youtube_v4_$youtubeId.mp4');
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tmpFile = File('${tempDir.path}${Platform.pathSeparator}queue_background_youtube_v4_${youtubeId}_$timestamp.mp4.tmp');

        if (await targetFile.exists() && await targetFile.length() > 1024) {
          _logDebug('Cached video found at: ${targetFile.path}. Skipping download.');
          streamUrl = targetFile.path;
        } else {
          _logDebug('Starting download for YouTube ID: $youtubeId');
          setState(() {
            _downloadProgressPercent = '0';
          });

          IOSink? fileStream;
          try {
            final yt = yt_exp.YoutubeExplode();
            _logDebug('Fetching manifest for YouTube ID: $youtubeId');
            final manifest = await yt.videos.streamsClient.getManifest(youtubeId);
            _logDebug('Manifest fetched. Muxed count: ${manifest.muxed.length}, VideoOnly count: ${manifest.videoOnly.length}');
            
            yt_exp.VideoStreamInfo? streamInfo;
            if (manifest.muxed.isNotEmpty) {
              try {
                streamInfo = manifest.muxed.firstWhere(
                  (s) => s.videoQuality.toString().contains('360')
                );
                _logDebug('Selected Muxed 360p stream: ${streamInfo.videoQuality}');
              } catch (_) {
                try {
                  streamInfo = manifest.muxed.firstWhere(
                    (s) => s.videoQuality.toString().contains('480')
                  );
                  _logDebug('Selected Muxed 480p stream: ${streamInfo.videoQuality}');
                } catch (_) {
                  streamInfo = manifest.muxed.withHighestBitrate();
                  _logDebug('Selected Muxed highest bitrate: ${streamInfo.videoQuality}');
                }
              }
            } else if (manifest.videoOnly.isNotEmpty) {
              final mp4Streams = manifest.videoOnly.where((s) => s.container.name == 'mp4').toList();
              if (mp4Streams.isNotEmpty) {
                mp4Streams.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
                try {
                  streamInfo = mp4Streams.firstWhere(
                    (s) => s.videoQuality.toString().contains('360') || s.videoQuality.toString().contains('480')
                  );
                } catch (_) {
                  try {
                    streamInfo = mp4Streams.firstWhere(
                      (s) => s.videoQuality.toString().contains('720')
                    );
                  } catch (_) {
                    streamInfo = mp4Streams.first;
                  }
                }
                _logDebug('Selected VideoOnly MP4: ${streamInfo.videoQuality}');
              } else {
                streamInfo = manifest.videoOnly.withHighestBitrate();
                _logDebug('Selected VideoOnly highest bitrate: ${streamInfo.videoQuality}');
              }
            }

            if (streamInfo != null) {
              _logDebug('Downloading YouTube stream to temp file: ${tmpFile.path}');
              if (await tmpFile.exists()) {
                try {
                  await tmpFile.delete();
                } catch (_) {}
              }
              
              final stream = yt.videos.streamsClient.get(streamInfo);
              fileStream = tmpFile.openWrite();
              
              final totalBytes = streamInfo.size.totalBytes;
              _logDebug('Total video stream size: $totalBytes bytes');
              
              int downloadedBytes = 0;
              DateTime lastLogTime = DateTime.now();
              final completer = Completer<void>();
              bool isSuccess = false;
              
              final streamWithTimeout = stream.timeout(
                const Duration(seconds: 45),
                onTimeout: (sink) {
                  _logDebug('Stream download timed out after 45 seconds of inactivity.');
                  sink.addError(TimeoutException('YouTube stream download timed out'));
                  sink.close();
                },
              );

              _downloadSubscription = streamWithTimeout.listen(
                (chunk) {
                  fileStream?.add(chunk);
                  downloadedBytes += chunk.length;
                  
                  final now = DateTime.now();
                  if (now.difference(lastLogTime).inSeconds >= 2) {
                    final pct = totalBytes > 0 ? (downloadedBytes / totalBytes * 100).toStringAsFixed(0) : null;
                    _logDebug('Download progress: ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(2)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB ($pct%)');
                    if (mounted && pct != _downloadProgressPercent) {
                      setState(() {
                        _downloadProgressPercent = pct;
                      });
                    }
                    lastLogTime = now;
                  }
                },
                onError: (err) {
                  _logDebug('Stream listener error: $err');
                  if (!completer.isCompleted) completer.completeError(err);
                },
                onDone: () {
                  _logDebug('Stream listener completed successfully.');
                  if (downloadedBytes >= totalBytes) {
                    isSuccess = true;
                  } else {
                    _logDebug('Stream closed prematurely. Downloaded $downloadedBytes of $totalBytes bytes.');
                  }
                  if (!completer.isCompleted) completer.complete();
                },
                cancelOnError: true,
              );

              await completer.future;
              await _downloadSubscription?.cancel();
              _downloadSubscription = null;
              await fileStream.close();
              fileStream = null;

              if (isSuccess) {
                _logDebug('Download complete. Renaming temp file to target file.');
                if (await targetFile.exists()) {
                  try {
                    await targetFile.delete();
                  } catch (_) {}
                }
                await tmpFile.rename(targetFile.path);
                _logDebug('Rename complete. File size: ${await targetFile.length()} bytes');
                streamUrl = targetFile.path;
              } else {
                _logDebug('Download did not complete successfully. Deleting temp file.');
                if (await tmpFile.exists()) {
                  try {
                    await tmpFile.delete();
                  } catch (_) {}
                }
                throw Exception('Download incomplete');
              }
            } else {
              _logDebug('No suitable stream found for YouTube ID: $youtubeId');
            }
            yt.close();
          } catch (e) {
            _logDebug('YouTube stream download/extraction error: $e');
            await _downloadSubscription?.cancel();
            _downloadSubscription = null;
            if (fileStream != null) {
              try {
                await fileStream.close();
              } catch (_) {}
            }
            if (await tmpFile.exists()) {
              try {
                await tmpFile.delete();
              } catch (_) {}
            }
            if (mounted && _initializingVideoPath == cacheKey) {
              setState(() {
                _downloadProgressPercent = null;
                _videoPlayerController = null;
                _currentVideoPath = null;
                _initializingVideoPath = null;
              });
            }
            return;
          } finally {
            _downloadSubscription = null;
            if (mounted) {
              setState(() {
                _downloadProgressPercent = null;
              });
            }
          }
        }
        
        // Copy YouTube file for separate window to avoid sharing locks on Windows WMF
        if (streamUrl != null && widget.isSeparateWindow) {
          try {
            final tFile = File(streamUrl);
            final extendFile = File('${tempDir.path}${Platform.pathSeparator}queue_background_youtube_v4_${youtubeId}_extend.mp4');
            if (tFile.existsSync()) {
              if (!extendFile.existsSync() || extendFile.lengthSync() != tFile.lengthSync()) {
                tFile.copySync(extendFile.path);
              }
              streamUrl = extendFile.path;
              _logDebug('Copied YouTube file for separate window: $streamUrl');
            }
          } catch (e) {
            _logDebug('Failed to copy YouTube file for separate window: $e');
          }
        }
      } else {
        _logDebug('Not a YouTube ID. Using URL directly.');
        streamUrl = url;
      }

      _logDebug('Extracted Stream URL: $streamUrl');

      if (streamUrl != null && mounted && _initializingVideoPath == cacheKey) {
        final isLocalFile = !streamUrl.startsWith('http://') && !streamUrl.startsWith('https://');
        _logDebug('Creating VideoPlayerController (isLocalFile=$isLocalFile)...');
        _videoPlayerController = isLocalFile
            ? VideoPlayerController.file(File(streamUrl))
            : VideoPlayerController.networkUrl(Uri.parse(streamUrl));

        _videoPlayerController!.initialize().then((_) {
          _logDebug('Controller initialized successfully.');
          if (mounted && _initializingVideoPath == cacheKey) {
            _currentVideoPath = cacheKey;
            _initializingVideoPath = null;
            _videoPlayerController!.setLooping(true);
            _videoPlayerController!.setVolume(0.0);
            _videoPlayerController!.play();
            _logDebug('Playback started.');
            setState(() {});
          } else {
            _logDebug('Initialization done but mounted=$mounted or initializingPath changed.');
          }
        }).catchError((e, s) {
          _logDebug('Error initializing Controller: $e');
          _logDebug('Stacktrace: $s');
          if (mounted && _initializingVideoPath == cacheKey) {
            if (youtubeId != null) {
              final targetFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}queue_background_youtube_v4_$youtubeId.mp4');
              if (targetFile.existsSync()) {
                try {
                  targetFile.deleteSync();
                  _logDebug('Deleted failed cache file to force redownload: ${targetFile.path}');
                } catch (_) {}
              }
            }
            setState(() {
              _videoPlayerController = null;
              _currentVideoPath = null;
              _initializingVideoPath = null;
            });
          }
        });
      } else {
        _logDebug('Will not initialize: streamUrl=$streamUrl, mounted=$mounted, pathMatch=${_initializingVideoPath == cacheKey}');
        if (mounted && _initializingVideoPath == cacheKey) {
          setState(() {
            _initializingVideoPath = null;
          });
        }
      }
    } else {
      _logDebug('Resetting background video player');
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
      _currentVideoPath = null;
      _initializingVideoPath = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _bottomPageController = PageController(initialPage: 0);
    _fullPageController = PageController(initialPage: 0);
    _startPromoSlideTimer();
    _startCycleTimer();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final controller = Provider.of<POSController>(context, listen: false);
        await controller.reloadEnvironment();
        controller.setupEventSubscription();
        _initializeBackgroundVideo();
      } catch (e) {
        print('OrderQueueScreen init controller error: $e');
      }
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _promoSlideTimer?.cancel();
    _bottomPageController?.dispose();
    _fullPageController?.dispose();
    _videoPlayerController?.dispose();
    _downloadSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  List<OfferModel> _getActiveBanners() {
    final controller = Provider.of<POSController>(context, listen: false);
    return controller.offers.where((o) => o.status == 'active').toList();
  }

  bool _isHappyHourCurrentlyActive(Map<String, dynamic> promo) {
    try {
      final now = DateTime.now();
      final currentDay = now.weekday; // 1=Mon, 7=Sun
      
      final daysStr = promo['days_of_week'] ?? '1,2,3,4,5,6,7';
      final days = daysStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
      if (!days.contains(currentDay)) return false;
      
      final startStr = promo['start_time'].toString().substring(0, 5); // HH:mm
      final endStr = promo['end_time'].toString().substring(0, 5); // HH:mm
      
      final currentStr = DateFormat('HH:mm').format(now);
      return currentStr.compareTo(startStr) >= 0 && currentStr.compareTo(endStr) <= 0;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _getActiveHappyHours() {
    final controller = Provider.of<POSController>(context, listen: false);
    return controller.happyHours.where((h) => _isHappyHourCurrentlyActive(h)).toList();
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
        if (DateTime.now().second % 30 == 0) {
          setState(() {});
        }
        return;
      }

      final allPromos = _getCombinedActivePromos();
      final hasPromos = allPromos.isNotEmpty;

      _ticks++;
      if (_isFullScreenPromo) {
        if (_ticks >= 15 || !hasPromos) {
          setState(() {
            _isFullScreenPromo = false;
            _ticks = 0;
            _bottomSlideIndex = 0;
            final int numBatches = (allPromos.length / _batchSize).ceil();
            if (numBatches > 1) {
              _batchIndex = (_batchIndex + 1) % numBatches;
            }
          });
          _bottomPageController = PageController(initialPage: 0);
        }
      } else {
        if (_ticks >= 45 && hasPromos) {
          setState(() {
            _isFullScreenPromo = true;
            _ticks = 0;
            _fullSlideIndex = 0;
          });
          _fullPageController = PageController(initialPage: 0);
        } else if (_ticks >= 45 && !hasPromos) {
          _ticks = 0;
        }
      }

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

      final batchPromos = _getCurrentBatchPromos();
      final totalSlides = batchPromos.length;
      if (totalSlides <= 1) return;

      if (_isFullScreenPromo) {
        setState(() {
          _fullSlideIndex = (_fullSlideIndex + 1) % totalSlides;
        });
        if (_fullPageController != null && _fullPageController!.hasClients) {
          _fullPageController!.animateToPage(
            _fullSlideIndex,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOutCubic,
          );
        }
      } else {
        setState(() {
          _bottomSlideIndex = (_bottomSlideIndex + 1) % totalSlides;
        });
        if (_bottomPageController != null && _bottomPageController!.hasClients) {
          _bottomPageController!.animateToPage(
            _bottomSlideIndex,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOutCubic,
          );
        }
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
    final appSettings = Provider.of<AppSettingsController>(context);

    final isVideo = appSettings.queueBgType == 'video';
    if (isVideo) {
      final expectedCacheKey = appSettings.queueBgVideoSource == 'file'
          ? appSettings.queueBgVideoPath
          : 'link_${appSettings.queueBgVideoUrl}';
      if (_currentVideoPath != expectedCacheKey && _initializingVideoPath != expectedCacheKey) {
        _initializingVideoPath = expectedCacheKey;
        Future.microtask(() => _initializeBackgroundVideo());
      }
    } else if (_videoPlayerController != null) {
      Future.microtask(() {
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        _currentVideoPath = null;
        _initializingVideoPath = null;
        setState(() {});
      });
    }

    bool hasKotItems(OrderModel o) {
      return o.items.any((item) {
        final p = controller.products.firstWhere(
          (prod) => prod.id == item.productId,
          orElse: () => ProductModel(id: 0, name: '', categoryId: 0, price: 0, cost: 0, activePrice: 0, isHappyHour: false, stockQty: 0, minStockLevel: 0, isShortEat: false, isKotItem: false),
        );
        return p.id != 0 && p.isKotItem;
      });
    }

    final preparingOrders = controller.activeOrders
        .where((o) => (o.status == 'pending' || o.status == 'preparing') && hasKotItems(o))
        .toList();
    preparingOrders.sort((a, b) {
      final aTime = DateTime.tryParse(a.createdAt) ?? DateTime.now();
      final bTime = DateTime.tryParse(b.createdAt) ?? DateTime.now();
      return bTime.compareTo(aTime);
    });

    final now = DateTime.now();
    final readyOrders = controller.activeOrders.where((o) {
      if (o.status != 'prepared') return false;
      if (!hasKotItems(o)) return false;
      final timeStr = o.updatedAt ?? o.createdAt;
      final time = DateTime.tryParse(timeStr) ?? now;
      return now.difference(time).inMinutes < 20;
    }).toList();

    readyOrders.sort((a, b) {
      final aTime = DateTime.tryParse(a.updatedAt ?? a.createdAt) ?? now;
      final bTime = DateTime.tryParse(b.updatedAt ?? b.createdAt) ?? now;
      return bTime.compareTo(aTime);
    });

    final batchPromos = _getCurrentBatchPromos();
    final hasPromos = batchPromos.isNotEmpty;

    Widget mainContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _isFullScreenPromo && hasPromos
          ? _buildPromotionsSlideshow(batchPromos)
          : _buildSplitLayout(preparingOrders, readyOrders, batchPromos, hasPromos),
    );

    Widget bodyContent = mainContent;
    if (appSettings.queueBgType != 'none') {
      Widget? bgWidget;
      if (appSettings.queueBgType == 'image' && appSettings.queueBgImageBase64 != null) {
        bgWidget = Positioned.fill(
          child: Opacity(
            opacity: appSettings.queueBgOpacity,
            child: Base64ImageWidget(
              base64Str: appSettings.queueBgImageBase64,
              fit: BoxFit.cover,
            ),
          ),
        );
      } else if (appSettings.queueBgType == 'video') {
        bgWidget = Positioned.fill(
          child: Container(
            color: const Color(0xFF0F172A),
            child: Opacity(
              opacity: appSettings.queueBgOpacity,
              child: _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                  ? SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _videoPlayerController!.value.size.width,
                          height: _videoPlayerController!.value.size.height,
                          child: VideoPlayer(_videoPlayerController!),
                        ),
                      ),
                    )
                  : (appSettings.queueBgVideoSource == 'link' && appSettings.queueBgVideoUrl != null)
                      ? Builder(builder: (context) {
                          final videoId = _getYoutubeId(appSettings.queueBgVideoUrl!);
                          final isDownloading = videoId != null && _downloadSubscription != null;
                          return videoId != null
                              ? Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.network(
                                        'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(color: const Color(0xFF0F172A)),
                                      ),
                                    ),
                                    if (isDownloading)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.black54,
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CircularProgressIndicator(
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  _downloadProgressPercent != null
                                                      ? 'Downloading Background Video ($_downloadProgressPercent%)...'
                                                      : 'Downloading Background Video...',
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'This will take a moment for long videos.',
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : const Center(
                                  child: Icon(Icons.video_library_outlined, size: 200, color: Colors.white10),
                                );
                        })
                      : const Center(
                          child: Icon(Icons.video_file_outlined, size: 200, color: Colors.white10),
                        ),
            ),
          ),
        );
      }

      if (bgWidget != null) {
        bodyContent = Stack(
          children: [
            bgWidget,
            mainContent,
          ],
        );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: bodyContent,
    );
  }

  Widget _buildSplitLayout(List<OrderModel> preparingOrders, List<OrderModel> readyOrders, List<dynamic> batchPromos, bool hasPromos) {
    return Stack(
      children: [
        Column(
          key: const ValueKey('split_layout'),
          children: [
            Expanded(
              child: _buildQueueScreen(preparingOrders, readyOrders),
            ),
            if (hasPromos) ...[
              const Divider(height: 1, color: Color(0xFF334155)),
              Container(
                height: 180,
                color: const Color(0xFF0F172A),
                child: _buildBottomSlideshow(batchPromos),
              ),
            ],
          ],
        ),
        Positioned(
          bottom: hasPromos ? 196 : 16,
          right: 24,
          child: _buildPerpovaBranding(),
        ),
      ],
    );
  }

  Widget _buildPerpovaBranding() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/perpova logo.png',
            height: 28,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.phone_android_rounded,
              color: Colors.white70,
              size: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '+94 71 3 55 55 66',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.95),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueScreen(List<OrderModel> preparingOrders, List<OrderModel> readyOrders) {
    final controller = Provider.of<POSController>(context, listen: false);
    final appSettings = Provider.of<AppSettingsController>(context);
    final activeBanners = _getActiveBanners();
    final activeHappyHours = _getActiveHappyHours();
    final hasPromos = activeBanners.isNotEmpty || activeHappyHours.isNotEmpty;

    return Column(
      children: [
        // Screen Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          color: const Color(0xFF1E293B),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Left Corner (Logo & Title) & Right Corner (Slideshow & Messages)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Corner: Logo, Title, and fullscreen button
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/mhb_logo.png',
                        width: 62,
                        height: 62,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.restaurant_rounded,
                          color: Colors.white70,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 1,
                        height: 32,
                        color: Colors.white24,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'CUSTOMER ORDER STATUS',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // IconButton(
                      //   icon: Icon(
                      //     widget.isSeparateWindow
                      //         ? Icons.close_rounded
                      //         : (appSettings.extendQueueScreen
                      //             ? Icons.fullscreen_exit_rounded
                      //             : Icons.fullscreen_rounded),
                      //     color: Colors.white54,
                      //     size: 20,
                      //   ),
                      //   tooltip: widget.isSeparateWindow
                      //       ? 'Close Window'
                      //       : (appSettings.extendQueueScreen
                      //           ? 'Exit Full Screen'
                      //           : 'Go Full Screen'),
                      //   onPressed: () async {
                      //     if (widget.isSeparateWindow) {
                      //       exit(0);
                      //     } else {
                      //       await appSettings.toggleExtendQueueScreen();
                      //     }
                      //   },
                      // ),
                    ],
                  ),
                  // Right Corner: Slideshow buttons & message
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPromos) ...[
                        // IconButton(
                        //   icon: Icon(
                        //     _isAutoplayPaused
                        //         ? Icons.play_arrow_rounded
                        //         : Icons.pause_rounded,
                        //     color: _isAutoplayPaused
                        //         ? AppTheme.primary
                        //         : const Color(0xFF94A3B8),
                        //     size: 20,
                        //   ),
                        //   onPressed: () {
                        //     setState(() {
                        //       _isAutoplayPaused = !_isAutoplayPaused;
                        //     });
                        //   },
                        // ),
                        // Text(
                        //   _isAutoplayPaused
                        //       ? 'RESUME SLIDESHOW'
                        //       : 'PAUSE SLIDESHOW',
                        //   style: GoogleFonts.inter(
                        //     fontSize: 10,
                        //     fontWeight: FontWeight.bold,
                        //     color: _isAutoplayPaused
                        //         ? AppTheme.primary
                        //         : const Color(0xFF64748B),
                        //     letterSpacing: 0.5,
                        //   ),
                        // ),
                        const SizedBox(width: 20),
                      ],
                      Text(
                        'Please collect when your number is Ready',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Centered branding: Name & Phone number displayed horizontally side-by-side
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'v£ly »ƒ£Šfzx',
                    style: const TextStyle(
                      fontFamily: 'Isiagni',
                      fontSize: 62,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.white30,
                  ),
                  const SizedBox(width: 24),
                  Text(
                    '041 2283857',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
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
                  color: appSettings.queueBgType != 'none' ? const Color(0xFF0F172A).withOpacity(0.85) : const Color(0xFF0F172A),
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
                  color: appSettings.queueBgType != 'none' ? const Color(0xFF0F172A).withOpacity(0.85) : const Color(0xFF0F172A),
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

  Widget _buildBottomSlideshow(List<dynamic> batchPromos) {
    final totalSlides = batchPromos.length;

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
            final promo = batchPromos[index];
            if (promo is OfferModel) {
              return _buildBottomBannerSlide(promo);
            } else {
              return _buildBottomHappyHourSlide(promo);
            }
          },
        ),

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

  Widget _buildPromotionsSlideshow(List<dynamic> batchPromos) {
    final totalSlides = batchPromos.length;

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
            final promo = batchPromos[index];
            if (promo is OfferModel) {
              return _buildBannerSlide(promo);
            } else {
              return _buildHappyHourSlide(promo);
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

        // Clock at the bottom center of the screen
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Center(
            child: const NeonDigitalClock(),
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
                    color: AppTheme.warning,
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
    final categoryId = promo['category_id'];
    final categoryName = promo['category_name'] ?? '';
    final promoPrice = promo['promo_price'];
    final promoPriceVal = double.tryParse(promoPrice.toString()) ?? 0.0;
    
    final prodName = promo['product_name'] ?? '';
    final pModel = _getProductByName(prodName);
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

    if (categoryId != null) {
      final hasImage = promo['image_base64'] != null && promo['image_base64'].toString().length > 200;
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
                child: hasImage
                    ? Base64ImageWidget(
                        base64Str: promo['image_base64'].toString(),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppTheme.accent.withOpacity(0.15),
                        child: const Center(
                          child: Icon(
                            Icons.category_rounded,
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
                    '$categoryName Category Special',
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
                    'Valid: ${_formatTimeString(start)} to ${_formatTimeString(end)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
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
              child: Text(
                '${promoPriceVal.toStringAsFixed(0)}% OFF',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.warning,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      );
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
                            color: AppTheme.warning,
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
                      color: AppTheme.warning,
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
    final categoryId = promo['category_id'];
    final categoryName = promo['category_name'] ?? '';
    final promoPrice = promo['promo_price'];
    final promoPriceVal = double.tryParse(promoPrice.toString()) ?? 0.0;
    
    final prodName = promo['product_name'] ?? '';
    final pModel = _getProductByName(prodName);
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

    if (categoryId != null) {
      final hasImage = promo['image_base64'] != null && promo['image_base64'].toString().length > 200;
      
      Widget childContent = Center(
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
                    child: hasImage
                        ? Base64ImageWidget(
                            base64Str: promo['image_base64'].toString(),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppTheme.accent.withOpacity(0.15),
                            child: const Center(
                              child: Icon(
                                Icons.category_rounded,
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
                      '$categoryName Special',
                      style: GoogleFonts.outfit(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CATEGORY DISCOUNT',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.warning,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              '${promoPriceVal.toStringAsFixed(0)}% OFF',
                              style: GoogleFonts.outfit(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.warning,
                                height: 1,
                              ),
                            ),
                          ],
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
      );

      if (hasImage) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Base64ImageWidget(
              base64Str: promo['image_base64'].toString(),
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
            childContent,
          ],
        );
      } else {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: childContent,
        );
      }
    }

    final hasImage = pModel != null && pModel.imageBase64 != null && pModel.imageBase64!.length > 200;

    Widget childContent = Center(
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
                  child: hasImage
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
    );

    if (hasImage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Base64ImageWidget(
            base64Str: pModel.imageBase64,
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
          childContent,
        ],
      );
    } else {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: childContent,
      );
    }
  }

  Widget _buildQueueToken(String token, bool isReady) {
    return Container(
      decoration: BoxDecoration(
        color: isReady 
            ? AppTheme.accent.withOpacity(0.18) 
            : const Color(0xFF1E293B).withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady ? AppTheme.accent : const Color(0xFF334155).withOpacity(0.7),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          token,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isReady ? AppTheme.accent : Colors.white.withOpacity(0.9),
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

// ── Neon Digital Clock Widget ───────────────────────────────────────────────
class NeonDigitalClock extends StatefulWidget {
  const NeonDigitalClock({super.key});

  @override
  State<NeonDigitalClock> createState() => _NeonDigitalClockState();
}

class _NeonDigitalClockState extends State<NeonDigitalClock> {
  late Timer _timer;
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = DateFormat('hh').format(_currentTime);
    final minutes = DateFormat('mm').format(_currentTime);
    final seconds = DateFormat('ss').format(_currentTime);
    final period = DateFormat('a').format(_currentTime);
    final showColon = _currentTime.second % 2 == 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF007F), // Neon Pink/Magenta
            Color(0xFF00F0FF), // Neon Cyan/Blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF007F).withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(-2, -2),
          ),
          BoxShadow(
            color: const Color(0xFF00F0FF).withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2.5), // Border thickness
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D1B), // Dark digital clock background
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildDigitGroup(hours),
            _buildColon(showColon),
            _buildDigitGroup(minutes),
            _buildColon(showColon),
            _buildDigitGroup(seconds),
            const SizedBox(width: 16),
            _buildAmPm(period),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitGroup(String digits) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFF00F0FF),
          Color(0xFFFF007F),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        digits,
        style: GoogleFonts.orbitron(
          fontSize: 42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 1.5,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildColon(bool show) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.25,
      duration: const Duration(milliseconds: 200),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Color(0xFF00F0FF),
            Color(0xFFFF007F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
        child: Text(
          ':',
          style: GoogleFonts.orbitron(
            fontSize: 42,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildAmPm(String amPm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFF007F).withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Color(0xFFFF007F),
            Color(0xFF00F0FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
        child: Text(
          amPm,
          style: GoogleFonts.orbitron(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
