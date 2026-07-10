import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/socket_service.dart';

/// 小测专用打字页面
class QuizTypingPage extends StatefulWidget {
  final String referenceText;
  final String typingType;
  final int timeLimit;
  final int questionScore;
  final int questionNumber;

  const QuizTypingPage({
    super.key,
    required this.referenceText,
    required this.typingType,
    required this.timeLimit,
    required this.questionScore,
    required this.questionNumber,
  });

  @override
  State<QuizTypingPage> createState() => _QuizTypingPageState();
}

class _QuizTypingPageState extends State<QuizTypingPage> {
  static const double _baseFontSizeChinese = 26.0;
  static const double _baseFontSize = 23.4;
  static const String _fontFamilyChinese = 'NSimSun';
  static const String _fontFamilyEnglish = 'Courier New';
  late final String _fontFamily;
  double _fontSize = _baseFontSize;
  double _inputFontSize = _baseFontSize - 2;
  double _lastLayoutWidth = 0;

  static const int _targetSpeed = 100;
  static const int _totalScore = 100;
  static const double _pointsPerError = 0.2;

  bool _isStarted = false;
  bool _isFinished = false;
  bool _isPaused = false;
  Timer? _timer;
  final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _correctCharsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalTypedNotifier = ValueNotifier<int>(0);
  double _score = 0;

  int get _remainingSeconds => _remainingSecondsNotifier.value;
  set _remainingSeconds(int v) => _remainingSecondsNotifier.value = v;
  int get _elapsedSeconds => _elapsedSecondsNotifier.value;
  set _elapsedSeconds(int v) => _elapsedSecondsNotifier.value = v;
  int get _correctChars => _correctCharsNotifier.value;
  set _correctChars(int v) => _correctCharsNotifier.value = v;
  int get _totalTyped => _totalTypedNotifier.value;
  set _totalTyped(int v) => _totalTypedNotifier.value = v;

  // 多行输入
  int _activeLine = 0;
  final List<String> _lineInputs = [];
  final List<TextEditingController> _lineControllers = [];
  final List<FocusNode> _lineFocusNodes = [];
  List<String> _lines = [];

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeLimit * 60;
    if (widget.typingType == 'english') {
      _fontSize = _baseFontSize;
      _inputFontSize = _baseFontSize - 1;
      _fontFamily = _fontFamilyEnglish;
    } else {
      _fontSize = _baseFontSizeChinese;
      _inputFontSize = _baseFontSizeChinese - 0.5;
      _fontFamily = _fontFamilyChinese;
    }
    try {
      SocketService.instance.updateStatus('typing');
    } catch (e) {
      debugPrint('更新Socket状态为typing失败: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeLineControllers();
    _remainingSecondsNotifier.dispose();
    _elapsedSecondsNotifier.dispose();
    _correctCharsNotifier.dispose();
    _totalTypedNotifier.dispose();
    try {
      SocketService.instance.updateStatus('online');
    } catch (e) {
      debugPrint('恢复Socket状态失败: $e');
    }
    super.dispose();
  }

  void _disposeLineControllers() {
    for (final c in _lineControllers) {
      c.dispose();
    }
    for (final f in _lineFocusNodes) {
      f.dispose();
    }
  }

  /// 创建带 backspace 回退功能和禁止复制粘贴的 FocusNode
  FocusNode _createLineFocusNode(int lineIdx) {
    return FocusNode(
      onKeyEvent: (node, event) {
        // 禁止复制粘贴快捷键
        if (event is KeyDownEvent) {
          final pressedKeys = RawKeyboard.instance.keysPressed;
          final isCtrl = pressedKeys.contains(LogicalKeyboardKey.control) ||
              pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
              pressedKeys.contains(LogicalKeyboardKey.controlRight);
          final isShift = pressedKeys.contains(LogicalKeyboardKey.shift) ||
              pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
              pressedKeys.contains(LogicalKeyboardKey.shiftRight);
          if (isCtrl &&
              (event.logicalKey == LogicalKeyboardKey.keyC ||
                  event.logicalKey == LogicalKeyboardKey.keyV ||
                  event.logicalKey == LogicalKeyboardKey.keyA ||
                  event.logicalKey == LogicalKeyboardKey.keyX)) {
            return KeyEventResult.handled;
          }
          if (isShift && event.logicalKey == LogicalKeyboardKey.insert) {
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          final controller = _lineControllers[lineIdx];
          if (controller.selection.baseOffset == 0 && lineIdx > 0) {
            setState(() {
              _activeLine = lineIdx - 1;
            });
            _lineFocusNodes[_activeLine].requestFocus();
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                final c = _lineControllers[_activeLine];
                c.selection = TextSelection.collapsed(
                  offset: c.text.length,
                );
              }
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
  }

  /// 根据窗口宽度动态计算字体大小
  double _calcFontSize(double containerWidth) {
    const baseWidth = 1180.0;
    final scale = (containerWidth / baseWidth).clamp(0.8, 1.5);
    return (widget.typingType == 'english'
            ? _baseFontSize
            : _baseFontSizeChinese) *
        scale;
  }

  /// 使用等宽字体固定字符宽分行（支持窗口大小变化时重新分行）
  void _splitLines(double width) {
    if (widget.referenceText.isEmpty) return;

    // 如果宽度没有变化且已有分行，跳过重新计算
    if (_lines.isNotEmpty && (width - _lastLayoutWidth).abs() < 1.0) return;

    _lastLayoutWidth = width;

    // 动态计算字体大小
    _fontSize = _calcFontSize(width);
    _inputFontSize = _fontSize - 1; // 输入框字体比原文小2

    final availableWidth = width - 36; // 20 padding + 16 container padding(8+8)
    if (availableWidth <= 0) return;

    // 用 TextPainter 测量等宽字体单字符宽度
    final style =
        TextStyle(fontSize: _fontSize, height: 1.6, fontFamily: _fontFamily);
    final tp = TextPainter(
      text: TextSpan(text: 'W', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = tp.width;
    tp.dispose();
    if (charWidth <= 0) return;

    final charsPerLine = (availableWidth / charWidth).floor();
    if (charsPerLine <= 0) return;

    // 保存旧的行输入数据，用于窗口大小变化时恢复已输入内容
    final oldLineInputs = List<String>.from(_lineInputs);
    final oldActiveLine = _activeLine;

    _disposeLineControllers();
    _lineInputs.clear();
    _lineControllers.clear();
    _lineFocusNodes.clear();

    _lines = [];
    for (int i = 0; i < widget.referenceText.length; i += charsPerLine) {
      final end = (i + charsPerLine < widget.referenceText.length)
          ? i + charsPerLine
          : widget.referenceText.length;
      _lines.add(widget.referenceText.substring(i, end));
    }

    // 恢复已输入的内容（尽可能匹配旧行到新行）
    for (int i = 0; i < _lines.length; i++) {
      if (i < oldLineInputs.length) {
        final input = oldLineInputs[i];
        _lineInputs.add(input.length <= _lines[i].length
            ? input
            : input.substring(0, _lines[i].length));
      } else {
        _lineInputs.add('');
      }
      _lineControllers.add(TextEditingController(text: _lineInputs[i]));
      _lineFocusNodes.add(_createLineFocusNode(i));
    }

    // 恢复活动行
    _activeLine =
        oldActiveLine < _lines.length ? oldActiveLine : _lines.length - 1;
    if (_activeLine < 0) _activeLine = 0;

    // 重新计算已打字数和正确数
    _totalTyped = 0;
    _correctChars = 0;
    for (int l = 0; l < _lineInputs.length; l++) {
      final input = _lineInputs[l];
      final lineText = _lines[l];
      _totalTyped += input.length;
      for (int i = 0; i < input.length && i < lineText.length; i++) {
        if (input[i] == lineText[i]) _correctChars++;
      }
    }
  }

  void _startTyping() {
    if (_isStarted) return;
    try {
      SocketService.instance.updateStatus('typing');
    } catch (e) {
      debugPrint('更新Socket状态为typing失败: $e');
    }
    setState(() {
      _isStarted = true;
      _isFinished = false;
      _isPaused = false;
    });
    _remainingSeconds = widget.timeLimit * 60;
    _elapsedSeconds = 0;
    _correctChars = 0;
    _totalTyped = 0;
    _score = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lineFocusNodes.isNotEmpty) {
        _lineFocusNodes[0].requestFocus();
      }
    });

    // 直接更新 ValueNotifier，不调用 setState，避免重建 TextField 导致光标位置丢失
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _remainingSeconds--;
        _elapsedSeconds++;
        if (_remainingSeconds <= 0) _finishTyping();
      }
    });
  }

  void _pauseTyping() {
    _timer?.cancel();
    setState(() {
      _isPaused = true;
    });
  }

  void _resumeTyping() {
    if (!_isPaused) return;
    setState(() {
      _isPaused = false;
    });
    // 直接更新 ValueNotifier，不调用 setState
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _remainingSeconds--;
        _elapsedSeconds++;
        if (_remainingSeconds <= 0) _finishTyping();
      }
    });
    // 恢复焦点到当前活动行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lineFocusNodes.isNotEmpty && _activeLine < _lineFocusNodes.length) {
        _lineFocusNodes[_activeLine].requestFocus();
      }
    });
  }

  void _onLineChanged(int lineIdx, String value) {
    if (!_isStarted || _isFinished || _isPaused) return;

    // 如果文本没有实际变化，不触发 setState（避免光标位置丢失）
    if (_lineInputs[lineIdx] == value) return;

    _lineInputs[lineIdx] = value;
    _recalcStats();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _lineControllers[lineIdx];
      final stillComposing = c.value.composing != TextRange.empty;
      if (stillComposing) return;

      final lineLength = _lines[lineIdx].length;
      if (c.text.length > lineLength) {
        final currentOffset = c.selection.baseOffset.clamp(0, lineLength);
        final truncatedText = c.text.substring(0, lineLength);
        c.text = truncatedText;
        c.selection = TextSelection.collapsed(offset: currentOffset);
        _lineInputs[lineIdx] = truncatedText;
        _recalcStats();
        _checkAndAdvanceLine(lineIdx, truncatedText);
        return;
      }

      _checkAndAdvanceLine(lineIdx, c.text);
    });
  }

  /// 重新计算打字统计（正确数、总字数），并刷新UI
  void _recalcStats() {
    int totalTyped = 0;
    int correctChars = 0;
    for (int l = 0; l < _lineInputs.length; l++) {
      final input = _lineInputs[l];
      final lineText = _lines[l];
      totalTyped += input.length;
      for (int i = 0; i < input.length && i < lineText.length; i++) {
        if (input[i] == lineText[i]) correctChars++;
      }
    }
    // 直接更新 ValueNotifier，不调用 setState
    _totalTyped = totalTyped;
    _correctChars = correctChars;
  }

  /// 检查当前行是否输入满且光标在末尾，如果是则切换到下一行
  void _checkAndAdvanceLine(int lineIdx, String currentVal) {
    final lineText = _lines[lineIdx];
    final controller = _lineControllers[lineIdx];
    final cursorAtEnd = controller.selection.baseOffset >= currentVal.length;
    if (currentVal.length >= lineText.length && cursorAtEnd) {
      // 找到第一个未输入满的行
      int? nextIncompleteLine;
      for (int l = 0; l < _lines.length; l++) {
        if (_lineInputs[l].length < _lines[l].length) {
          nextIncompleteLine = l;
          break;
        }
      }
      if (nextIncompleteLine != null) {
        final targetLine = nextIncompleteLine;
        setState(() {
          _activeLine = targetLine;
        });
        _lineFocusNodes[targetLine].requestFocus();
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            final ctrl = _lineControllers[targetLine];
            ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
          }
        });
      } else {
        _finishTyping();
      }
    }
  }

  Future<void> _finishTyping() async {
    _timer?.cancel();
    try {
      SocketService.instance.updateStatus('online');
    } catch (e) {
      debugPrint('恢复Socket状态失败: $e');
    }
    int errorCount = _totalTyped - _correctChars;
    final minutes = _elapsedSeconds > 0 ? _elapsedSeconds / 60.0 : 1.0;
    final speed = _correctChars / minutes;
    double baseScore =
        (speed / _targetSpeed * _totalScore).clamp(0, _totalScore).toDouble();
    _score = (baseScore - errorCount * _pointsPerError)
        .clamp(0, _totalScore)
        .toDouble();

    final accuracy =
        _totalTyped > 0 ? (_correctChars / _totalTyped * 100).round() : 0;
    final speedRounded = _elapsedSeconds > 0
        ? (_correctChars / (_elapsedSeconds / 60.0)).round()
        : 0;

    setState(() {
      _isFinished = true;
    });

    // 返回小测结果给调用页面
    if (mounted) {
      Navigator.pop(context, {
        'score': _score.round(),
        'accuracy': accuracy,
        'speed': speedRounded,
        'correctChars': _correctChars,
        'totalTyped': _totalTyped,
        'errorCount': errorCount,
        'elapsedSeconds': _elapsedSeconds,
      });
    }
  }

  void _resetPractice() {
    _timer?.cancel();
    _disposeLineControllers();
    _lineInputs.clear();
    _lineControllers.clear();
    _lineFocusNodes.clear();
    _lines.clear();
    _lastLayoutWidth = 0;

    setState(() {
      _isStarted = false;
      _isFinished = false;
      _isPaused = false;
      _activeLine = 0;
    });
    _remainingSeconds = widget.timeLimit * 60;
    _elapsedSeconds = 0;
    _correctChars = 0;
    _totalTyped = 0;
    _score = 0;
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD6DBE8)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (_isStarted && !_isFinished) {
                      _pauseTyping();
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认退出'),
                          content: const Text('练习尚未完成，是否退出？退出后进度将丢失。'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _resumeTyping();
                              },
                              child: const Text('继续练习'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.pop(context);
                              },
                              child: const Text('退出'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text('第${widget.questionNumber}题 - 打字',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: _remainingSecondsNotifier,
                  builder: (context, remaining, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: remaining <= 60 && _isStarted
                            ? Colors.red.withAlpha(26)
                            : AppTheme.primaryColor.withAlpha(26),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(_formatTime(remaining),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: remaining <= 60 && _isStarted
                                  ? Colors.red
                                  : AppTheme.primaryColor,
                              fontSize: 16)),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<int>(
                  valueListenable: _totalTypedNotifier,
                  builder: (context, totalTyped, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _correctCharsNotifier,
                      builder: (context, correctChars, _) {
                        final errorCount = totalTyped - correctChars;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('已打字数: $totalTyped',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('正确: $correctChars',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('错误: $errorCount',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                if (!_isStarted)
                  ElevatedButton.icon(
                    onPressed: _startTyping,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('开始练习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                else if (_isFinished)
                  ElevatedButton.icon(
                    onPressed: _resetPractice,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('再来一次'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                else if (_isPaused)
                  ElevatedButton.icon(
                    onPressed: _resumeTyping,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续练习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                else if (_isStarted)
                  ElevatedButton.icon(
                    onPressed: _pauseTyping,
                    icon: const Icon(Icons.pause, size: 18),
                    label: const Text('暂停练习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ),

          // 文本区域 + 输入框
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(builder: (context, constraints) {
                _splitLines(constraints.maxWidth - 48);
                if (_lines.isEmpty) return const SizedBox.shrink();

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFD6DBE8)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(_lines.length, (lineIdx) {
                        final line = _lines[lineIdx];
                        final isActive = _activeLine == lineIdx;
                        final isDone = _activeLine > lineIdx;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 原文行（实时变色）
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    isActive ? Colors.blue.withAlpha(13) : null,
                              ),
                              child: Builder(builder: (context) {
                                final input = isDone || isActive
                                    ? _lineInputs[lineIdx]
                                    : '';
                                List<InlineSpan> spans = [];
                                for (int i = 0; i < line.length; i++) {
                                  Color textColor;
                                  Color? bgColor;
                                  if (i < input.length) {
                                    final isCorrect = input[i] == line[i];
                                    textColor = Colors.black;
                                    bgColor = isCorrect
                                        ? Colors.green.withAlpha(102)
                                        : Colors.red.withAlpha(102);
                                  } else if (isActive && i == input.length) {
                                    textColor = AppTheme.primaryColor;
                                  } else {
                                    textColor = Colors.black;
                                  }
                                  spans.add(TextSpan(
                                      text: line[i],
                                      style: TextStyle(
                                          fontSize: _fontSize,
                                          color: textColor,
                                          backgroundColor: bgColor,
                                          fontWeight: FontWeight.bold,
                                          height: 1.6,
                                          fontFamily: _fontFamily)));
                                }
                                return RichText(
                                    text: TextSpan(children: spans));
                              }),
                            ),
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFFEEF5FF)
                                    : const Color(0xFFF8FAFC),
                                border: Border.all(
                                    color: isActive
                                        ? AppTheme.primaryColor.withAlpha(128)
                                        : const Color(0xFFD6DBE8)),
                              ),
                              child: SizedBox(
                                height: _inputFontSize * 1.6 + 12,
                                child: TextField(
                                  controller: _lineControllers[lineIdx],
                                  focusNode: _lineFocusNodes[lineIdx],
                                  enabled: _isStarted && !_isPaused,
                                  maxLines: 1,
                                  textInputAction: TextInputAction.none,
                                  style: TextStyle(
                                      fontSize: _inputFontSize,
                                      height: 1.6,
                                      fontFamily: _fontFamily,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: isActive
                                        ? 'Type the text above here...'
                                        : '',
                                    hintStyle:
                                        TextStyle(color: Colors.grey[400]),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(0),
                                      borderSide: BorderSide(
                                          color: const Color(0xFFD6DBE8)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(0),
                                      borderSide: BorderSide(
                                          color: const Color(0xFFD6DBE8)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(0),
                                      borderSide: BorderSide(
                                          color: const Color(0xFFD6DBE8)),
                                    ),
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onTap: () {
                                    if (_activeLine != lineIdx) {
                                      setState(() {
                                        _activeLine = lineIdx;
                                      });
                                    }
                                  },
                                  onChanged: (value) =>
                                      _onLineChanged(lineIdx, value),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        );
                      }),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
