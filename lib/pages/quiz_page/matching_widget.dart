part of 'quiz_page.dart';

/// 连线配色方案（随机色彩系??
const List<Color> _kMatchingLineColors = [
  Color(0xFF2563EB), // ??
  Color(0xFFF97316), // ??
  Color(0xFF059669), // ??
  Color(0xFF8B5CF6), // ??
  Color(0xFFEF4444), // ??
  Color(0xFF06B6D4), // ??
  Color(0xFFEC4899), // ??
  Color(0xFFF59E0B), // ??
];

/// 实现连线覆盖层绘制器
class _MatchingOverlayPainter extends CustomPainter {
  final Map<int, int> connections;
  final Map<int, Offset> leftEndpoints;
  final Map<int, Offset> rightEndpoints;

  _MatchingOverlayPainter({
    required this.connections,
    required this.leftEndpoints,
    required this.rightEndpoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 按长序key 排序，分配随机色??
    final sorted = connections.keys.toList()..sort();
    for (int i = 0; i < sorted.length; i++) {
      final li = sorted[i];
      final ri = connections[li]!;
      final start = leftEndpoints[li];
      final end = rightEndpoints[ri];
      if (start == null || end == null) continue;

      final color = _kMatchingLineColors[i % _kMatchingLineColors.length];

      // 贝塞尔线
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            color.withAlpha(204),
            color,
            color.withAlpha(204),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final cp1x = start.dx + (end.dx - start.dx) * 0.3;
      final cp2x = start.dx + (end.dx - start.dx) * 0.7;
      final path = Path();
      path.moveTo(start.dx, start.dy);
      path.cubicTo(cp1x, start.dy, cp2x, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);

      // 起点圆点
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(start, 5, dotPaint);
      canvas.drawCircle(start, 2.5, Paint()..color = Colors.white);

      // 终点圆点
      canvas.drawCircle(end, 5, dotPaint);
      canvas.drawCircle(end, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_MatchingOverlayPainter oldDelegate) {
    if (oldDelegate.connections.length != connections.length) return true;
    for (final entry in connections.entries) {
      if (oldDelegate.connections[entry.key] != entry.value) return true;
    }
    if (oldDelegate.leftEndpoints.length != leftEndpoints.length ||
        oldDelegate.rightEndpoints.length != rightEndpoints.length) return true;
    return false;
  }
}

/// 连线题相??mixin
mixin _MatchingWidgetMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;
  // 连线题栈层连线量??
  final GlobalKey _matchingStackKey = GlobalKey();
  final List<GlobalKey> _leftItemKeys = [];
  final List<GlobalKey> _rightItemKeys = [];
  // 量化结果：左??item 右边缘中心点、右??item 左边缘中心点
  Map<int, Offset> _leftEndpoints = {};
  Map<int, Offset> _rightEndpoints = {};

  /// 获取连线颜色
  static Color _getConnColorStatic(int connIndex) {
    return _kMatchingLineColors[connIndex % _kMatchingLineColors.length];
  }

  /// 获取左列卡片对应的连线式颜色索引
  static int _leftConnColorIdx(Map<int, int> connections, int leftIdx) {
    final sorted = connections.keys.toList()..sort();
    return sorted.indexOf(leftIdx);
  }

  /// 量化连线题各 item 的实际位??
  void _measureMatchingPositions() {
    final stackBox =
        _matchingStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    final newLeft = <int, Offset>{};
    final newRight = <int, Offset>{};

    for (int i = 0; i < _leftItemKeys.length; i++) {
      final ctx = _leftItemKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero, ancestor: stackBox);
      // 右边缘中??
      newLeft[i] =
          Offset(pos.dx + box.size.width, pos.dy + box.size.height / 2);
    }

    for (int i = 0; i < _rightItemKeys.length; i++) {
      final ctx = _rightItemKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero, ancestor: stackBox);
      // 左边缘中??
      newRight[i] = Offset(pos.dx, pos.dy + box.size.height / 2);
    }

    // 只在有变化时 setState
    if (!_offsetMapsEqual(newLeft, _leftEndpoints) ||
        !_offsetMapsEqual(newRight, _rightEndpoints)) {
      _quizState.setState(() {
        _leftEndpoints = newLeft;
        _rightEndpoints = newRight;
      });
    }
  }

  static bool _offsetMapsEqual(Map<int, Offset> a, Map<int, Offset> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if ((entry.value.dx - other.dx).abs() > 0.5 ||
          (entry.value.dy - other.dy).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  /// 连线题（优化版：Stack 并行连线 + 随机色彩 + 图片 + 进度提示??
  Widget _buildMatchingQuestion(Map<String, dynamic> question) {
    final items = question['items'] as List<dynamic>? ?? [];
    final rawMap = _quizState._answers[_quizState._currentQuestionIndex];
    final Map<int, int> connections = rawMap is Map
        ? Map<int, int>.from(rawMap['mapping'] is Map
            ? (rawMap['index_mapping'] is Map
                ? rawMap['index_mapping']
                : rawMap['mapping'])
            : rawMap.map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0,
                int.tryParse(v.toString()) ?? 0)))
        : <int, int>{};
    final int? selectedLeft =
        _quizState._matchingSelectedLeft[_quizState._currentQuestionIndex];
    final int totalPairs = items.length;
    final int connectedCount = connections.length;

    // 确保 keys 数量足够
    while (_leftItemKeys.length < items.length) {
      _leftItemKeys.add(GlobalKey());
    }
    while (_rightItemKeys.length < items.length) {
      _rightItemKeys.add(GlobalKey());
    }

    // 渲染后测量位置（仅首次布局后执行一次，避免重复注册回调）
    if (!_quizState._matchingMeasured) {
      _quizState._matchingMeasured = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_quizState.mounted) return;
        _measureMatchingPositions();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 题干
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            question['questionText'] ?? '',
            style: TextStyle(
                fontSize: 31.2 * _quizState._contentScale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'SimHei'),
          ),
        ),
        const SizedBox(height: 16),
        // 提示 + 进度
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withAlpha(38),
                    Colors.orangeAccent.withAlpha(26),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Text(
                    '点击左列，再点击右列进行连线',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: connectedCount == totalPairs
                    ? Colors.green.withAlpha(26)
                    : Colors.blue.withAlpha(26),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connectedCount == totalPairs
                        ? Icons.check_circle
                        : Icons.link,
                    size: 14,
                    color: connectedCount == totalPairs
                        ? Colors.green
                        : Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$connectedCount/$totalPairs',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: connectedCount == totalPairs
                          ? Colors.green
                          : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedLeft != null) ...[
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha(26),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_forward, size: 12, color: Colors.purple),
                    const SizedBox(width: 4),
                    Text(
                      '请选择右列',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // 连线区域：Stack 叠层，底层每??Row，顶层连??
        Stack(
          key: _matchingStackKey,
          children: [
            // 底层：每对一??Row（弹性布局??
            Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(items.length, (index) {
                final bool isLeftConnected = connections.containsKey(index);
                final bool isLeftSelected = selectedLeft == index;
                final int leftConnIdx = isLeftConnected
                    ? _leftConnColorIdx(connections, index)
                    : -1;
                final Color leftConnColor = leftConnIdx >= 0
                    ? _getConnColorStatic(leftConnIdx)
                    : Colors.blue;
                final bool hasLeftImage = items[index]['leftImage'] != null &&
                    items[index]['leftImage'].toString().isNotEmpty;

                final bool isRightConnected = connections.containsValue(index);
                int rightConnIdx = -1;
                if (isRightConnected) {
                  final sorted = connections.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  for (int i = 0; i < sorted.length; i++) {
                    if (sorted[i].value == index) {
                      rightConnIdx = i;
                      break;
                    }
                  }
                }
                final Color rightConnColor = rightConnIdx >= 0
                    ? _getConnColorStatic(rightConnIdx)
                    : Colors.blue;
                final bool isHighlightTarget =
                    selectedLeft != null && !isRightConnected;
                final bool hasRightImage = items[index]['rightImage'] != null &&
                    items[index]['rightImage'].toString().isNotEmpty;

                return Padding(
                  padding: EdgeInsets.only(
                      bottom: index < items.length - 1 ? 36 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左列卡片（弹性布局??
                      Expanded(
                        child: GestureDetector(
                          key: _leftItemKeys.length > index
                              ? _leftItemKeys[index]
                              : null,
                          onTap: () {
                            _quizState.setState(() {
                              if (isLeftConnected) {
                                connections.remove(index);
                                _quizState._answers[
                                        _quizState._currentQuestionIndex] =
                                    Map<int, int>.from(connections);
                              } else if (isLeftSelected) {
                                _quizState._matchingSelectedLeft[
                                    _quizState._currentQuestionIndex] = null;
                              } else {
                                _quizState._matchingSelectedLeft[
                                    _quizState._currentQuestionIndex] = index;
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isLeftSelected
                                  ? Colors.blue.withAlpha(20)
                                  : isLeftConnected
                                      ? leftConnColor.withAlpha(20)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isLeftSelected
                                    ? Colors.blue
                                    : isLeftConnected
                                        ? leftConnColor
                                        : Colors.grey[300]!,
                                width:
                                    isLeftSelected || isLeftConnected ? 2 : 1,
                              ),
                              boxShadow: isLeftSelected
                                  ? [
                                      BoxShadow(
                                          color: Colors.blue.withAlpha(51),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4))
                                    ]
                                  : isLeftConnected
                                      ? [
                                          BoxShadow(
                                              color:
                                                  leftConnColor.withAlpha(38),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3))
                                        ]
                                      : [
                                          BoxShadow(
                                              color: Colors.black.withAlpha(10),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2))
                                        ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isLeftSelected
                                        ? Colors.blue
                                        : isLeftConnected
                                            ? leftConnColor
                                            : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      String.fromCharCode(65 + index),
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: isLeftSelected || isLeftConnected
                                            ? Colors.white
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        items[index]['leftText'] ?? '',
                                        style: TextStyle(
                                          fontSize: 26 * _quizState._contentScale,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SimHei',
                                        ),
                                      ),
                                      if (hasLeftImage) ...[
                                        const SizedBox(height: 4),
                                        _quizState._buildImage(items[index]
                                                ['leftImage']
                                            .toString()),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isLeftConnected)
                                  Icon(Icons.check_circle,
                                      size: 18, color: leftConnColor),
                                if (isLeftSelected)
                                  Icon(Icons.radio_button_checked,
                                      size: 18, color: Colors.blue),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 左右间距 - 根据屏幕宽度动态计算
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final gapWidth =
                              (constraints.maxWidth * 0.12).clamp(40.0, 160.0);
                          return SizedBox(width: gapWidth);
                        },
                      ),
                      // 右列卡片（弹性布局??
                      Expanded(
                        child: GestureDetector(
                          key: _rightItemKeys.length > index
                              ? _rightItemKeys[index]
                              : null,
                          onTap: () {
                            if (isRightConnected) {
                              final leftKey = connections.entries
                                  .where((e) => e.value == index)
                                  .map((e) => e.key)
                                  .firstOrNull;
                              if (leftKey != null) {
                                _quizState.setState(() {
                                  connections.remove(leftKey);
                                  _quizState._answers[
                                          _quizState._currentQuestionIndex] =
                                      Map<int, int>.from(connections);
                                });
                              }
                            } else if (selectedLeft != null) {
                              _quizState.setState(() {
                                connections[selectedLeft] = index;
                                _quizState._answers[
                                        _quizState._currentQuestionIndex] =
                                    Map<int, int>.from(connections);
                                _quizState._matchingSelectedLeft[
                                    _quizState._currentQuestionIndex] = null;
                              });
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isRightConnected
                                  ? rightConnColor.withAlpha(20)
                                  : isHighlightTarget
                                      ? Colors.purple.withAlpha(10)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isRightConnected
                                    ? rightConnColor
                                    : isHighlightTarget
                                        ? Colors.purple.withAlpha(102)
                                        : Colors.grey[300]!,
                                width: isRightConnected ? 2 : 1,
                              ),
                              boxShadow: isRightConnected
                                  ? [
                                      BoxShadow(
                                          color: rightConnColor.withAlpha(38),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3))
                                    ]
                                  : isHighlightTarget
                                      ? [
                                          BoxShadow(
                                              color:
                                                  Colors.purple.withAlpha(13),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2))
                                        ]
                                      : [
                                          BoxShadow(
                                              color: Colors.black.withAlpha(10),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2))
                                        ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        items[index]['rightText'] ?? '',
                                        style: TextStyle(
                                          fontSize: 26 * _quizState._contentScale,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SimHei',
                                        ),
                                      ),
                                      if (hasRightImage) ...[
                                        const SizedBox(height: 4),
                                        _quizState._buildImage(items[index]
                                                ['rightImage']
                                            .toString()),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 36,
                                  height: 36,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: isRightConnected
                                        ? rightConnColor
                                        : isHighlightTarget
                                            ? Colors.purple.withAlpha(51)
                                            : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: isRightConnected
                                            ? Colors.white
                                            : isHighlightTarget
                                                ? Colors.purple
                                                : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                                if (isRightConnected)
                                  Icon(Icons.check_circle,
                                      size: 18, color: rightConnColor),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            // 顶层：并行连线绘制器
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MatchingOverlayPainter(
                    connections: connections,
                    leftEndpoints: _leftEndpoints,
                    rightEndpoints: _rightEndpoints,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
