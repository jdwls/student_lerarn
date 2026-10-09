import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口模式服务
///
/// 统一管理「进入/退出答题」时的窗口状态，避免各页面各自调用
/// setSize / setFullScreen / setMinimumSize 互相覆盖
/// （典型问题：退出答题后被强制缩回 1280x720，用户原来的最大化状态丢失）。
///
/// 用法：
/// ```dart
/// await WindowModeService.capturePreQuizState(); // 进入答题前记录
/// await WindowModeService.enterQuizFullScreen(); // 进入全屏
/// await WindowModeService.exitQuizFullScreen();  // 退出并恢复（幂等）
/// ```
class WindowModeService {
  WindowModeService._();

  /// 答题模式下的最小尺寸
  /// 放宽限制，避免"最小尺寸 > 屏幕工作区"导致最大化/全屏异常
  static const Size quizMinSize = Size(640, 480);

  /// 应用默认最小尺寸（与学生端 main.dart 的 WindowOptions 保持一致）
  static const Size appMinSize = Size(1280, 720);

  static const Duration _timeout = Duration(seconds: 3);

  /// 是否处于答题（全屏）模式
  static bool _active = false;

  /// 进入答题前是否为最大化
  static bool _wasMaximized = false;

  /// 进入答题前是否已是全屏
  static bool _wasFullScreen = false;

  /// 进入答题前的窗口尺寸
  static Size? _normalSize;

  static bool get isQuizMode => _active;

  /// 记录进入答题前的窗口状态（必须在进入全屏之前调用）
  static Future<void> capturePreQuizState() async {
    try {
      _wasMaximized = await windowManager.isMaximized();
    } catch (_) {
      _wasMaximized = false;
    }
    try {
      _wasFullScreen = await windowManager.isFullScreen();
    } catch (_) {
      _wasFullScreen = false;
    }
    try {
      _normalSize = await windowManager.getSize();
    } catch (_) {
      _normalSize = null;
    }
  }

  /// 进入答题全屏
  static Future<void> enterQuizFullScreen() async {
    _active = true;
    try {
      // 先放宽最小尺寸，避免与全屏/最大化互相冲突
      await windowManager
          .setMinimumSize(quizMinSize)
          .timeout(_timeout, onTimeout: () {});

      // 已经是全屏就不重复设置，避免与最大化状态打架
      if (await windowManager.isFullScreen()) return;

      await windowManager.setFullScreen(true).timeout(_timeout);
    } catch (e) {
      debugPrint('进入答题全屏失败，回退为最大化窗口: $e');
      try {
        await windowManager.setFullScreen(false).timeout(_timeout);
      } catch (_) {}
      try {
        await windowManager.restore().timeout(_timeout);
      } catch (_) {}
      try {
        await windowManager.maximize().timeout(_timeout);
        await windowManager.show().timeout(_timeout);
        await windowManager.focus().timeout(_timeout);
      } catch (e2) {
        debugPrint('窗口最大化或激活失败: $e2');
      }
    }
  }

  /// 退出答题并恢复进入前的窗口状态
  /// 幂等：非答题模式下调用不做任何事（首页/结果页可安全重复调用）
  static Future<void> exitQuizFullScreen() async {
    if (!_active) return;
    _active = false;

    // 1. 退出全屏
    try {
      await windowManager
          .setAlwaysOnTop(false)
          .timeout(_timeout, onTimeout: () {});
      await windowManager
          .setFullScreen(false)
          .timeout(_timeout, onTimeout: () {});
    } catch (e) {
      debugPrint('退出全屏失败: $e');
    }

    // 2. 恢复窗口外观（与学生端 main.dart 初始化一致）
    try {
      await windowManager
          .setBackgroundColor(Colors.transparent)
          .timeout(_timeout, onTimeout: () {});
      await windowManager
          .setTitleBarStyle(TitleBarStyle.hidden)
          .timeout(_timeout, onTimeout: () {});
      await windowManager
          .setAlignment(Alignment.center)
          .timeout(_timeout, onTimeout: () {});
      await windowManager
          .setMinimumSize(appMinSize)
          .timeout(_timeout, onTimeout: () {});
    } catch (e) {
      debugPrint('恢复窗口外观失败: $e');
    }

    // 3. 恢复进入前的尺寸/最大化状态（不再一律缩回 1280x720）
    try {
      if (_wasMaximized) {
        await windowManager.maximize().timeout(_timeout, onTimeout: () {});
      } else if (!_wasFullScreen && _normalSize != null) {
        await windowManager
            .setSize(_normalSize!)
            .timeout(_timeout, onTimeout: () {});
        await windowManager.center().timeout(_timeout, onTimeout: () {});
      }
    } catch (e) {
      debugPrint('恢复窗口状态失败: $e');
    }
  }

  /// 切换全屏（供标题栏"全屏/退出全屏"按钮使用）
  /// 返回切换后的全屏状态
  static Future<bool> toggleFullScreen() async {
    try {
      final isFull = await windowManager.isFullScreen();
      await windowManager
          .setFullScreen(!isFull)
          .timeout(_timeout, onTimeout: () {});
      return !isFull;
    } catch (e) {
      debugPrint('切换全屏失败: $e');
      return false;
    }
  }
}
