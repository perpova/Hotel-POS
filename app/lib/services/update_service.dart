import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds information about a discovered GitHub release.
class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String? releaseDate;
  final String? downloadUrl;
  final String? changelog;
  final bool isDirectDownload; // true if downloadUrl points to a .zip asset

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    this.releaseDate,
    this.downloadUrl,
    this.changelog,
    this.isDirectDownload = false,
  });
}

/// Singleton service that checks for new releases on GitHub and handles the
/// self-update flow for the Hotel POS Windows desktop app.
///
/// Mirrors the UpdateService pattern in the `ceylux_new` Flutter project so
/// both apps share the same update architecture.
class UpdateService {
  static final UpdateService _instance = UpdateService._();
  factory UpdateService() => _instance;
  UpdateService._();

  // ── GitHub repo configuration ─────────────────────────────────────────────
  static const String githubRepo = 'Perpova/hotel-pos';
  static const String _apiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';
  static const String _releasesUrl =
      'https://github.com/$githubRepo/releases/latest';

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const String _lastInstalledVersionKey = 'pos_last_installed_version';
  static const String _pendingUpdateVersionKey  = 'pos_pending_update_version';
  static const String _updateAttemptCountKey    = 'pos_update_attempt_count';

  // ── Version comparison ────────────────────────────────────────────────────

  /// Returns `true` when [remoteTag] represents a newer version than the
  /// installed app (described by [currentVersion] + [currentBuild]).
  ///
  /// Supports semantic version strings with an optional `+<build>` suffix.
  bool _isNewerVersion(
      String currentVersion, String currentBuild, String remoteTag) {
    String remote = remoteTag.toLowerCase().startsWith('v')
        ? remoteTag.substring(1)
        : remoteTag;
    String local = currentVersion.toLowerCase().startsWith('v')
        ? currentVersion.substring(1)
        : currentVersion;

    // Normalise: strip anything that isn't digits or dots/plus
    remote = remote.replaceAll(RegExp(r'[^0-9.+]'), '');
    local  = local.replaceAll(RegExp(r'[^0-9.+]'), '');

    final remoteSplit = remote.split('+');
    final localSplit  = local.split('+');

    final remoteVer = remoteSplit[0];
    final localVer  = localSplit[0];

    final remoteBuild = remoteSplit.length > 1 ? remoteSplit[1] : '';
    final localBuild  = localSplit.length  > 1 ? localSplit[1]  : currentBuild;

    final rParts = remoteVer.split('.');
    final lParts = localVer.split('.');
    final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;

    for (int i = 0; i < maxLen; i++) {
      final rNum = i < rParts.length ? int.tryParse(rParts[i]) ?? 0 : 0;
      final lNum = i < lParts.length ? int.tryParse(lParts[i]) ?? 0 : 0;
      if (rNum > lNum) return true;
      if (lNum > rNum) return false;
    }

    if (remoteBuild.isNotEmpty) {
      final rBuildNum = int.tryParse(remoteBuild) ?? 0;
      final lBuildNum = int.tryParse(localBuild)  ?? 0;
      return rBuildNum > lBuildNum;
    }

    return false;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetches the latest GitHub release and compares it against the installed
  /// version.  Returns an [UpdateInfo] describing the result.
  Future<UpdateInfo> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$githubRepo/releases'),
        headers: {
          'Accept':     'application/vnd.github.v3+json',
          'User-Agent': 'HotelPOS-Updater',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const UpdateInfo(hasUpdate: false, latestVersion: '');
      }

      final List<dynamic> releases = jsonDecode(response.body) as List<dynamic>;
      if (releases.isEmpty) {
        return const UpdateInfo(hasUpdate: false, latestVersion: '');
      }

      for (final release in releases) {
        if (release is! Map) continue;
        if (release['draft'] == true) continue;

        final List<dynamic> assets = (release['assets'] as List<dynamic>?) ?? [];
        String? downloadUrl;
        bool isDirectDownload = false;

        for (final asset in assets) {
          if (asset is Map) {
            final name = (asset['name'] as String?) ?? '';
            final lowerName = name.toLowerCase();
            if (lowerName.endsWith('.zip') ||
                (lowerName.endsWith('.apk') && (lowerName.contains('main') || lowerName.contains('pos')) && !lowerName.contains('admin') && !lowerName.contains('staff'))) {
              downloadUrl = asset['browser_download_url'] as String?;
              if (lowerName.endsWith('.zip')) {
                isDirectDownload = true;
              }
              break;
            }
          }
        }

        if (downloadUrl != null) {
          final String remoteTag = (release['tag_name'] as String?) ?? '';
          if (remoteTag.isEmpty) continue;

          final String changelog = (release['body'] as String?) ?? 'No changelog provided.';
          final String rawCreatedAt = (release['created_at'] as String?) ?? '';
          String formattedDate = '';
          if (rawCreatedAt.isNotEmpty) {
            try {
              final dt = DateTime.parse(rawCreatedAt).toLocal();
              formattedDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
            } catch (_) {
              formattedDate = rawCreatedAt.length >= 10 ? rawCreatedAt.substring(0, 10) : rawCreatedAt;
            }
          }

          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersion = packageInfo.version;
          final currentBuild = packageInfo.buildNumber;

          final hasUpdate = _isNewerVersion(currentVersion, currentBuild, remoteTag);

          return UpdateInfo(
            hasUpdate: hasUpdate,
            latestVersion: remoteTag,
            releaseDate: formattedDate,
            downloadUrl: downloadUrl,
            changelog: changelog,
            isDirectDownload: isDirectDownload,
          );
        }
      }

      return const UpdateInfo(hasUpdate: false, latestVersion: '');
    } catch (_) {
      return const UpdateInfo(hasUpdate: false, latestVersion: '');
    }
  }

  // ── Windows self-update ───────────────────────────────────────────────────

  /// Downloads a `.zip` release asset and applies it via a PowerShell script
  /// that runs after the app exits.
  ///
  /// [onProgress] is called with a value from 0.0 to 1.0.
  /// [onError]    is called on failure.
  /// [onComplete] is called just before the app exits to apply the update.
  Future<void> startWindowsUpdate(
    String downloadUrl, {
    required void Function(double progress) onProgress,
    required void Function(String error)    onError,
    required VoidCallback                   onComplete,
  }) async {
    assert(!kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
        'startWindowsUpdate is only supported on Windows desktop.');

    try {
      // ── Download ──────────────────────────────────────────────────────────
      final client  = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final stream  = await client.send(request);

      final total    = stream.contentLength ?? 0;
      int    received = 0;
      final  bytes    = <int>[];

      await stream.stream.forEach((chunk) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(received / total);
        }
      });

      client.close();

      // ── Save zip ──────────────────────────────────────────────────────────
      final tempDir    = Directory.systemTemp.path;
      final zipPath    = '$tempDir\\hotel_pos_update.zip';
      final installDir = File(Platform.resolvedExecutable).parent.path;
      final currentPid = pid;

      await File(zipPath).writeAsBytes(bytes);

      // ── PowerShell script (paths passed as -ArgumentList, not embedded) ───
      // This avoids all string-escaping issues with special path characters.
      const psScript = r'''
param(
    [string]$ZipPath,
    [string]$InstallDir,
    [int]$ParentPid
)

# ── Self-elevate to Administrator if needed ────────────────────────────────
# Required when InstallDir is inside C:\Program Files\ (write-protected)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -ZipPath `"$ZipPath`" -InstallDir `"$InstallDir`" -ParentPid $ParentPid"
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

$LogFile = "$env:TEMP\hotel_pos_update.log"
try { Remove-Item $LogFile -ErrorAction SilentlyContinue } catch {}

function Log([string]$msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Log "=== Hotel POS Auto-Update Started ==="
Log "ZipPath:    $ZipPath"
Log "InstallDir: $InstallDir"
Log "ParentPid:  $ParentPid"

# ── Wait for the app process to exit (max 30 seconds) ─────────────────────
$timeout = 30
$elapsed = 0
while ((Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) -and ($elapsed -lt $timeout)) {
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
}
Log "App exited (waited ${elapsed}s). Starting installation..."

# ── Extract zip ────────────────────────────────────────────────────────────
$ExtractDir = "$env:TEMP\hotel_pos_update_extract"
if (Test-Path $ExtractDir) { Remove-Item -Recurse -Force $ExtractDir }
New-Item -ItemType Directory -Path $ExtractDir | Out-Null

try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractDir -Force
    Log "Zip extracted to: $ExtractDir"
} catch {
    Log "ERROR extracting zip: $_"
    exit 1
}

# ── Find hotel_pos.exe inside extracted content ────────────────────────────
$ExeFile = Get-ChildItem -Path $ExtractDir -Filter "hotel_pos.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ExeFile) {
    Log "ERROR: hotel_pos.exe not found inside zip. Listing extracted contents:"
    Get-ChildItem -Path $ExtractDir -Recurse | ForEach-Object { Log "  $_" }
    exit 1
}

$SourceFolder = $ExeFile.Directory.FullName
Log "Found exe at: $($ExeFile.FullName), copying from: $SourceFolder"

# ── Copy files to install directory (retry up to 10 times) ────────────────
$success = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        Copy-Item -Path "$SourceFolder\*" -Destination $InstallDir -Recurse -Force -ErrorAction Stop
        $success = $true
        Log "Files copied successfully on attempt $i."
        break
    } catch {
        Log "Copy attempt $i failed: $_"
        Start-Sleep -Seconds 1
    }
}

if (-not $success) {
    Log "ERROR: Could not copy update files after 10 attempts."
    exit 1
}

# ── Cleanup ────────────────────────────────────────────────────────────────
try {
    Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue
    Remove-Item -Force $ZipPath -ErrorAction SilentlyContinue
    Log "Cleanup done."
} catch {
    Log "Cleanup warning: $_"
}

# ── Relaunch the updated app ───────────────────────────────────────────────
$NewExe = Join-Path $InstallDir "hotel_pos.exe"
Log "Launching: $NewExe"
try {
    Start-Process -FilePath $NewExe -WorkingDirectory $InstallDir
    Log "App launched successfully."
} catch {
    Log "ERROR launching app: $_"
    exit 1
}

Log "=== Update Complete ==="
''';

      // Write script to temp directory
      final scriptPath = '$tempDir\\hotel_pos_install_update.ps1';
      await File(scriptPath).writeAsString(psScript);

      // ── Launch PowerShell via cmd "start /b" for reliable Windows detachment ─
      // ProcessStartMode.detached alone can still be killed when the parent
      // exits. Using "cmd /c start /b" truly orphans the child process.
      await Process.run('cmd.exe', [
        '/c', 'start', '/b', '',
        'powershell.exe',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-ZipPath', zipPath,
        '-InstallDir', installDir,
        '-ParentPid', currentPid.toString(),
      ]);

      // Small delay so PowerShell is fully running before we exit
      await Future.delayed(const Duration(milliseconds: 1500));

      onComplete();
      exit(0);
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Opens the GitHub releases page in the default browser.
  void openReleasePage([String? url]) {
    final target = url ?? _releasesUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      Process.run('cmd', ['/c', 'start', target]);
    }
  }

  // ── Persistence helpers ───────────────────────────────────────────────────

  Future<void> markUpdateStarted(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingUpdateVersionKey, version);
  }

  Future<void> markUpdateInstalled(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastInstalledVersionKey, version);
    await prefs.remove(_pendingUpdateVersionKey);
    await prefs.setInt(_updateAttemptCountKey, 0);
  }

  Future<String?> getLastInstalledVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastInstalledVersionKey);
  }

  Future<String?> getPendingUpdateVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingUpdateVersionKey);
  }

  Future<int> incrementUpdateAttemptCount() async {
    final prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt(_updateAttemptCountKey) ?? 0;
    count++;
    await prefs.setInt(_updateAttemptCountKey, count);
    return count;
  }

  Future<void> resetUpdateAttemptCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_updateAttemptCountKey, 0);
  }

  /// Returns `true` if this version should be silently skipped (already
  /// installed, or failed too many times).
  Future<bool> shouldSkipUpdate(String remoteVersion) async {
    final lastInstalled = await getLastInstalledVersion();
    if (lastInstalled == remoteVersion) return true;

    final pending = await getPendingUpdateVersion();
    if (pending == remoteVersion) {
      final prefs       = await SharedPreferences.getInstance();
      final attemptCount = prefs.getInt(_updateAttemptCountKey) ?? 0;
      if (attemptCount >= 2) return true;
    }

    return false;
  }
}
