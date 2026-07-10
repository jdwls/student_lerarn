part of 'quiz_page.dart';

/// 打字题状态类
class TypingQuestionState {
  final List<TextEditingController> lineControllers = [];
  final List<FocusNode> lineFocusNodes = [];
  final List<String> lineInputs = [];
  List<String> lines = [];
  int activeLine = 0;
  // 使用 ValueNotifier 避免每次 setState 重建整个 widget，防止 TextField 丢失焦点位置
  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> correctCharsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> totalTypedNotifier = ValueNotifier<int>(0);
  // 行变化通知器（避免因原文更新实时刷新，值本身无意义，仅用于通知）
  final ValueNotifier<int> lineInputsNotifier = ValueNotifier<int>(0);
  bool started = false;
  bool finished = false;
  bool paused = false;
  Timer? timer;
  bool autoPausedByRoute = false;

  // 便捷访问
  int get remainingSeconds => remainingSecondsNotifier.value;
  set remainingSeconds(int v) => remainingSecondsNotifier.value = v;
  int get correctChars => correctCharsNotifier.value;
  set correctChars(int v) => correctCharsNotifier.value = v;
  int get totalTyped => totalTypedNotifier.value;
  set totalTyped(int v) => totalTypedNotifier.value = v;

  void dispose() {
    timer?.cancel();
    remainingSecondsNotifier.dispose();
    correctCharsNotifier.dispose();
    totalTypedNotifier.dispose();
    lineInputsNotifier.dispose();
    for (final c in lineControllers) {
      c.dispose();
    }
    for (final f in lineFocusNodes) {
      f.dispose();
    }
  }
}

/// 打字题 mixin
mixin _TypingWidgetMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// 构建 - 内嵌打字界面
  Widget _buildTypingQuestion(Map<String, dynamic> question) {
    final answer =
        _quizState._answers[_quizState._currentQuestionIndex] as Map?;
    final bool isCompleted = answer != null;
    final typingType = question['typingType'] ?? 'chinese';
    final referenceText = question['questionText'] ?? '';
    final fontSize = typingType == 'english' ? 23.4 : 26.0;
    final fontFamily = typingType == 'english' ? 'Courier New' : 'NSimSun';
    final questionScore = question['score'] as int? ?? 5;

    // 题目切换时新的打字题
    if (_quizState._typingQuestionIndex != _quizState._currentQuestionIndex) {
      // 暂停旧题目的计时（通过状态类获取状态）
      if (_quizState._typingQuestionIndex >= 0) {
        final oldState =
            _quizState._getTypingState(_quizState._typingQuestionIndex);
        if (oldState.started && !oldState.finished && !oldState.paused) {
          oldState.timer?.cancel();
          oldState.paused = true;
          oldState.autoPausedByRoute = true; // 标记为因路由切换暂停
        }
      }
      // 新题目是否需要恢复（之前因路由切换暂停的）
      final newState =
          _quizState._getTypingState(_quizState._currentQuestionIndex);
      if (newState.autoPausedByRoute) {
        // 切换回来不自动恢复，只清理标志，等用户点"继续打字"按钮恢复
        newState.autoPausedByRoute = false;
        _quizState._typingQuestionIndex = _quizState._currentQuestionIndex;
        // 不调用 _resumeInlineTyping()，保持暂停状态
      } else if (!newState.started) {
        // 全新的打字题，初始化
        _initTypingState(referenceText, fontSize, fontFamily);
        _quizState._typingQuestionIndex = _quizState._currentQuestionIndex;
      } else {
        _quizState._typingQuestionIndex = _quizState._currentQuestionIndex;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 信息栏
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: typingType == 'chinese'
                    ? Colors.red.withAlpha(26)
                    : Colors.blue.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    typingType == 'chinese' ? Icons.language : Icons.translate,
                    size: 14,
                    color: typingType == 'chinese' ? Colors.red : Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    typingType == 'chinese' ? '中文打字' : '英文打字',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: typingType == 'chinese' ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('分值: $questionScore',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            ),
            const SizedBox(width: 8),
            // 计时器 - 使用 ValueListenableBuilder 避免重建输入框
            ValueListenableBuilder<int>(
              valueListenable: _quizState._ts.remainingSecondsNotifier,
              builder: (context, remainingSeconds, _) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: remainingSeconds <= 60 && _quizState._typingStarted
                        ? Colors.red.withAlpha(26)
                        : AppTheme.primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_quizState._formatTime(remainingSeconds),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: remainingSeconds <= 60 &&
                                  _quizState._typingStarted
                              ? Colors.red
                              : AppTheme.primaryColor)),
                );
              },
            ),
            const SizedBox(width: 12),
            // 统计 - 使用 ValueListenableBuilder 避免重建输入框
            ValueListenableBuilder<int>(
              valueListenable: _quizState._ts.totalTypedNotifier,
              builder: (context, totalTyped, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: _quizState._ts.correctCharsNotifier,
                  builder: (context, correctChars, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('已打: $totalTyped',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        const SizedBox(width: 12),
                        Text('正确: $correctChars',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        const SizedBox(width: 12),
                        Text('错误: ${totalTyped - correctChars}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                      ],
                    );
                  },
                );
              },
            ),
            const Spacer(),
            if (!_quizState._typingStarted && !isCompleted)
              ElevatedButton.icon(
                onPressed: () => _startInlineTyping(fontSize, fontFamily),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('开始打字'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              )
            else if (_quizState._typingStarted &&
                !_quizState._typingFinished &&
                _quizState._typingPaused)
              Row(children: [
                ElevatedButton.icon(
                  onPressed: () => _resumeInlineTyping(),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('继续打字'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ])
            else if (_quizState._typingStarted && !_quizState._typingFinished)
              Row(children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _quizState
                        .setState(() => _quizState._typingFinished = true);
                    _saveInlineTypingResult(questionScore);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('完成打字'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ])
            else if (isCompleted)
              ElevatedButton.icon(
                onPressed: () {
                  _disposeTypingControllers();
                  _quizState.setState(() {
                    _quizState._typingStarted = false;
                    _quizState._typingFinished = false;
                    _quizState._typingCorrectChars = 0;
                    _quizState._typingTotalTyped = 0;
                    _quizState._typingLines.clear();
                    _quizState._typingLineInputs.clear();
                    _quizState._typingLineControllers.clear();
                    _quizState._typingLineFocusNodes.clear();
                    _quizState._answers
                        .remove(_quizState._currentQuestionIndex);
                    _quizState._typingQuestionIndex = -1;
                  });
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新打字'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 完成状态提示
        if (isCompleted) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withAlpha(77)),
            ),
            child: Text(
              '✅ 已完成打字  正确字符: ${answer['correctChars']}  总计: ${answer['totalTyped']}  耗时: ${_quizState._formatTime(answer['elapsedSeconds'] ?? 0)}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // 打字区域（初始不显示，LayoutBuilder 确定宽度渲染时再分行）
        if (_quizState._pendingTypingText != null ||
            _quizState._typingLines.isNotEmpty)
          _buildInlineTypingArea(fontSize, fontFamily, typingType),
      ],
    );
  }

  /// 初始化打字状态
  void _initTypingState(String text, double fontSize, String fontFamily) {
    _disposeTypingControllers();
    _quizState._typingLineInputs.clear();
    _quizState._typingLineControllers.clear();
    _quizState._typingLineFocusNodes.clear();
    _quizState._typingLines.clear();
    _quizState._typingActiveLine = 0;
    _quizState._typingCorrectChars = 0;
    _quizState._typingTotalTyped = 0;
    _quizState._typingStarted = false;
    _quizState._typingFinished = false;
    _quizState._lastTypingLayoutWidth = 0;

    // 分行延迟到 LayoutBuilder 获取精确宽度后再执行
    _quizState._pendingTypingText = text;
    _quizState._pendingTypingFontSize = fontSize;
    _quizState._pendingTypingFontFamily = fontFamily;
  }

  /// 使用精确可用宽度进行分行，由 LayoutBuilder 调用
  void _doSplitLines(double availableWidth) {
    if (_quizState._pendingTypingText == null ||
        _quizState._pendingTypingFontSize == null ||
        _quizState._pendingTypingFontFamily == null) return;
    // 如果已有且宽度没变，跳过重新分行
    if (_quizState._typingLines.isNotEmpty &&
        _quizState._lastTypingLayoutWidth != null &&
        (availableWidth - _quizState._lastTypingLayoutWidth! < 1.0 &&
            availableWidth - _quizState._lastTypingLayoutWidth! > -1.0)) return;
    _quizState._lastTypingLayoutWidth = availableWidth;

    final text = _quizState._pendingTypingText!;
    final fontSize = _quizState._pendingTypingFontSize!;
    final fontFamily = _quizState._pendingTypingFontFamily!;
    final style = TextStyle(
        fontSize: fontSize,
        height: 1.6,
        fontFamily: fontFamily,
        fontWeight: FontWeight.bold);

    _disposeTypingControllers();
    _quizState._typingLineInputs.clear();
    _quizState._typingLineControllers.clear();
    _quizState._typingLineFocusNodes.clear();
    _quizState._typingLines.clear();
    _quizState._typingActiveLine = 0;

    if (availableWidth > 0 && text.isNotEmpty) {
      int start = 0;
      while (start < text.length) {
        int lo = 1;
        int hi = text.length - start;
        int bestLen = 1;

        while (lo <= hi) {
          final mid = (lo + hi) ~/ 2;
          final candidate = text.substring(start, start + mid);
          final tp = TextPainter(
            text: TextSpan(text: candidate, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout(minWidth: 0, maxWidth: availableWidth);

          if (tp.didExceedMaxLines || tp.width > availableWidth) {
            hi = mid - 1;
          } else {
            bestLen = mid;
            lo = mid + 1;
          }
          tp.dispose();
        }

        _quizState._typingLines.add(text.substring(start, start + bestLen));
        start += bestLen;
      }
    } else if (text.isNotEmpty) {
      final charsPerLine = fontFamily == 'Courier New' ? 50 : 30;
      for (int i = 0; i < text.length; i += charsPerLine) {
        final end =
            (i + charsPerLine < text.length) ? i + charsPerLine : text.length;
        _quizState._typingLines.add(text.substring(i, end));
      }
    }
    for (int i = 0; i < _quizState._typingLines.length; i++) {
      _quizState._typingLineInputs.add('');
      _quizState._typingLineControllers.add(TextEditingController());
      _quizState._typingLineFocusNodes.add(FocusNode(
        onKeyEvent: (node, event) {
          // 阻止复制粘贴快捷键（仅桌面平台）
          try {
            if (Platform.isAndroid || Platform.isIOS) {
              return KeyEventResult.ignored; // 移动端不拦截
            }
          } catch (_) {
            // Web 平台 dart:io 不可用，不拦截
            return KeyEventResult.ignored;
          }
          final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
          final isCtrl = pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
              pressedKeys.contains(LogicalKeyboardKey.controlRight) ||
              pressedKeys.contains(LogicalKeyboardKey.control);
          final isShift = pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
              pressedKeys.contains(LogicalKeyboardKey.shiftRight) ||
              pressedKeys.contains(LogicalKeyboardKey.shift);
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
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            final controller = _quizState._typingLineControllers[i];
            if (controller.selection.baseOffset == 0 && i > 0) {
              _quizState.setState(() => _quizState._typingActiveLine = i - 1);
              _quizState._typingLineFocusNodes[_quizState._typingActiveLine]
                  .requestFocus();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (_quizState.mounted) {
                  final c = _quizState
                      ._typingLineControllers[_quizState._typingActiveLine];
                  c.selection = TextSelection.collapsed(offset: c.text.length);
                }
              });
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
      ));
    }
  }

  void _disposeTypingControllers() {
    for (final c in _quizState._typingLineControllers) {
      c.dispose();
    }
    for (final f in _quizState._typingLineFocusNodes) {
      f.dispose();
    }
  }

  void _startInlineTyping(double fontSize, String fontFamily) {
    final timeLimit = _quizState
            ._currentQuestions[_quizState._currentQuestionIndex]['timeLimit'] ??
        5;
    _quizState._typingRemainingSeconds = timeLimit * 60;
    _quizState.setState(() => _quizState._typingStarted = true);
    _quizState._typingPaused = false;
    _quizState._typingTimer?.cancel();
    // 直接更新 ValueNotifier，避免 setState 导致整体 TextField 失去焦点位置
    _quizState._typingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_quizState.mounted) return;
      _quizState._typingRemainingSeconds--;
      if (_quizState._typingRemainingSeconds <= 0) {
        _quizState._typingTimer?.cancel();
        if (!_quizState._typingFinished) {
          _quizState._typingFinished = true;
          _saveInlineTypingResult(
              _quizState._currentQuestions[_quizState._currentQuestionIndex]
                      ['score'] ??
                  10);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_quizState._typingLineFocusNodes.isNotEmpty) {
        _quizState._typingLineFocusNodes[0].requestFocus();
      }
    });
  }

  /// 暂停打字计时（切换到其他题目时调用）
  void _pauseInlineTyping() {
    if (!_quizState._typingStarted ||
        _quizState._typingFinished ||
        _quizState._typingPaused) return;
    _quizState._typingTimer?.cancel();
    _quizState._typingPaused = true;
    _quizState._ts.autoPausedByRoute = true;
    _quizState.setState(() {});
  }

  /// 恢复打字计时（切换回该题目时调用）
  void _resumeInlineTyping() {
    if (!_quizState._typingPaused) return;
    _quizState._typingPaused = false;
    _quizState._typingTimer?.cancel();
    // 直接更新 ValueNotifier，避免 setState
    _quizState._typingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_quizState.mounted) return;
      _quizState._typingRemainingSeconds--;
      if (_quizState._typingRemainingSeconds <= 0) {
        _quizState._typingTimer?.cancel();
        if (!_quizState._typingFinished) {
          _quizState._typingFinished = true;
          _saveInlineTypingResult(
              _quizState._currentQuestions[_quizState._currentQuestionIndex]
                      ['score'] ??
                  10);
        }
      }
    });
    // 恢复焦点到当前活动行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_quizState._typingLineFocusNodes.isNotEmpty &&
          _quizState._typingActiveLine <
              _quizState._typingLineFocusNodes.length) {
        _quizState._typingLineFocusNodes[_quizState._typingActiveLine]
            .requestFocus();
      }
    });
  }

  void _onInlineTypingChanged(int lineIdx, String value) {
    if (!_quizState._typingStarted || _quizState._typingFinished) return;
    _quizState._typingLineInputs[lineIdx] = value;
    // 直接更新 ValueNotifier，避免 setState 导致整体 TextField 失去焦点位置
    int totalTyped = 0;
    int correctChars = 0;
    for (int l = 0; l < _quizState._typingLineInputs.length; l++) {
      final input = _quizState._typingLineInputs[l];
      final lineText = _quizState._typingLines[l];
      totalTyped += input.length;
      for (int i = 0; i < input.length && i < lineText.length; i++) {
        if (input[i] == lineText[i]) correctChars++;
      }
    }
    _quizState._typingTotalTyped = totalTyped;
    _quizState._typingCorrectChars = correctChars;
    // 通知原文更新刷新
    _quizState._ts.lineInputsNotifier.value++;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_quizState.mounted) return;
      final c = _quizState._typingLineControllers[lineIdx];
      final stillComposing = c.value.composing != TextRange.empty;
      if (stillComposing) return;
      final lineLength = _quizState._typingLines[lineIdx].length;
      if (c.text.length > lineLength) {
        final truncatedText = c.text.substring(0, lineLength);
        c.text = truncatedText;
        c.selection = TextSelection.collapsed(offset: lineLength);
        _quizState._typingLineInputs[lineIdx] = truncatedText;
      }
      // 自动下一行
      if (_quizState._typingLineControllers[lineIdx].text.length >=
          lineLength) {
        int? nextLine;
        for (int l = 0; l < _quizState._typingLines.length; l++) {
          if (_quizState._typingLineInputs[l].length <
              _quizState._typingLines[l].length) {
            nextLine = l;
            break;
          }
        }
        if (nextLine != null) {
          _quizState.setState(() => _quizState._typingActiveLine = nextLine!);
          _quizState._typingLineFocusNodes[nextLine].requestFocus();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_quizState.mounted) {
              final ctrl = _quizState._typingLineControllers[nextLine!];
              ctrl.selection =
                  TextSelection.collapsed(offset: ctrl.text.length);
            }
          });
        } else {
          _quizState._typingFinished = true;
          _saveInlineTypingResult(
              _quizState._currentQuestions[_quizState._currentQuestionIndex]
                      ['score'] ??
                  10);
        }
      }
    });
  }

  void _saveInlineTypingResult(int questionScore) {
    _quizState._typingTimer?.cancel();
    // 得分由提交时计算，这里只保存当前状态
    final accuracy = _quizState._typingTotalTyped > 0
        ? _quizState._typingCorrectChars / _quizState._typingTotalTyped
        : 0.0;
    final score = (accuracy * questionScore).clamp(0, questionScore).toDouble();
    _quizState.setState(() {
      _quizState._answers[_quizState._currentQuestionIndex] = {
        'score': score.round(),
        'correctChars': _quizState._typingCorrectChars,
        'totalTyped': _quizState._typingTotalTyped,
        'elapsedSeconds':
            (_quizState._currentQuestions[_quizState._currentQuestionIndex]
                            ['timeLimit'] ??
                        5) *
                    60 -
                _quizState._typingRemainingSeconds,
      };
    });
  }

  /// 内嵌打字显示区
  Widget _buildInlineTypingArea(
      double fontSize, String fontFamily, String typingType) {
    final inputFontSize = fontSize - (typingType == 'english' ? 1 : 0.5);
    return LayoutBuilder(builder: (context, constraints) {
      // 获取 Container padding 内部的精确可用宽度
      // constraints.maxWidth 是 LayoutBuilder 提供的约束宽度
      // Container padding(32) + border(2) + 原有外层 padding(16) + border(2) = 52
      final textWidth = constraints.maxWidth - 52;
      if (textWidth > 0 && _quizState._typingLines.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_quizState.mounted) {
            _doSplitLines(textWidth);
            _quizState.setState(() {});
          }
        });
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD6DBE8)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(_quizState._typingLines.length, (lineIdx) {
            final line = _quizState._typingLines[lineIdx];
            final isActive = _quizState._typingActiveLine == lineIdx;
            final isDone = _quizState._typingActiveLine > lineIdx;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 原文行（实时着色）
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.blue.withAlpha(13) : null,
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _quizState._ts.lineInputsNotifier,
                    builder: (context, _, __) {
                      final input = isDone || isActive
                          ? _quizState._typingLineInputs[lineIdx]
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
                                fontSize: fontSize,
                                color: textColor,
                                backgroundColor: bgColor,
                                fontWeight: FontWeight.bold,
                                height: 1.6,
                                fontFamily: fontFamily)));
                      }
                      return RichText(text: TextSpan(children: spans));
                    },
                  ),
                ),
                // 输入行
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    height: inputFontSize * 1.6 + 8,
                    child: ClipRect(
                      child: TextField(
                        controller: _quizState._typingLineControllers[lineIdx],
                        focusNode: _quizState._typingLineFocusNodes[lineIdx],
                        enabled: _quizState._typingStarted &&
                            !_quizState._typingFinished,
                        maxLines: 1,
                        textInputAction: TextInputAction.none,
                        style: TextStyle(
                            fontSize: inputFontSize,
                            height: 1.6,
                            fontFamily: fontFamily,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: isActive ? '在此输入上方参考文字...' : '',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(0),
                            borderSide:
                                const BorderSide(color: Color(0xFFD6DBE8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(0),
                            borderSide:
                                const BorderSide(color: Color(0xFFD6DBE8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(0),
                            borderSide:
                                const BorderSide(color: Color(0xFFD6DBE8)),
                          ),
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) =>
                            _onInlineTypingChanged(lineIdx, value),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
              ],
            );
          }),
        ),
      );
    });
  }
}
