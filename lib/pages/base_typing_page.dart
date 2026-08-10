import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';

/// 打字页面配置
class TypingConfig {
  final String type; // 'chinese' 或 'english'
  final String title;
  final String fontFamily;
  final double baseFontSize;
  final int defaultTimeLimitMinutes;
  final int defaultTargetSpeed;
  final int defaultTargetChars;
  final double defaultPointsPerError;
  final String apiConfigEndpoint;
  final String apiArticlesEndpoint;

  const TypingConfig({
    required this.type,
    required this.title,
    required this.fontFamily,
    required this.baseFontSize,
    required this.defaultTimeLimitMinutes,
    required this.defaultTargetSpeed,
    required this.defaultTargetChars,
    required this.defaultPointsPerError,
    required this.apiConfigEndpoint,
    required this.apiArticlesEndpoint,
  });
}

/// 打字练习页面的抽象基类
/// 子类只需提供 TypingConfig 配置即可
abstract class BaseTypingPage extends StatefulWidget {
  final TypingConfig config;

  const BaseTypingPage({super.key, required this.config});
}

abstract class BaseTypingPageState<T extends BaseTypingPage> extends State<T> with RouteAware {
  // 配置参数
  TypingConfig get config => widget.config;

  // 状态
  int _timeLimitMinutes = 5;
  int _targetSpeed = 20;

  /// 评分目标字数 — 教师端可配置，根据目标字数计算比例得分
  /// 当前版本直接使用速度目标评分，此字段保留为后续扩展
  // ignore: unused_field
  int _targetChars = 100;
  double _pointsPerError = 1.0;
  static const int _totalScore = 100;
  double _fontSize = 26.0;
  double _inputFontSize = 24.0;
  double _lastLayoutWidth = 0;

  // 文章数据
  List<String> _practiceTexts = [];
  bool _isLoadingArticles = true;
  String? _loadError;

  // 教师端指定的文章选择策略
  bool _randomArticle = true;
  int? _selectedArticleIndex;

  // 打字状态
  String _currentText = '';
  bool _isStarted = false;
  bool _isFinished = false;
  bool _isFinishing = false;
  bool _isPaused = false;
  Timer? _timer;
  int _remainingSeconds = 300;
  int _elapsedSeconds = 0;
  int _correctChars = 0;
  int _totalTyped = 0;
  double _score = 0;

  // 多行输入
  int _activeLine = 0;
  final List<String> _lineInputs = [];
  final List<TextEditingController> _lineControllers = [];
  final List<FocusNode> _lineFocusNodes = [];
  List<String> _lines = [];

  bool _autoPausedByRoute = false;

  // 抽象方法：子类提供 RouteObserver
  RouteObserver<ModalRoute<void>> get routeObserver;

  @override
  void initState() {
    super.initState();
    try {
      SocketService.instance.updateStatus('typing');
    } catch (e) {
      print('更新Socket状态为typing失败: $e');
    }
    _fetchTypingConfig();
    _fetchArticles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _timer?.cancel();
    _timer = null;
    _disposeLineControllers();
    try {
      SocketService.instance.updateStatus('online');
    } catch (e) {
      print('恢复Socket状态失败: $e');
    }
    super.dispose();
  }

  @override
  void didPushNext() {
    if (_isStarted && !_isFinished && !_isPaused) {
      _pauseTyping();
      _autoPausedByRoute = true;
    }
  }

  @override
  void didPopNext() {
    if (_isStarted && !_isFinished && _isPaused && _autoPausedByRoute) {
      _resumeTyping();
      _autoPausedByRoute = false;
    }
  }

  /// 从教师端获取打字配置
  Future<void> _fetchTypingConfig() async {
    try {
      final response = await ApiService.getSharedClient()
          .get(Uri.parse('${ApiService.baseUrl}${config.apiConfigEndpoint}'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final cfg = data['data'] as Map<String, dynamic>;
          if (!mounted) return;
          int parseInt(dynamic value, int fallback) =>
              value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? fallback;
          setState(() {
            _timeLimitMinutes = parseInt(cfg['time_limit'], config.defaultTimeLimitMinutes);
            _targetSpeed = parseInt(cfg['target_speed'], config.defaultTargetSpeed);
            _targetChars = parseInt(cfg['target_chars'], config.defaultTargetChars);
            _pointsPerError = (cfg['points_per_error'] is num)
                ? (cfg['points_per_error'] as num).toDouble()
                : double.tryParse(cfg['points_per_error']?.toString() ?? '') ??
                    config.defaultPointsPerError;
            _randomArticle = cfg['random'] ?? true;
            _selectedArticleIndex =
                _randomArticle ? null : (cfg['selected_article_index'] as int?);
          });
          // 配置获取成功后，再按配置拉取文章列表（文章可能已随配置更新）
          await _fetchArticles();
        }
      }
    } catch (e) {
      print('获取打字配置失败，使用默认值: $e');
    }
  }

  /// 从教师端HTTP API获取打字文章
  Future<void> _fetchArticles() async {
    if (!mounted) return;
    setState(() {
      _isLoadingArticles = true;
      _loadError = null;
    });

    try {
      final response = await ApiService.getSharedClient()
          .get(Uri.parse('${ApiService.baseUrl}${config.apiArticlesEndpoint}'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> articles = data['data'] as List<dynamic>;
          final texts = articles
              .whereType<Map>()
              .map((a) => a['content'])
              .whereType<String>()
              .where((text) => text.isNotEmpty)
              .toList();
          if (!mounted) return;
          setState(() {
            _practiceTexts = texts;
            _isLoadingArticles = false;
          });
          if (_practiceTexts.isNotEmpty) {
            _generateNewText();
          } else {
            _loadError = '当前没有可用文章';
          }
        } else {
          if (!mounted) return;
          setState(() {
            _isLoadingArticles = false;
            _loadError = '获取文章失败: ${data['error'] ?? '未知错误'}';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoadingArticles = false;
          _loadError = '获取文章失败，状态码: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingArticles = false;
        _loadError = '无法连接教师端，请检查网络连接。\n错误: $e';
      });
    }
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
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
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

  void _generateNewText() {
    if (_practiceTexts.isEmpty) return;
    if (!_randomArticle && _selectedArticleIndex != null && _selectedArticleIndex! >= 0 && _selectedArticleIndex! < _practiceTexts.length) {
      // 教师端指定了特定文章
      _currentText = _practiceTexts[_selectedArticleIndex!];
    } else {
      // 随机选择一篇文章
      final random = Random();
      _currentText = _practiceTexts[random.nextInt(_practiceTexts.length)];
    }
  }

  /// 根据窗口宽度动态计算字体大小
  double _calcFontSize(double containerWidth) {
    const baseWidth = 1180.0;
    final scale = (containerWidth / baseWidth).clamp(0.8, 1.5);
    return config.baseFontSize * scale;
  }

  /// 使用精确可用宽度进行分行
  void _splitLines(double width) {
    if (_currentText.isEmpty) return;
    if (_lines.isNotEmpty && (width - _lastLayoutWidth).abs() < 1.0) return;

    _lastLayoutWidth = width;
    _fontSize = _calcFontSize(width);
    _inputFontSize = _fontSize - (config.type == 'english' ? 1 : 0.5);

    final availableWidth = width - 36;
    if (availableWidth <= 0) return;

    final style = TextStyle(fontSize: _fontSize, height: 1.6, fontFamily: config.fontFamily);
    final tp = TextPainter(
      text: TextSpan(text: config.type == 'english' ? 'W' : '字', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = tp.width;
    tp.dispose();
    if (charWidth <= 0) return;

    final charsPerLine = (availableWidth / charWidth).floor();
    if (charsPerLine <= 0) return;

    final oldLineInputs = List<String>.from(_lineInputs);
    final oldActiveLine = _activeLine;

    _disposeLineControllers();
    _lineInputs.clear();
    _lineControllers.clear();
    _lineFocusNodes.clear();

    _lines = [];
    for (int i = 0; i < _currentText.length; i += charsPerLine) {
      final end = (i + charsPerLine < _currentText.length) ? i + charsPerLine : _currentText.length;
      _lines.add(_currentText.substring(i, end));
    }

    for (int i = 0; i < _lines.length; i++) {
      if (i < oldLineInputs.length) {
        final input = oldLineInputs[i];
        _lineInputs
            .add(input.length <= _lines[i].length ? input : input.substring(0, _lines[i].length));
      } else {
        _lineInputs.add('');
      }
      _lineControllers.add(TextEditingController(text: _lineInputs[i]));
      _lineFocusNodes.add(_createLineFocusNode(i));
    }

    _activeLine = oldActiveLine < _lines.length ? oldActiveLine : _lines.length - 1;
    if (_activeLine < 0) _activeLine = 0;

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
      print('更新Socket状态为typing失败: $e');
    }
    setState(() {
      _isStarted = true;
      _isFinished = false;
      _isPaused = false;
      _remainingSeconds = _timeLimitMinutes * 60;
      _elapsedSeconds = 0;
      _correctChars = 0;
      _totalTyped = 0;
      _score = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lineFocusNodes.isNotEmpty) {
        _lineFocusNodes[0].requestFocus();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
          _elapsedSeconds++;
        });
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
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
          _elapsedSeconds++;
        });
        if (_remainingSeconds <= 0) _finishTyping();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lineFocusNodes.isNotEmpty && _activeLine < _lineFocusNodes.length) {
        _lineFocusNodes[_activeLine].requestFocus();
      }
    });
  }

  void _onLineChanged(int lineIdx, String value) {
    if (!_isStarted || _isFinished || _isPaused) return;
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
    setState(() {
      _totalTyped = totalTyped;
      _correctChars = correctChars;
    });
  }

  void _checkAndAdvanceLine(int lineIdx, String currentVal) {
    final lineText = _lines[lineIdx];
    final controller = _lineControllers[lineIdx];
    final cursorAtEnd = controller.selection.baseOffset >= currentVal.length;
    if (currentVal.length >= lineText.length && cursorAtEnd) {
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
    if (_isFinishing || _isFinished) return;
    _isFinishing = true;
    _timer?.cancel();
    try {
      try {
        SocketService.instance.updateStatus('online');
      } catch (e) {
        print('恢复Socket状态失败: $e');
      }
      int errorCount = _totalTyped - _correctChars;
      final minutes = _elapsedSeconds > 0 ? _elapsedSeconds / 60.0 : 1.0;
      final speed = _correctChars / minutes;
      if (!mounted) return;
      setState(() {
        _isFinished = true;
        double baseScore = (speed / _targetSpeed * _totalScore).clamp(0, _totalScore).toDouble();
        _score = (baseScore - errorCount * _pointsPerError).clamp(0, _totalScore).toDouble();
      });

      final accuracy = _totalTyped > 0 ? (_correctChars / _totalTyped * 100).round() : 0;
      final speedRounded =
          _elapsedSeconds > 0 ? (_correctChars / (_elapsedSeconds / 60.0)).round() : 0;
      final userProvider = context.read<UserProvider>();
      userProvider.addTypingResult({
        'type': config.type,
        'wpm': speedRounded,
        'accuracy': accuracy,
        'score': _score.round(),
        'elapsed': _elapsedSeconds,
        'correctChars': _correctChars,
        'totalTyped': _totalTyped,
        'date': DateTime.now().toString().substring(0, 19),
      });

      final auth = context.read<AuthProvider>();
      final currentUser = auth.currentUser;
      // 生成唯一幂等ID，防止重复提交
      final submissionId = currentUser != null
          ? '${currentUser.id}_typing_${config.type}_${DateTime.now().millisecondsSinceEpoch}'
          : 'typing_${config.type}_${DateTime.now().millisecondsSinceEpoch}';

      await _saveTypingScoreToServer(_score.round(), speedRounded, accuracy, submissionId);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('练习完成'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('成绩: ${_score.round()}/$_totalScore 分',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('已打字符数: $_totalTyped', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text('错误字符数: $errorCount',
                  style:
                      TextStyle(fontSize: 16, color: errorCount > 0 ? Colors.red : Colors.green)),
              const SizedBox(height: 4),
              Text('准确率: $accuracy%', style: const TextStyle(fontSize: 16)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resetPractice();
              },
              child: const Text('再来一次'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pop(context);
              },
              child: const Text('返回'),
            ),
          ],
        ),
      );
    } finally {
      _isFinishing = false;
    }
  }

  Future<void> _saveTypingScoreToServer(
      int score, int speed, int accuracy, String submissionId) async {
    try {
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      final user = auth.currentUser;
      if (user == null) return;

      final points = (score * 0.1).round();

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/score/typing'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'submission_id': submissionId,
              'student_id': user.id,
              'student_name': user.name,
              'type': config.type,
              'score': score,
              'points': points,
              'class_id': user.classId ?? '',
              'speed': speed,
              'accuracy': accuracy,
              'elapsed_seconds': _elapsedSeconds,
              'correct_chars': _correctChars,
              'total_chars': _totalTyped,
              'error_count': _totalTyped - _correctChars,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('成绩已保存到教师端');
          final totalPoints = data['total_points'] as int?;
          if (totalPoints != null) {
            userProvider.setPointsDirectly(totalPoints);
          }
          return;
        }
      }
      final saved = await _savePendingSubmission(score, speed, accuracy, submissionId);
      if (!saved) {
        print('警告: 成绩保存失败且无法写入待同步队列，请重新提交');
      }
    } on TimeoutException {
      print('保存成绩超时: $submissionId');
      await _savePendingSubmission(score, speed, accuracy, submissionId);
    } catch (e) {
      print('保存成绩失败: $e');
      // 保存到本地待同步队列
      await _savePendingSubmission(score, speed, accuracy, submissionId);
    }
  }

  Future<bool> _savePendingSubmission(
      int score, int speed, int accuracy, String submissionId) async {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return false;
    try {
      final storage = LocalStorageService.instance;
      // 整个读改写过程在单文件锁内执行，避免并发写入导致记录丢失
      return storage.withFileLock('pending_typing_submissions.json', () async {
        final pending = await storage.readJson('pending_typing_submissions.json');
        final submissions = (pending['submissions'] as List<dynamic>?) ?? [];
        final pendingPayload = {
          'submission_id': submissionId,
          'student_id': currentUser.id,
          'student_name': currentUser.name,
          'class_id': currentUser.classId ?? '',
          'type': config.type,
          'score': score,
          'points': (score * 0.1).round(),
          'speed': speed,
          'accuracy': accuracy,
          'elapsed_seconds': _elapsedSeconds,
          'correct_chars': _correctChars,
          'total_chars': _totalTyped,
          'error_count': _totalTyped - _correctChars,
          'created_at': DateTime.now().toIso8601String(),
          'retry_count': 0,
        };
        submissions.add(pendingPayload);
        final saved = await storage.writeJson('pending_typing_submissions.json', {
          'submissions': submissions,
        });
        if (!saved) {
          print('警告: 待同步记录写入失败，成绩可能丢失');
        }
        return saved;
      });
    } catch (e) {
      print('保存待同步记录失败: $e');
      return false;
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
      _remainingSeconds = _timeLimitMinutes * 60;
      _elapsedSeconds = 0;
      _correctChars = 0;
      _totalTyped = 0;
      _score = 0;
      _activeLine = 0;
      _generateNewText();
    });
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
                Text(config.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _remainingSeconds <= 60 && _isStarted
                        ? Colors.red.withAlpha(26)
                        : AppTheme.primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(_formatTime(_remainingSeconds),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _remainingSeconds <= 60 && _isStarted
                              ? Colors.red
                              : AppTheme.primaryColor,
                          fontSize: 16)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('已打字数: $_totalTyped',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('正确: $_correctChars',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('错误: ${_totalTyped - _correctChars}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
                const SizedBox(width: 8),
                if (!_isStarted && !_isLoadingArticles && _loadError == null)
                  ElevatedButton.icon(
                    onPressed: _startTyping,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('开始练习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ),

          // 加载中或错误提示
          if (_isLoadingArticles)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在从教师端加载文章...', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
            )
          else if (_loadError != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _fetchArticles,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            )
          else
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.blue.withAlpha(13) : null,
                                ),
                                child: Builder(builder: (context) {
                                  final input = isDone || isActive ? _lineInputs[lineIdx] : '';
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
                                            fontFamily: config.fontFamily)));
                                  }
                                  return RichText(text: TextSpan(children: spans));
                                }),
                              ),
                              // 每行下方都有输入框/结果
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color:
                                      isActive ? const Color(0xFFEEF5FF) : const Color(0xFFF8FAFC),
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
                                        fontFamily: config.fontFamily,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: isActive
                                          ? (config.type == 'english'
                                              ? 'Type the text above here...'
                                              : '请在此输入上方文字...')
                                          : '',
                                      hintStyle: TextStyle(color: Colors.grey[400]),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(0),
                                        borderSide: BorderSide(color: const Color(0xFFD6DBE8)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(0),
                                        borderSide: BorderSide(color: const Color(0xFFD6DBE8)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(0),
                                        borderSide: BorderSide(color: const Color(0xFFD6DBE8)),
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
                                    onChanged: (value) => _onLineChanged(lineIdx, value),
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
