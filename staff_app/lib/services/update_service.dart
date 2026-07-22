import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String? releaseDate;
  final String? downloadUrl;
  final String? changelog;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    this.releaseDate,
    this.downloadUrl,
    this.changelog,
  });
}

class UpdateService {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  static const String githubRepo = 'Perpova/hotel-pos';
  static const String _apiUrl = 'https://api.github.com/repos/$githubRepo/releases/latest';
  static const String _releasesUrl = 'https://github.com/$githubRepo/releases/latest';

  bool _isNewerVersion(String currentVersion, String remoteTag) {
    String remote = remoteTag.toLowerCase().startsWith('v') ? remoteTag.substring(1) : remoteTag;
    String local = currentVersion.toLowerCase().startsWith('v') ? currentVersion.substring(1) : currentVersion;

    remote = remote.replaceAll(RegExp(r'[^0-9.+]'), '');
    local = local.replaceAll(RegExp(r'[^0-9.+]'), '');

    final rParts = remote.split('+')[0].split('.');
    final lParts = local.split('+')[0].split('.');
    final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;

    for (int i = 0; i < maxLen; i++) {
      final rNum = i < rParts.length ? int.tryParse(rParts[i]) ?? 0 : 0;
      final lNum = i < lParts.length ? int.tryParse(lParts[i]) ?? 0 : 0;
      if (rNum > lNum) return true;
      if (lNum > rNum) return false;
    }
    return false;
  }

  Future<UpdateInfo> checkForUpdate({bool manual = false}) async {
    try {
      if (!manual) {
        final prefs = await SharedPreferences.getInstance();
        final suppressDate = prefs.getString('suppress_staff_update_date');
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (suppressDate == today) {
          return const UpdateInfo(hasUpdate: false, latestVersion: '');
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$githubRepo/releases'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'HotelPOS-Staff-Updater',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const UpdateInfo(hasUpdate: false, latestVersion: '');
      }

      final List<dynamic> releases = jsonDecode(response.body);
      if (releases.isEmpty) {
        return const UpdateInfo(hasUpdate: false, latestVersion: '');
      }

      for (final release in releases) {
        if (release is! Map) continue;
        if (release['draft'] == true) continue;

        final List<dynamic> assets = (release['assets'] as List<dynamic>?) ?? [];
        String? downloadUrl;

        for (final asset in assets) {
          if (asset is Map) {
            final name = (asset['name'] as String?) ?? '';
            if (name.toLowerCase().contains('staff') && name.toLowerCase().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
        }

        if (downloadUrl != null) {
          final String remoteTag = (release['tag_name'] as String?) ?? '';
          final String changelog = (release['body'] as String?) ?? 'General performance improvements and bug fixes.';
          final String rawCreatedAt = (release['created_at'] as String?) ?? '';

          String formattedDate = '';
          if (rawCreatedAt.isNotEmpty) {
            try {
              final dt = DateTime.parse(rawCreatedAt).toLocal();
              formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
            } catch (_) {
              formattedDate = rawCreatedAt.length >= 10 ? rawCreatedAt.substring(0, 10) : rawCreatedAt;
            }
          }

          final bool hasUpdate = _isNewerVersion(currentVersion, remoteTag);

          return UpdateInfo(
            hasUpdate: hasUpdate,
            latestVersion: remoteTag,
            releaseDate: formattedDate,
            downloadUrl: downloadUrl,
            changelog: changelog,
          );
        }
      }

      return const UpdateInfo(hasUpdate: false, latestVersion: '');
    } catch (e) {
      debugPrint('Error checking for staff app updates: $e');
      return const UpdateInfo(hasUpdate: false, latestVersion: '');
    }
  }

  Future<bool> launchUpdate(UpdateInfo info) async {
    final targetUrl = info.downloadUrl ?? _releasesUrl;
    try {
      final uri = Uri.parse(targetUrl);
      bool launched = false;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (_) {}
      }
      return launched;
    } catch (e) {
      debugPrint('Error launching update URL: $e');
      return false;
    }
  }

  Future<void> downloadAndInstallApk(
    String apkUrl, {
    required Function(double progress) onProgress,
    required Function(String error) onError,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        onError('HTTP ${response.statusCode} download error');
        client.close();
        return;
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final bytes = <int>[];

      await response.stream.forEach((chunk) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(received / total);
        }
      });
      client.close();

      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/hotel_staff_update.apk');
      await apkFile.writeAsBytes(bytes);

      final result = await OpenFilex.open(apkFile.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        final uri = Uri.parse(apkUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      onError(e.toString());
    }
  }
}
