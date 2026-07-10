import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义窗口标题栏组件
/// 提供最小化、最大化/还原、关闭按钮功能
class CustomTitleBar extends StatefulWidget {
  final String title;
  final Color? backgroundColor;
  final bool showMaximizeButton;

  const CustomTitleBar({
    super.key,
    this.title = 'Student',
    this.backgroundColor,
    this.showMaximizeButton = true,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

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
    final isMaximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
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
            _WindowButton(
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
              tooltip: '最小化',
            ),
            if (widget.showMaximizeButton)
              _WindowButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                onPressed: () async {
                  if (_isMaximized) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                tooltip: _isMaximized ? '还原' : '最大化',
              ),
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
