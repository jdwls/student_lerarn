import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 获取真正的屏幕尺寸（安全方法，带 fallback）
Size _getRealScreenSize(BuildContext? context) {
  try {
    final displays = ui.PlatformDispatcher.instance.displays;
    if (displays.isNotEmpty) {
      final display = displays.first;
      final physicalSize = display.size;
      final devicePixelRatio = display.devicePixelRatio;
      final width = physicalSize.width / devicePixelRatio;
      final height = physicalSize.height / devicePixelRatio;
      // 检查是否为有效数值
      if (width > 0 && height > 0 && !width.isNaN && !height.isNaN) {
        return Size(width, height);
      }
    }
  } catch (e) {
    debugPrint('获取 PlatformDispatcher 屏幕尺寸失败: $e');
  }
  // Fallback: 使用 MediaQuery 或默认值
  if (context != null && context.mounted) {
    try {
      final mediaQuerySize = MediaQuery.maybeOf(context)?.size;
      if (mediaQuerySize != null &&
          mediaQuerySize.width > 0 &&
          mediaQuerySize.height > 0 &&
          !mediaQuerySize.width.isNaN &&
          !mediaQuerySize.height.isNaN) {
        return mediaQuerySize;
      }
    } catch (e) {
      debugPrint('获取 MediaQuery 屏幕尺寸失败: $e');
    }
  }
  // 最终 fallback：默认尺寸
  return const Size(1920, 1080);
}

/// 可拖动的浮动窗口组件（使用 Overlay 实现全屏拖拽）
class DraggableOverlayWindow extends StatefulWidget {
  final String title;
  final Widget child;
  final double width;
  final double height;
  final VoidCallback? onClose;
  final bool showCloseButton;
  final bool showMinimizeButton;
  final VoidCallback? onMinimize;

  const DraggableOverlayWindow({
    super.key,
    required this.title,
    required this.child,
    this.width = 800,
    this.height = 500,
    this.onClose,
    this.showCloseButton = true,
    this.showMinimizeButton = false,
    this.onMinimize,
  });

  @override
  State<DraggableOverlayWindow> createState() => _DraggableOverlayWindowState();
}

class _DraggableOverlayWindowState extends State<DraggableOverlayWindow> {
  Offset? _position; // 使用 nullable，表示未初始化
  bool _initialized = false;

  void _onPanUpdate(DragUpdateDetails details) {
    if (_position == null) return;
    setState(() {
      double newX = _position!.dx + details.delta.dx;
      double newY = _position!.dy + details.delta.dy;

      // 使用安全方法获取屏幕尺寸
      final screenSize = _getRealScreenSize(context);
      final screenWidth = screenSize.width;
      final screenHeight = screenSize.height;

      // 限制窗口在屏幕范围内
      newX = newX.clamp(0.0, screenWidth - widget.width);
      newY = newY.clamp(0.0, screenHeight - widget.height);

      _position = Offset(newX, newY);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用安全方法获取屏幕尺寸
    final screenSize = _getRealScreenSize(context);
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // 初始化位置到屏幕中央（只执行一次）
    if (!_initialized) {
      _position = Offset(
        (screenWidth - widget.width) / 2,
        (screenHeight - widget.height) / 2,
      );
      _initialized = true;
    }

    return Stack(
      children: [
        // 浮动窗口
        Positioned(
          left: _position?.dx ?? 0,
          top: _position?.dy ?? 0,
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            shadowColor: Colors.black.withAlpha(77),
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD6DBE8)),
              ),
              child: Column(
                children: [
                  // 标题栏（可拖动）
                  GestureDetector(
                    onPanUpdate: _onPanUpdate,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.computer,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.showCloseButton)
                            GestureDetector(
                              onTap: widget.onClose,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 内容区域
                  Expanded(
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 操作题浮动窗口内容（紧凑版，适配小窗口）
class OperationQuestionPanel extends StatefulWidget {
  final String questionText;
  final String? driveLetter;
  final List<Map<String, dynamic>> initialFiles;
  final List<Map<String, dynamic>> answers;
  final VoidCallback onComplete;
  final VoidCallback? onRefresh; // 新增：重新获取回调

  const OperationQuestionPanel({
    super.key,
    required this.questionText,
    this.driveLetter,
    required this.initialFiles,
    required this.answers,
    required this.onComplete,
    this.onRefresh,
  });

  @override
  State<OperationQuestionPanel> createState() => _OperationQuestionPanelState();
}

class _OperationQuestionPanelState extends State<OperationQuestionPanel> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          // 可滚动的内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 题目说明（字体放大30%）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.assignment,
                                size: 18, color: Colors.grey[700]),
                            const SizedBox(width: 6),
                            Text(
                              '题目说明',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.questionText,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              decoration: TextDecoration.none),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 固定在底部的按钮区域
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 重新获取按钮
                if (widget.onRefresh != null)
                  ElevatedButton.icon(
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('重新获取', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                if (widget.onRefresh != null) const SizedBox(width: 12),
                // 完成操作按钮
                ElevatedButton.icon(
                  onPressed: widget.onComplete,
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('完成操作', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
