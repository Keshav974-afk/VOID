import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class DesktopWindowInfo {
  const DesktopWindowInfo({
    required this.pid,
    required this.processName,
    required this.title,
    this.isActive = false,
  });

  final int pid;
  final String processName;
  final String title;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'process_name': processName,
    'title': title,
    'is_active': isActive,
  };
}

class DesktopSystemOverview {
  const DesktopSystemOverview({
    required this.platform,
    required this.osVersion,
    required this.hostname,
    required this.username,
    required this.cpuCores,
    required this.totalMemoryMb,
    required this.freeMemoryMb,
    required this.usedMemoryMb,
    required this.memoryUsagePercent,
    this.diskTotalGb,
    this.diskFreeGb,
    this.batteryPercent,
    this.isCharging,
    this.activeWindowTitle,
    this.screenWidth,
    this.screenHeight,
  });

  final String platform;
  final String osVersion;
  final String hostname;
  final String username;
  final int cpuCores;
  final int totalMemoryMb;
  final int freeMemoryMb;
  final int usedMemoryMb;
  final double memoryUsagePercent;
  final double? diskTotalGb;
  final double? diskFreeGb;
  final int? batteryPercent;
  final bool? isCharging;
  final String? activeWindowTitle;
  final int? screenWidth;
  final int? screenHeight;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'os_version': osVersion,
    'hostname': hostname,
    'username': username,
    'cpu_cores': cpuCores,
    'total_memory_mb': totalMemoryMb,
    'free_memory_mb': freeMemoryMb,
    'used_memory_mb': usedMemoryMb,
    'memory_usage_percent': double.parse(memoryUsagePercent.toStringAsFixed(1)),
    if (diskTotalGb != null)
      'disk_total_gb': double.parse(diskTotalGb!.toStringAsFixed(1)),
    if (diskFreeGb != null)
      'disk_free_gb': double.parse(diskFreeGb!.toStringAsFixed(1)),
    if (batteryPercent != null) 'battery_percent': batteryPercent,
    if (isCharging != null) 'is_charging': isCharging,
    if (activeWindowTitle != null && activeWindowTitle!.isNotEmpty)
      'active_window_title': activeWindowTitle,
    if (screenWidth != null && screenHeight != null)
      'screen_resolution': '${screenWidth}x$screenHeight',
  };
}

class DesktopUiNode {
  const DesktopUiNode({
    required this.id,
    required this.text,
    required this.type,
    required this.bounds,
    required this.center,
    this.clickable = false,
    this.editable = false,
    this.focused = false,
  });

  final String id;
  final String text;
  final String type;
  final List<int> bounds;
  final List<int> center;
  final bool clickable;
  final bool editable;
  final bool focused;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'type': type,
    'bounds': bounds,
    'center': center,
    'clickable': clickable,
    'editable': editable,
    if (focused) 'focused': true,
  };
}

/// Cross-platform Desktop Control service for Windows, macOS, and Linux.
/// Provides native window management, mouse/keyboard automation, screenshots,
/// application launching, audio/media controls, and system telemetry.
class DesktopControlService {
  DesktopControlService._();
  static final DesktopControlService instance = DesktopControlService._();

  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Executes a desktop control action and returns a JSON-encoded result.
  Future<String> executeAction(Map<String, dynamic> args) async {
    final rawAction = (args['action'] ?? 'system_info')
        .toString()
        .trim()
        .toLowerCase();

    try {
      switch (rawAction) {
        case 'system_info':
        case 'get_system_info':
        case 'status':
          final info = await getSystemOverview();
          return jsonEncode({'status': 'ok', 'system': info.toJson()});

        case 'read_screen':
          final result = await readScreen();
          return jsonEncode(result);

        case 'click_text':
          final query = (args['text'] ?? args['query'] ?? args['label'] ?? '')
              .toString()
              .trim();
          if (query.isEmpty) {
            return jsonEncode({
              'status': 'error',
              'message': 'Missing text or query parameter for click_text.',
            });
          }
          final res = await clickText(query);
          return jsonEncode(res);

        case 'list_windows':
        case 'windows':
          final windows = await listOpenWindows();
          final sys = await getSystemOverview();
          return jsonEncode({
            'status': 'ok',
            'platform': sys.platform,
            'active_window': sys.activeWindowTitle,
            'screen_width': sys.screenWidth ?? 1920,
            'screen_height': sys.screenHeight ?? 1080,
            'window_count': windows.length,
            'windows': windows.map((w) => w.toJson()).toList(),
          });

        case 'focus_window':
        case 'activate_window':
          final query =
              (args['window_title'] ??
                      args['title'] ??
                      args['app_name'] ??
                      args['text'] ??
                      '')
                  .toString()
                  .trim();
          final pid = (args['pid'] as num?)?.toInt();
          final ok = await focusWindow(query: query, pid: pid);
          return jsonEncode({
            'status': ok ? 'ok' : 'not_found',
            'action': 'focus_window',
            'target': query.isNotEmpty ? query : pid?.toString(),
          });

        case 'close_window':
        case 'kill_app':
          final query =
              (args['window_title'] ??
                      args['title'] ??
                      args['app_name'] ??
                      args['process_name'] ??
                      '')
                  .toString()
                  .trim();
          final pid = (args['pid'] as num?)?.toInt();
          final ok = await closeWindowOrApp(query: query, pid: pid);
          return jsonEncode({
            'status': ok ? 'ok' : 'failed',
            'action': 'close_window',
            'target': query.isNotEmpty ? query : pid?.toString(),
          });

        case 'open_app':
        case 'launch_app':
          final appName =
              (args['app_name'] ??
                      args['package_name'] ??
                      args['executable'] ??
                      args['text'] ??
                      '')
                  .toString()
                  .trim();
          final uri = (args['uri'] ?? args['url'] ?? '').toString().trim();
          if (uri.isNotEmpty && appName.isEmpty) {
            final opened = await openUrlOrUri(uri);
            return jsonEncode({
              'status': opened ? 'ok' : 'failed',
              'action': 'open_url',
              'uri': uri,
            });
          }
          final launched = await openApplication(
            appName,
            arguments: args['arguments']?.toString(),
          );
          return jsonEncode({
            'status': launched ? 'ok' : 'failed',
            'action': 'open_app',
            'app_name': appName,
          });

        case 'open_url':
          final url = (args['url'] ?? args['uri'] ?? args['text'] ?? '')
              .toString()
              .trim();
          final opened = await openUrlOrUri(url);
          return jsonEncode({
            'status': opened ? 'ok' : 'failed',
            'action': 'open_url',
            'url': url,
          });

        case 'list_apps':
        case 'list_processes':
          final apps = await listRunningApps();
          return jsonEncode({
            'status': 'ok',
            'count': apps.length,
            'apps': apps,
          });

        case 'screenshot':
        case 'take_screenshot':
          final path = await captureScreenshot();
          if (path == null) {
            return jsonEncode({
              'status': 'error',
              'message': 'Failed to capture desktop screenshot.',
            });
          }
          return jsonEncode({
            'status': 'ok',
            'action': 'screenshot',
            'file_path': path,
            'message': 'Screenshot saved to $path',
          });

        case 'click':
        case 'tap':
        case 'double_click':
        case 'right_click':
        case 'long_press':
          final x = (args['x'] as num?)?.toInt();
          final y = (args['y'] as num?)?.toInt();
          final button =
              (rawAction == 'right_click' || rawAction == 'long_press')
              ? 'right'
              : (args['button']?.toString() ?? 'left');
          final isDouble =
              rawAction == 'double_click' || (args['double_click'] == true);
          if (x == null || y == null) {
            final targetQuery = (args['text'] ??
                    args['query'] ??
                    args['label'] ??
                    args['window_title'] ??
                    '')
                .toString()
                .trim();
            if (targetQuery.isNotEmpty) {
              final res = await clickText(
                targetQuery,
                doubleClick: isDouble,
                button: button,
              );
              return jsonEncode(res);
            }
            return jsonEncode({
              'status': 'error',
              'message':
                  'x and y coordinates or a text/query parameter are required for click.',
            });
          }
          final clicked = await mouseClick(
            x: x,
            y: y,
            button: button,
            doubleClick: isDouble,
          );
          return jsonEncode({
            'status': clicked ? 'ok' : 'failed',
            'action': rawAction,
            'x': x,
            'y': y,
            'button': button,
          });

        case 'mouse_move':
        case 'move_mouse':
          final x = (args['x'] as num?)?.toInt() ?? 0;
          final y = (args['y'] as num?)?.toInt() ?? 0;
          final moved = await mouseMove(x, y);
          return jsonEncode({
            'status': moved ? 'ok' : 'failed',
            'action': 'mouse_move',
            'x': x,
            'y': y,
          });

        case 'scroll':
        case 'swipe':
          final direction = (args['direction'] ?? 'down')
              .toString()
              .toLowerCase();
          final amount = (args['amount'] as num?)?.toInt() ?? 5;
          final ok = await mouseScroll(direction: direction, clicks: amount);
          return jsonEncode({
            'status': ok ? 'ok' : 'failed',
            'action': 'scroll',
            'direction': direction,
            'amount': amount,
          });

        case 'type_text':
        case 'set_text':
          final text = (args['text'] ?? '').toString();
          if (text.isEmpty) {
            return jsonEncode({
              'status': 'error',
              'message': 'Missing text parameter for type_text.',
            });
          }
          final typed = await typeText(text);
          return jsonEncode({
            'status': typed ? 'ok' : 'failed',
            'action': 'type_text',
            'length': text.length,
          });

        case 'send_keys':
        case 'hotkey':
        case 'shortcut':
        case 'back':
        case 'home':
        case 'recents':
          String keys = (args['keys'] ?? args['shortcut'] ?? args['text'] ?? '')
              .toString()
              .trim();
          if (rawAction == 'back' && keys.isEmpty) keys = 'alt+left';
          if (rawAction == 'home' && keys.isEmpty) keys = 'win+d';
          if (rawAction == 'recents' && keys.isEmpty) keys = 'alt+tab';
          final sent = await sendHotkey(keys);
          return jsonEncode({
            'status': sent ? 'ok' : 'failed',
            'action': 'send_keys',
            'keys': keys,
          });

        case 'volume':
        case 'media':
        case 'media_control':
          final mediaAction =
              (args['media_action'] ??
                      args['command'] ??
                      args['direction'] ??
                      'mute')
                  .toString()
                  .toLowerCase();
          final ok = await controlMediaOrVolume(mediaAction);
          return jsonEncode({
            'status': ok ? 'ok' : 'failed',
            'action': 'media_control',
            'command': mediaAction,
          });

        case 'clipboard_read':
        case 'get_clipboard':
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          return jsonEncode({'status': 'ok', 'text': data?.text ?? ''});

        case 'clipboard_write':
        case 'set_clipboard':
          final text = (args['text'] ?? '').toString();
          await Clipboard.setData(ClipboardData(text: text));
          return jsonEncode({'status': 'ok', 'length': text.length});

        case 'lock_screen':
        case 'lock':
          final ok = await lockScreen();
          return jsonEncode({
            'status': ok ? 'ok' : 'failed',
            'action': 'lock_screen',
          });

        default:
          return jsonEncode({
            'status': 'error',
            'message': 'Unsupported desktop_control action: $rawAction',
          });
      }
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'action': rawAction,
        'message': e.toString(),
      });
    }
  }

  /// Collects live OS, CPU, RAM, disk, battery, and active window metrics.
  Future<DesktopSystemOverview> getSystemOverview() async {
    final platform = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    final hostname = Platform.localHostname;
    final username =
        Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        'user';
    final cpuCores = Platform.numberOfProcessors;

    int totalMemMb = 8192;
    int freeMemMb = 4096;
    double? diskTotalGb;
    double? diskFreeGb;
    int? batteryPercent;
    bool? isCharging;
    String? activeWindow;
    int? screenW;
    int? screenH;

    if (!kIsWeb && Platform.isWindows) {
      try {
        final script = r'''
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Helper {
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")]
  public static extern int GetSystemMetrics(int nIndex);
}
"@ -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder 512
$hwnd = [Win32Helper]::GetForegroundWindow()
[void][Win32Helper]::GetWindowText($hwnd, $sb, 512)
$sw = [Win32Helper]::GetSystemMetrics(0)
$sh = [Win32Helper]::GetSystemMetrics(1)
$res = @{
  totalMemKb = if ($os) { $os.TotalVisibleMemorySize } else { 0 }
  freeMemKb = if ($os) { $os.FreePhysicalMemory } else { 0 }
  diskTotal = if ($disk) { $disk.Size } else { 0 }
  diskFree = if ($disk) { $disk.FreeSpace } else { 0 }
  battery = if ($bat) { $bat.EstimatedChargeRemaining } else { $null }
  batStatus = if ($bat) { $bat.BatteryStatus } else { $null }
  activeTitle = $sb.ToString()
  screenW = $sw
  screenH = $sh
}
$res | ConvertTo-Json -Compress
''';
        final proc = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 6));
        if (proc.exitCode == 0) {
          final raw = proc.stdout.toString().trim();
          if (raw.isNotEmpty) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final totalKb = (map['totalMemKb'] as num?)?.toInt() ?? 0;
            final freeKb = (map['freeMemKb'] as num?)?.toInt() ?? 0;
            if (totalKb > 0) {
              totalMemMb = (totalKb / 1024).round();
              freeMemMb = (freeKb / 1024).round();
            }
            final dTotal = (map['diskTotal'] as num?)?.toDouble() ?? 0;
            final dFree = (map['diskFree'] as num?)?.toDouble() ?? 0;
            if (dTotal > 0) {
              diskTotalGb = dTotal / (1024 * 1024 * 1024);
              diskFreeGb = dFree / (1024 * 1024 * 1024);
            }
            batteryPercent = (map['battery'] as num?)?.toInt();
            final batStatus = (map['batStatus'] as num?)?.toInt();
            if (batStatus != null) {
              isCharging = batStatus == 2 || batStatus == 6 || batStatus == 7;
            }
            activeWindow = map['activeTitle']?.toString();
            final sw = (map['screenW'] as num?)?.toInt() ?? 0;
            final sh = (map['screenH'] as num?)?.toInt() ?? 0;
            if (sw > 0 && sh > 0) {
              screenW = sw;
              screenH = sh;
            }
          }
        }
      } catch (_) {}
    } else if (!kIsWeb && Platform.isMacOS) {
      try {
        final memProc = await Process.run('sysctl', [
          '-n',
          'hw.memsize',
        ]).timeout(const Duration(seconds: 3));
        final bytes = int.tryParse(memProc.stdout.toString().trim()) ?? 0;
        if (bytes > 0) {
          totalMemMb = (bytes / (1024 * 1024)).round();
        }
        final vmProc = await Process.run(
          'vm_stat',
          [],
        ).timeout(const Duration(seconds: 3));
        final vmOut = vmProc.stdout.toString();
        final freeMatch = RegExp(r'Pages free:\s+(\d+)').firstMatch(vmOut);
        final inactiveMatch = RegExp(
          r'Pages inactive:\s+(\d+)',
        ).firstMatch(vmOut);
        if (freeMatch != null) {
          final freePages = int.tryParse(freeMatch.group(1)!) ?? 0;
          final inactivePages =
              int.tryParse(inactiveMatch?.group(1) ?? '0') ?? 0;
          freeMemMb = ((freePages + inactivePages) * 4096 / (1024 * 1024))
              .round();
        }
        final dfProc = await Process.run('df', [
          '-k',
          '/',
        ]).timeout(const Duration(seconds: 3));
        final lines = dfProc.stdout.toString().trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final totalKb = double.tryParse(parts[1]) ?? 0;
            final availKb = double.tryParse(parts[3]) ?? 0;
            if (totalKb > 0) {
              diskTotalGb = totalKb / (1024 * 1024);
              diskFreeGb = availKb / (1024 * 1024);
            }
          }
        }
        final winProc = await Process.run('osascript', [
          '-e',
          'tell application "System Events" to get name of first application process whose frontmost is true',
        ]).timeout(const Duration(seconds: 3));
        if (winProc.exitCode == 0) {
          activeWindow = winProc.stdout.toString().trim();
        }
      } catch (_) {}
    } else if (!kIsWeb && Platform.isLinux) {
      try {
        final memFile = File('/proc/meminfo');
        if (await memFile.exists()) {
          final content = await memFile.readAsString();
          final totalMatch = RegExp(r'MemTotal:\s+(\d+)').firstMatch(content);
          final availMatch = RegExp(
            r'MemAvailable:\s+(\d+)',
          ).firstMatch(content);
          if (totalMatch != null) {
            totalMemMb = ((int.tryParse(totalMatch.group(1)!) ?? 0) / 1024)
                .round();
          }
          if (availMatch != null) {
            freeMemMb = ((int.tryParse(availMatch.group(1)!) ?? 0) / 1024)
                .round();
          }
        }
        final dfProc = await Process.run('df', [
          '-k',
          '/',
        ]).timeout(const Duration(seconds: 3));
        final lines = dfProc.stdout.toString().trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final totalKb = double.tryParse(parts[1]) ?? 0;
            final availKb = double.tryParse(parts[3]) ?? 0;
            if (totalKb > 0) {
              diskTotalGb = totalKb / (1024 * 1024);
              diskFreeGb = availKb / (1024 * 1024);
            }
          }
        }
        final xdoProc = await Process.run('xdotool', [
          'getactivewindow',
          'getwindowname',
        ]).timeout(const Duration(seconds: 2));
        if (xdoProc.exitCode == 0) {
          activeWindow = xdoProc.stdout.toString().trim();
        }
      } catch (_) {}
    }

    final usedMemMb = (totalMemMb - freeMemMb).clamp(0, totalMemMb);
    final memPct = totalMemMb > 0 ? (usedMemMb / totalMemMb) * 100.0 : 0.0;

    return DesktopSystemOverview(
      platform: platform,
      osVersion: osVersion,
      hostname: hostname,
      username: username,
      cpuCores: cpuCores,
      totalMemoryMb: totalMemMb,
      freeMemoryMb: freeMemMb,
      usedMemoryMb: usedMemMb,
      memoryUsagePercent: memPct,
      diskTotalGb: diskTotalGb,
      diskFreeGb: diskFreeGb,
      batteryPercent: batteryPercent,
      isCharging: isCharging,
      activeWindowTitle: activeWindow,
      screenWidth: screenW,
      screenHeight: screenH,
    );
  }

  /// Reads the entire desktop screen, capturing a screenshot and extracting
  /// visible interactive UI elements (buttons, edit fields, text, windows)
  /// with their coordinates, matching mobile screen reading capabilities.
  Future<Map<String, dynamic>> readScreen({bool captureImage = true}) async {
    final sys = await getSystemOverview();
    final windows = await listOpenWindows();
    String? screenshotPath;
    if (captureImage) {
      screenshotPath = await captureScreenshot();
    }

    final nodes = <DesktopUiNode>[];
    var nodeIdx = 0;

    if (!kIsWeb && Platform.isWindows) {
      try {
        const uiaScript = r'''
Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = [System.Windows.Automation.Condition]::TrueCondition
$topWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
$items = @()

foreach ($win in $topWindows) {
  try {
    if ($win.Current.IsOffscreen -or [string]::IsNullOrWhiteSpace($win.Current.Name)) { continue }
    $wrect = $win.Current.BoundingRectangle
    if ($wrect.Width -le 0 -or $wrect.Height -le 0) { continue }
    $items += [PSCustomObject]@{
      text = $win.Current.Name
      type = "Window"
      x = [int]$wrect.X
      y = [int]$wrect.Y
      w = [int]$wrect.Width
      h = [int]$wrect.Height
      clickable = $true
      editable = $false
    }
    $children = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    foreach ($c in $children) {
      try {
        if ($c.Current.IsOffscreen) { continue }
        $txt = $c.Current.Name
        $tp = $c.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        if ([string]::IsNullOrWhiteSpace($txt) -and $tp -notmatch 'Edit|Button|Document') { continue }
        $r = $c.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { continue }
        $isClick = ($tp -match 'Button|Hyperlink|MenuItem|ListItem|TabItem|CheckBox|RadioButton|ComboBox')
        $isEdit = ($tp -match 'Edit|Document')
        $items += [PSCustomObject]@{
          text = if ($txt) { $txt.Trim() } else { "" }
          type = $tp
          x = [int]$r.X
          y = [int]$r.Y
          w = [int]$r.Width
          h = [int]$r.Height
          clickable = $isClick
          editable = $isEdit
        }
        if ($items.Count -ge 80) { break }
      } catch {}
    }
    if ($items.Count -ge 80) { break }
  } catch {}
}
$items | ConvertTo-Json -Compress
''';
        final proc = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          uiaScript,
        ]).timeout(const Duration(seconds: 5));
        if (proc.exitCode == 0) {
          final out = proc.stdout.toString().trim();
          if (out.isNotEmpty) {
            final decoded = jsonDecode(out);
            final list = decoded is List ? decoded : [decoded];
            for (final it in list) {
              if (it is Map) {
                final x = (it['x'] as num?)?.toInt() ?? 0;
                final y = (it['y'] as num?)?.toInt() ?? 0;
                final w = (it['w'] as num?)?.toInt() ?? 0;
                final h = (it['h'] as num?)?.toInt() ?? 0;
                nodeIdx++;
                nodes.add(
                  DesktopUiNode(
                    id: 'node_$nodeIdx',
                    text: (it['text'] ?? '').toString(),
                    type: (it['type'] ?? 'Control').toString(),
                    bounds: [x, y, w, h],
                    center: [x + (w ~/ 2), y + (h ~/ 2)],
                    clickable: it['clickable'] == true,
                    editable: it['editable'] == true,
                  ),
                );
              }
            }
          }
        }
      } catch (_) {}
    }

    // Ensure all open windows are listed as nodes if not already included
    for (final win in windows) {
      if (win.title.trim().isNotEmpty &&
          !nodes.any((n) => n.text == win.title)) {
        nodeIdx++;
        final x = 100;
        final y = 60 + (nodeIdx * 35);
        nodes.add(
          DesktopUiNode(
            id: 'win_$nodeIdx',
            text: win.title,
            type: 'Window',
            bounds: [x, y, 400, 30],
            center: [x + 200, y + 15],
            clickable: true,
            editable: false,
            focused: win.isActive,
          ),
        );
      }
    }

    final screenTextBuilder = StringBuffer();
    for (final n in nodes) {
      if (n.text.isNotEmpty) {
        screenTextBuilder.writeln('${n.type}: ${n.text}');
      }
    }

    return {
      'status': 'ok',
      'action': 'read_screen',
      'platform': sys.platform,
      'active_window': sys.activeWindowTitle,
      'screen_width': sys.screenWidth ?? 1920,
      'screen_height': sys.screenHeight ?? 1080,
      'screenshot': screenshotPath,
      'node_count': nodes.length,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'screen_text': screenTextBuilder.toString().trim(),
      'windows': windows.map((w) => w.toJson()).toList(),
    };
  }

  /// Finds an element or window on the desktop matching [query] and clicks it.
  Future<Map<String, dynamic>> clickText(
    String query, {
    bool doubleClick = false,
    String button = 'left',
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    final screen = await readScreen(captureImage: false);
    final rawNodes = screen['nodes'] as List<dynamic>? ?? const [];

    Map<String, dynamic>? match;
    for (final raw in rawNodes) {
      if (raw is Map) {
        final text = (raw['text'] ?? '').toString().toLowerCase();
        if (text == cleanQuery) {
          match = raw.cast<String, dynamic>();
          break;
        } else if (text.contains(cleanQuery) && match == null) {
          match = raw.cast<String, dynamic>();
        }
      }
    }

    if (match != null) {
      final center = (match['center'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList();
      if (center != null && center.length >= 2) {
        final cx = center[0];
        final cy = center[1];
        final clicked = await mouseClick(
          x: cx,
          y: cy,
          button: button,
          doubleClick: doubleClick,
        );
        return {
          'status': clicked ? 'ok' : 'failed',
          'action': 'click_text',
          'query': query,
          'matched_text': match['text'],
          'matched_type': match['type'],
          'clicked_at': {'x': cx, 'y': cy},
        };
      }
    }

    // Fall back to bringing matching window to front
    final focused = await focusWindow(query: query);
    return {
      'status': focused ? 'ok' : 'not_found',
      'action': 'click_text',
      'query': query,
      'message': focused
          ? 'Window matching "$query" brought to front.'
          : 'Could not find interactive element or window matching "$query".',
    };
  }

  /// Lists open desktop windows across Windows, macOS, and Linux.
  Future<List<DesktopWindowInfo>> listOpenWindows() async {
    final windows = <DesktopWindowInfo>[];
    if (kIsWeb) return windows;

    try {
      if (Platform.isWindows) {
        const script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFg {
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
}
"@ -ErrorAction SilentlyContinue
$fg = [WinFg]::GetForegroundWindow()
Get-Process | Where-Object { $_.MainWindowTitle -ne "" } | ForEach-Object {
  [PSCustomObject]@{
    pid = $_.Id
    name = $_.ProcessName
    title = $_.MainWindowTitle
    active = ($_.MainWindowHandle -eq $fg)
  }
} | ConvertTo-Json -Compress
''';
        final proc = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 6));
        if (proc.exitCode == 0) {
          final raw = proc.stdout.toString().trim();
          if (raw.isNotEmpty) {
            final decoded = jsonDecode(raw);
            final list = decoded is List ? decoded : [decoded];
            for (final item in list) {
              if (item is Map) {
                windows.add(
                  DesktopWindowInfo(
                    pid: (item['pid'] as num?)?.toInt() ?? 0,
                    processName: (item['name'] ?? '').toString(),
                    title: (item['title'] ?? '').toString(),
                    isActive: item['active'] == true,
                  ),
                );
              }
            }
          }
        }
      } else if (Platform.isMacOS) {
        const script = '''
tell application "System Events"
  set outList to {}
  repeat with p in (every application process whose background only is false)
    set pName to name of p
    set pId to unix id of p
    set isFront to frontmost of p
    set end of outList to (pId as string) & "|" & pName & "|" & (isFront as string)
  end repeat
  return outList
end tell
''';
        final proc = await Process.run('osascript', [
          '-e',
          script,
        ]).timeout(const Duration(seconds: 5));
        if (proc.exitCode == 0) {
          final parts = proc.stdout.toString().trim().split(', ');
          for (final entry in parts) {
            final segs = entry.split('|');
            if (segs.length >= 3) {
              windows.add(
                DesktopWindowInfo(
                  pid: int.tryParse(segs[0].trim()) ?? 0,
                  processName: segs[1].trim(),
                  title: segs[1].trim(),
                  isActive: segs[2].trim().toLowerCase() == 'true',
                ),
              );
            }
          }
        }
      } else if (Platform.isLinux) {
        final proc = await Process.run('wmctrl', [
          '-l',
          '-p',
        ]).timeout(const Duration(seconds: 3));
        if (proc.exitCode == 0) {
          for (final line in proc.stdout.toString().trim().split('\n')) {
            final cols = line.trim().split(RegExp(r'\s+'));
            if (cols.length >= 5) {
              final pid = int.tryParse(cols[2]) ?? 0;
              final title = cols.sublist(4).join(' ');
              windows.add(
                DesktopWindowInfo(pid: pid, processName: cols[3], title: title),
              );
            }
          }
        }
      }
    } catch (_) {}
    return windows;
  }

  /// Brings a window matching [query] or [pid] to the foreground.
  Future<bool> focusWindow({String query = '', int? pid}) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final escaped = query.replaceAll("'", "''");
        final script =
            '''
\$wshell = New-Object -ComObject wscript.shell
${pid != null ? 'if (\$wshell.AppActivate($pid)) { exit 0 }' : ''}
\$proc = Get-Process | Where-Object {
  \$_.MainWindowTitle -like "*$escaped*" -or \$_.ProcessName -like "*$escaped*"
} | Select-Object -First 1
if (\$proc) {
  [void]\$wshell.AppActivate(\$proc.Id)
  exit 0
}
exit 1
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final escaped = query.replaceAll('"', '\\"');
        final res = await Process.run('osascript', [
          '-e',
          'tell application "$escaped" to activate',
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('wmctrl', [
          '-a',
          query,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Gracefully closes a window or stops a process matching [query] or [pid].
  Future<bool> closeWindowOrApp({String query = '', int? pid}) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final escaped = query.replaceAll("'", "''");
        final script = pid != null
            ? 'Stop-Process -Id $pid -ErrorAction Stop'
            : '''
\$procs = Get-Process | Where-Object {
  \$_.MainWindowTitle -like "*$escaped*" -or \$_.ProcessName -like "*$escaped*"
}
if (-not \$procs) { exit 1 }
foreach (\$p in \$procs) {
  if (-not \$p.CloseMainWindow()) {
    Stop-Process -Id \$p.Id -Force -ErrorAction SilentlyContinue
  }
}
exit 0
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 5));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        if (pid != null) {
          return Process.killPid(pid);
        }
        final escaped = query.replaceAll('"', '\\"');
        final res = await Process.run('osascript', [
          '-e',
          'tell application "$escaped" to quit',
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        if (pid != null) {
          return Process.killPid(pid);
        }
        final res = await Process.run('wmctrl', [
          '-c',
          query,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Opens a desktop application by friendly name or executable path.
  Future<bool> openApplication(String appName, {String? arguments}) async {
    final clean = appName.trim();
    if (clean.isEmpty || kIsWeb) return false;

    if (clean.startsWith('http://') ||
        clean.startsWith('https://') ||
        clean.startsWith('mailto:')) {
      return openUrlOrUri(clean);
    }

    try {
      if (Platform.isWindows) {
        final lower = clean.toLowerCase();
        final resolved = switch (lower) {
          'notepad' => 'notepad.exe',
          'calculator' || 'calc' => 'calc.exe',
          'explorer' || 'file explorer' || 'files' => 'explorer.exe',
          'cmd' || 'command prompt' => 'cmd.exe',
          'powershell' || 'terminal' => 'powershell.exe',
          'paint' || 'mspaint' => 'mspaint.exe',
          'task manager' || 'taskmgr' => 'taskmgr.exe',
          'settings' || 'system settings' => 'ms-settings:',
          'control panel' => 'control.exe',
          'vscode' || 'vs code' || 'code' => 'code',
          'chrome' || 'google chrome' => 'chrome',
          'edge' || 'microsoft edge' => 'msedge',
          'firefox' => 'firefox',
          'spotify' => 'spotify:',
          'whatsapp' => 'whatsapp:',
          'discord' => 'discord:',
          _ => clean,
        };
        if (resolved.endsWith(':')) {
          return await openUrlOrUri(resolved);
        }
        final escaped = resolved.replaceAll("'", "''");
        final argPart = (arguments != null && arguments.trim().isNotEmpty)
            ? " -ArgumentList '${arguments.replaceAll("'", "''")}'"
            : '';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "Start-Process -FilePath '$escaped'$argPart",
        ]).timeout(const Duration(seconds: 5));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final args = <String>['-a', clean];
        if (arguments != null && arguments.trim().isNotEmpty) {
          args.addAll(['--args', arguments.trim()]);
        }
        final res = await Process.run(
          'open',
          args,
        ).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('sh', [
          '-c',
          'nohup "$clean" ${arguments ?? ''} >/dev/null 2>&1 &',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Opens a URL or URI using url_launcher or OS shell.
  Future<bool> openUrlOrUri(String rawUri) async {
    final trimmed = rawUri.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }
    if (!kIsWeb) {
      try {
        if (Platform.isWindows) {
          final res = await Process.run('cmd', ['/c', 'start', '', trimmed]);
          return res.exitCode == 0;
        } else if (Platform.isMacOS) {
          final res = await Process.run('open', [trimmed]);
          return res.exitCode == 0;
        } else if (Platform.isLinux) {
          final res = await Process.run('xdg-open', [trimmed]);
          return res.exitCode == 0;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Lists running applications and processes with memory footprint.
  Future<List<Map<String, dynamic>>> listRunningApps() async {
    final windows = await listOpenWindows();
    if (windows.isNotEmpty) {
      return windows.map((w) => w.toJson()).toList();
    }
    return const [];
  }

  /// Captures the primary desktop screen to a PNG file and returns its path.
  Future<String?> captureScreenshot() async {
    if (kIsWeb) return null;
    try {
      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'desktop_screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      if (Platform.isWindows) {
        final escaped = outPath.replaceAll("'", "''");
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$bmp = New-Object System.Drawing.Bitmap \$bounds.Width, \$bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bmp)
\$graphics.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
\$bmp.Save('$escaped', [System.Drawing.Imaging.ImageFormat]::Png)
\$graphics.Dispose()
\$bmp.Dispose()
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 6));
        if (res.exitCode == 0 && await File(outPath).exists()) {
          return outPath;
        }
      } else if (Platform.isMacOS) {
        final res = await Process.run('screencapture', [
          '-x',
          outPath,
        ]).timeout(const Duration(seconds: 5));
        if (res.exitCode == 0 && await File(outPath).exists()) {
          return outPath;
        }
      } else if (Platform.isLinux) {
        for (final cmd in [
          ['gnome-screenshot', '-f', outPath],
          ['scrot', outPath],
          ['import', '-window', 'root', outPath],
        ]) {
          try {
            final res = await Process.run(
              cmd.first,
              cmd.sublist(1),
            ).timeout(const Duration(seconds: 4));
            if (res.exitCode == 0 && await File(outPath).exists()) {
              return outPath;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// Moves the mouse cursor to (x, y).
  Future<bool> mouseMove(int x, int y) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdotool', [
          'mousemove',
          '$x',
          '$y',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('cliclick', [
          'm:$x,$y',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Moves the cursor to (x, y) and performs a mouse click.
  Future<bool> mouseClick({
    required int x,
    required int y,
    String button = 'left',
    bool doubleClick = false,
  }) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final isRight = button.toLowerCase() == 'right';
        final downFlag = isRight ? 0x0008 : 0x0002;
        final upFlag = isRight ? 0x0010 : 0x0004;
        final script =
            '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMouse {
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);
}
"@ -ErrorAction SilentlyContinue
[void][WinMouse]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 30
[WinMouse]::mouse_event($downFlag, 0, 0, 0, 0)
[WinMouse]::mouse_event($upFlag, 0, 0, 0, 0)
${doubleClick ? 'Start-Sleep -Milliseconds 60; [WinMouse]::mouse_event($downFlag, 0, 0, 0, 0); [WinMouse]::mouse_event($upFlag, 0, 0, 0, 0)' : ''}
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final btn = button.toLowerCase() == 'right' ? '3' : '1';
        final args = <String>[
          'mousemove',
          '$x',
          '$y',
          'click',
          if (doubleClick) ...['--repeat', '2'],
          btn,
        ];
        final res = await Process.run(
          'xdotool',
          args,
        ).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final cmd = button.toLowerCase() == 'right'
            ? 'rc:$x,$y'
            : (doubleClick ? 'dc:$x,$y' : 'c:$x,$y');
        final res = await Process.run('cliclick', [
          cmd,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Scrolls the mouse wheel up or down.
  Future<bool> mouseScroll({String direction = 'down', int clicks = 5}) async {
    if (kIsWeb) return false;
    final isUp = direction == 'up' || direction == 'backward';
    final delta = (isUp ? 120 : -120) * clicks.clamp(1, 20);
    try {
      if (Platform.isWindows) {
        final script =
            '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinScroll {
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, int dwExtraInfo);
}
"@ -ErrorAction SilentlyContinue
[WinScroll]::mouse_event(0x0800, 0, 0, $delta, 0)
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final btn = isUp ? '4' : '5';
        final res = await Process.run('xdotool', [
          'click',
          '--repeat',
          '${clicks.clamp(1, 20)}',
          btn,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Types text into the active window.
  Future<bool> typeText(String text) async {
    if (kIsWeb || text.isEmpty) return false;
    try {
      if (Platform.isWindows) {
        // Escape special SendKeys characters: + ^ % ~ ( ) { } [ ]
        final sendKeysEscaped = text.replaceAllMapped(
          RegExp(r'([+\^%~(){}\[\]])'),
          (m) => '{${m.group(1)}}',
        );
        final psEscaped = sendKeysEscaped.replaceAll("'", "''");
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('$psEscaped')
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final escaped = text.replaceAll('"', '\\"');
        final res = await Process.run('osascript', [
          '-e',
          'tell application "System Events" to keystroke "$escaped"',
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdotool', [
          'type',
          '--clearmodifiers',
          text,
        ]).timeout(const Duration(seconds: 4));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Sends a keyboard shortcut such as "ctrl+c", "alt+tab", "enter", "escape".
  Future<bool> sendHotkey(String rawKeys) async {
    final clean = rawKeys.trim().toLowerCase();
    if (clean.isEmpty || kIsWeb) return false;

    try {
      if (Platform.isWindows) {
        final sendKeySeq = _mapToWindowsSendKeys(clean);
        final escaped = sendKeySeq.replaceAll("'", "''");
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('$escaped')
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final xdoKey = clean
            .replaceAll('ctrl+', 'ctrl+')
            .replaceAll(' enter', 'Return')
            .replaceAll('esc', 'Escape');
        final res = await Process.run('xdotool', [
          'key',
          xdoKey,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        if (clean == 'enter' || clean == 'return') {
          final res = await Process.run('osascript', [
            '-e',
            'tell application "System Events" to key code 36',
          ]);
          return res.exitCode == 0;
        } else if (clean == 'escape' || clean == 'esc') {
          final res = await Process.run('osascript', [
            '-e',
            'tell application "System Events" to key code 53',
          ]);
          return res.exitCode == 0;
        }
      }
    } catch (_) {}
    return false;
  }

  String _mapToWindowsSendKeys(String combo) {
    final parts = combo.split('+').map((e) => e.trim()).toList();
    final buffer = StringBuffer();
    for (final p in parts) {
      switch (p) {
        case 'ctrl':
        case 'control':
          buffer.write('^');
          break;
        case 'alt':
          buffer.write('%');
          break;
        case 'shift':
          buffer.write('+');
          break;
        case 'enter':
        case 'return':
          buffer.write('{ENTER}');
          break;
        case 'esc':
        case 'escape':
          buffer.write('{ESC}');
          break;
        case 'tab':
          buffer.write('{TAB}');
          break;
        case 'backspace':
          buffer.write('{BS}');
          break;
        case 'delete':
        case 'del':
          buffer.write('{DEL}');
          break;
        case 'up':
          buffer.write('{UP}');
          break;
        case 'down':
          buffer.write('{DOWN}');
          break;
        case 'left':
          buffer.write('{LEFT}');
          break;
        case 'right':
          buffer.write('{RIGHT}');
          break;
        case 'space':
          buffer.write(' ');
          break;
        default:
          buffer.write(p);
      }
    }
    return buffer.toString();
  }

  /// Controls volume or media playback.
  Future<bool> controlMediaOrVolume(String command) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        // Windows virtual key codes:
        // 173 = Mute, 174 = Volume Down, 175 = Volume Up, 179 = Play/Pause, 176 = Next, 177 = Prev
        final keyChar = switch (command) {
          'mute' || 'unmute' => 173,
          'volume_down' || 'down' => 174,
          'volume_up' || 'up' => 175,
          'play_pause' || 'play' || 'pause' => 179,
          'next' || 'next_track' => 176,
          'prev' || 'prev_track' || 'previous' => 177,
          _ => 173,
        };
        final script =
            '''
\$wsh = New-Object -ComObject WScript.Shell
\$wsh.SendKeys([char]$keyChar)
''';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final script = switch (command) {
          'mute' => 'set volume with output muted',
          'unmute' => 'set volume without output muted',
          'volume_up' || 'up' =>
            'set volume output volume ((output volume of (get volume settings)) + 10)',
          'volume_down' || 'down' =>
            'set volume output volume ((output volume of (get volume settings)) - 10)',
          _ => 'set volume with output muted',
        };
        final res = await Process.run('osascript', [
          '-e',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final arg = switch (command) {
          'mute' || 'unmute' => 'toggle',
          'volume_up' || 'up' => '10%+',
          'volume_down' || 'down' => '10%-',
          _ => 'toggle',
        };
        final res = await Process.run('amixer', [
          '-D',
          'pulse',
          'sset',
          'Master',
          arg,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Locks the desktop screen.
  Future<bool> lockScreen() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final res = await Process.run('rundll32.exe', [
          'user32.dll,LockWorkStation',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('pmset', [
          'displaysleepnow',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('loginctl', [
          'lock-session',
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }
}
