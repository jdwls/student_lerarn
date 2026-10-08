import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../services/window_mode_service.dart';

/// 自定义窗口标题栏组件
/// 提供最小化、最大化/还原、全屏/退出全屏、关闭按钮功能（各按钮均可通过参数隐藏）
class CustomTitleBar extends StatefulWidget {
  final String title;
  final Color? backgroundColor;

  /// 是否显示最大化/还原按钮
  final bool showMaximizeButton;

  /// 是否显示最小化按钮
  final bool showMinimizeButton;

  /// 是否显示关闭按钮
  final bool showCloseButton;

  /// 是否显示"全屏/退出全屏"按钮（答题页等需要用户自行切换全屏时开启）
  final bool showFullScreenButton;

  const CustomTitleBar({
    super.key,
    this.title = 'Student',
    this.backgroundColor,
    this.showMaximizeButton = true,
    this.showMinimizeButton = true,
    this.showCloseButton = true,
    this.showFullScreenButton = false,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    bool isMaximized = false;
    bool isFullScreen = false;
    try {
      isMaximized = await windowManager.isMaximized();
    } catch (_) {}
    try {
      isFullScreen = await windowManager.isFullScreen();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
        _isFullScreen = isFullScreen;
      });
    }
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullScreen = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullScreen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      onDoubleTap: widget.showMaximizeButton
          ? () async {
              // 全屏状态下优先退出全屏，否则"最大化"按钮会失效
              if (_isFullScreen) {
                await WindowModeService.toggleFullScreen();
                return;
              }
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }
          : null,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? const Color(0xFFF8FAFF),
          border: const Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            // 应用图标和标题
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.menu_book,
                size: 14,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const Spacer(),
            // 窗口控制按钮
            if (widget.showMinimizeButton)
            _WindowButton(
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
              tooltip: '最小化',
            ),
            if (widget.showFullScreenButton)
              _WindowButton(
                icon: _isFullScreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                onPressed: () async {
                  final isFullScreen =
                      await WindowModeService.toggleFullScreen();
                  if (mounted) {
                    setState(() {
                      _isFullScreen = isFullScreen;
                    });
                  }
                },
                tooltip: _isFullScreen ? '退出全屏' : '全屏',
              ),
            if (widget.showMaximizeButton)
              _WindowButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                onPressed: () async {
                  // 全屏状态下优先退出全屏，否则"最大化/还原"按钮会失效
                  if (_isFullScreen) {
                    await WindowModeService.toggleFullScreen();
                    return;
                  }
                  if (_isMaximized) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                tooltip: _isFullScreen
                    ? '退出全屏'
                    : (_isMaximized ? '还原' : '最大化'),
              ),
            if (widget.showCloseButton)
            _WindowButton(
              icon: Icons.close,
              onPressed: () => windowManager.close(),
              tooltip: '关闭',
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个窗口控制按钮
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 36,
            color: _isHovered
                ? (widget.isClose
                    ? const Color(0xFFE81123)
                    : const Color(0xFFE2E8F0))
                : Colors.transparent,
            child: Center(
              child: Icon(
                widget.icon,
                size: 16,
                color: _isHovered && widget.isClose
                    ? Colors.white
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
