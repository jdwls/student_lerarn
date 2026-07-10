library quiz_page;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../providers/auth_provider.dart';
import '../../services/quiz_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/socket_service.dart';
import '../../services/vhd_service.dart';
import '../../theme/app_theme.dart';
import '../result_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_path.dart';

// Include all part files
part 'matching_widget.dart';
part 'typing_widget.dart';
part 'choice_widget.dart';
part 'sequential_widget.dart';
part 'operation_handler.dart';
part 'data_loader.dart';
part 'scoring_utils.dart';

/// 课堂小测答题面
class QuizPage extends StatefulWidget {
  final String studentId;
  final String studentName;

  const QuizPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage>
    with
        _MatchingWidgetMixin,
        _TypingWidgetMixin,
        _ChoiceWidgetMixin,
        _SequentialWidgetMixin,
        _OperationHandlerMixin,
        _DataLoaderMixin,
        _ScoringUtilsMixin {
  // 状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showingOperationOverlay = false; // 是否正在显示操作题浮动窗口
  // 操作题浮动窗口相关数据
  Map<String, dynamic>? _currentOperationQuestion;
  List<dynamic>? _currentOperationInitialFiles;
  List<dynamic>? _currentOperationAnswers;
  bool _isDownloadingImages = false;
  int _totalImages = 0;
  int _downloadedImages = 0;
  String? _errorMessage;
  final List<String> _questionBanks = [];
  String? _selectedBank;

  // 题库数据
  List<Map<String, dynamic>> _choiceQuestions = [];
  List<Map<String, dynamic>> _matchingQuestions = [];
  List<Map<String, dynamic>> _sequentialQuestions = [];
  List<Map<String, dynamic>> _typingQuestions = [];
  List<Map<String, dynamic>> _operationQuestions = [];

  // 所有题目（当前显示的题目）
  List<Map<String, dynamic>> _currentQuestions = [];

  // 答题状态
  int _currentQuestionIndex = 0;
  final Map<int, dynamic> _answers = {}; // 题目索引 -> 答案

  // 连线题状态
  final Map<int, int?> _matchingSelectedLeft = {}; // 题目索引 -> 选中的左列索引

  // 当前选择的题目类型
  String _selectedQuestionType = 'all'; // all, choice, matching, sequential

  // Pending typing state (for layout-off screen rendering)
  String? _pendingTypingText;
  double? _lastTypingLayoutWidth;
  double? _pendingTypingFontSize;
  String? _pendingTypingFontFamily;

  // 计时器
  Timer? _timer;
  int _elapsedSeconds = 0;
  final bool _isPaused = false;

  // 考试时间限制
  int _examTimeLimit = 0; // 考试时间限制（分钟），0表示无限制
  int _earlySubmitMinutes = 0; // 提前交卷时间（考试开始多少分钟后可交卷），0表示只能等时间结束
  int _examRemainingSeconds = 0; // 考试剩余时间（秒）
  Timer? _examTimer; // 考试倒计时计时器

  /// 是否可以交卷
  /// - 无时间限制时，始终可交卷
  /// - 有时间限制时：
  ///   - 如果设置了提前交卷时间(_earlySubmitMinutes>0)，考试开始超过该时间后可交卷
  ///   - 如果未设置提前交卷时间，只能等考试时间结束才能交卷
  bool get _canSubmitExam {
    if (_examTimeLimit <= 0) return true; // 无时间限制，可交卷
    if (_examRemainingSeconds <= 0) return true; // 时间到，可交卷
    if (_earlySubmitMinutes > 0) {
      // 已超过提前交卷时间，可交卷
      final elapsedMinutes = _elapsedSeconds / 60;
      return elapsedMinutes >= _earlySubmitMinutes;
    }
    return false; // 未设置提前交卷时间，只能等时间结束
  }

  // 打字题独立状态（每个打字题独立的时间、输入、按钮状态）
  final Map<int, TypingQuestionState> _typingStates = {};
  int _typingQuestionIndex = -1; // 当前显示的打字题全局索引

  /// 获取指定题目的打字状态
  TypingQuestionState _getTypingState(int questionIndex) {
    if (!_typingStates.containsKey(questionIndex)) {
      _typingStates[questionIndex] = TypingQuestionState();
    }
    return _typingStates[questionIndex]!;
  }

  /// 当前显示题目的打字状态
  TypingQuestionState get _ts => _getTypingState(_currentQuestionIndex);

  // 便捷 getter/setter
  bool get _typingStarted => _ts.started;
  set _typingStarted(bool v) => _ts.started = v;
  bool get _typingFinished => _ts.finished;
  set _typingFinished(bool v) => _ts.finished = v;
  bool get _typingPaused => _ts.paused;
  set _typingPaused(bool v) => _ts.paused = v;
  Timer? get _typingTimer => _ts.timer;
  set _typingTimer(Timer? v) => _ts.timer = v;
  int get _typingRemainingSeconds => _ts.remainingSeconds;
  set _typingRemainingSeconds(int v) => _ts.remainingSeconds = v;
  int get _typingActiveLine => _ts.activeLine;
  set _typingActiveLine(int v) => _ts.activeLine = v;
  int get _typingCorrectChars => _ts.correctChars;
  set _typingCorrectChars(int v) => _ts.correctChars = v;
  int get _typingTotalTyped => _ts.totalTyped;
  set _typingTotalTyped(int v) => _ts.totalTyped = v;
  List<TextEditingController> get _typingLineControllers => _ts.lineControllers;
  List<FocusNode> get _typingLineFocusNodes => _ts.lineFocusNodes;
  List<String> get _typingLineInputs => _ts.lineInputs;
  List<String> get _typingLines => _ts.lines;
  set _typingLines(List<String> v) => _ts.lines = v;

  // 定时器用于检测窗口最小化（Win+D 后恢复）
  Timer? _windowCheckTimer;

  // 开始检测窗口状态
  void _startWindowCheck() {
    _windowCheckTimer?.cancel();
    _windowCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_showingOperationOverlay) {
        _windowCheckTimer?.cancel();
        return;
      }
      try {
        final isMinimized = await windowManager.isMinimized();
        if (isMinimized) {
          debugPrint('窗口被最小化（可能是 Win+D），正在恢复显示...');
          await windowManager.restore();
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setAlwaysOnTop(true);
        }
      } catch (e) {
        // 静默处理错误
      }
    });
  }

  // 停止检测窗口状态
  void _stopWindowCheck() {
    _windowCheckTimer?.cancel();
    _windowCheckTimer = null;
  }

  // 窗口状态（进入小测前首页的状态）
  bool _wasFullScreenBeforeQuiz = false;

  @override
  void initState() {
    super.initState();
    // 启动时清理残留的 subst 虚拟驱动器映射，避免"位置不可用"错误
    try {
      VhdService.cleanupAllSubstDrives();
    } catch (e) {
      debugPrint('清理残留虚拟驱动器失败: $e');
    }
    // 通知教师端：进入小测状态
    try {
      SocketService.instance.updateStatus('exam');
    } catch (e) {
      debugPrint('更新Socket状态为exam失败: $e');
    }
    // 记录进入前的窗口状态，然后全屏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordWindowState();
      _enterFullScreen();
    });
    _loadQuestionBanks();
  }

  /// 记录进入小测前的窗口状态
  void _recordWindowState() async {
    try {
      _wasFullScreenBeforeQuiz = await windowManager.isFullScreen();
    } catch (_) {
      _wasFullScreenBeforeQuiz = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _examTimer?.cancel();
    for (final typingState in _typingStates.values) {
      typingState.dispose();
    }
    _typingStates.clear();
    // 退出小测后恢复窗口到进入前的状态
    _restoreWindowAfterQuiz();
    try {
      SocketService.instance.updateStatus('online');
    } catch (e) {
      debugPrint('恢复Socket状态失败: $e');
    }
    super.dispose();
  }

  /// 退出小测后恢复到进入前的窗口状态
  void _restoreWindowAfterQuiz() async {
    try {
      if (_wasFullScreenBeforeQuiz) {
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        await windowManager.setMinimumSize(const Size(1280, 720));
        await windowManager.setSize(const Size(1280, 720));
        await windowManager.center();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  /// 进入全屏模式
  Future<void> _enterFullScreen() async {
    try {
      await windowManager.setFullScreen(true).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('setFullScreen 超时，尝试最大化');
          try {
            windowManager.maximize();
          } catch (_) {}
        },
      );
    } catch (e) {
      debugPrint('进入全屏失败: $e');
      try {
        await windowManager.maximize().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('maximize 超时');
          },
        );
      } catch (e2) {
        debugPrint('窗口最大化失败: $e2');
      }
    }
  }

  /// 退出全屏模式
  Future<void> _exitFullScreen() async {
    try {
      await windowManager.setFullScreen(false).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('setFullScreen(false) 超时');
        },
      );
    } catch (e) {
      debugPrint('退出全屏失败: $e');
      try {
        await windowManager.restore().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('restore 超时');
          },
        );
      } catch (e2) {
        debugPrint('窗口还原失败: $e2');
      }
    }
  }

  /// 开始计时器
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        if (mounted) {
          setState(() {
            _elapsedSeconds++;
          });
        }
      }
    });
  }

  /// 格式化时间
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // 如果正在显示操作题浮动窗口，显示小窗口模式
    if (_showingOperationOverlay) {
      return _buildOperationOverlayWindow();
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // 答题中，退出确认对话框
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出答题'),
            content: const Text('确定要退出答题吗？退出后答题现场将丧失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认退出'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // 如果正在显示操作题浮动窗口，隐藏大页面内容
    if (_showingOperationOverlay) {
      return const SizedBox.shrink(); // 返回空容器，让 Overlay 显示
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            if (_isDownloadingImages) ...[
              Text('下载图片: $_downloadedImages/$_totalImages'),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value:
                      _totalImages > 0 ? _downloadedImages / _totalImages : 0,
                ),
              ),
            ] else ...[
              const Text('加载中...'),
            ],
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadQuestionBanks,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    // 题库选择界面
    if (_selectedBank == null) {
      return _buildBankSelection();
    }

    // 做题界面
    return _buildQuizInterface();
  }

  /// 题库选择界面
  Widget _buildBankSelection() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primaryColor.withAlpha(26),
            Colors.white,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部图标
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child:
                        const Icon(Icons.quiz, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '课堂小测',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '选择一个题库开始答题',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // 题库列表
              Expanded(
                child: _questionBanks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_off,
                                size: 80, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              '暂无可用题库',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '请等待教师端发布题库',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _questionBanks.length,
                        itemBuilder: (context, index) {
                          final bank = _questionBanks[index];
                          return _buildBankCard(bank);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 题库卡片
  Widget _buildBankCard(String bankName) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _loadQuestionBank(bankName),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withAlpha(26),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.library_books,
                    color: AppTheme.primaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  bankName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '点击开始',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 做题界面
  Widget _buildQuizInterface() {
    if (_currentQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '题库中没有题目',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回'),
            ),
          ],
        ),
      );
    }

    // 确保索引在有效范围内
    if (_currentQuestionIndex < 0 ||
        _currentQuestionIndex >= _currentQuestions.length) {
      _currentQuestionIndex = 0;
    }

    final question = _currentQuestions[_currentQuestionIndex];

    return Column(
      children: [
        // 顶部信息栏
        _buildTopBar(),
        // 左侧题目导航 + 右侧题目内容
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧题目导航 - 固定高度
              Container(
                width: 200,
                margin: const EdgeInsets.only(top: 16, left: 16, bottom: 16),
                child: _buildQuestionNav(),
              ),
              const SizedBox(width: 8),
              // 右侧题目内容
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // 题目卡片
                        _buildQuestionCard(question),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶部信息栏
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 上一题
          if (_currentQuestionIndex > 0)
            GestureDetector(
              onTap: () {
                if (_typingStarted && !_typingFinished && !_typingPaused) {
                  _pauseInlineTyping();
                }
                setState(() => _currentQuestionIndex--);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 27, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('上一题',
                        style: TextStyle(fontSize: 21, color: Colors.white)),
                  ],
                ),
              ),
            )
          else
            const SizedBox(width: 110),
          const SizedBox(width: 12),
          // 题库名称
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selectedBank ?? '',
              style: const TextStyle(
                  fontSize: 20,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SimHei'),
            ),
          ),
          const SizedBox(width: 12),
          // 题号
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_currentQuestionIndex + 1}/${_currentQuestions.length}',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 已答数量
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '已答 ${_answers.length}',
              style:
                  const TextStyle(fontSize: 20, color: AppTheme.successColor),
            ),
          ),
          const SizedBox(width: 12),
          // 考试倒计时（如果有时间限制）
          if (_examTimeLimit > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _examRemainingSeconds <= 300
                    ? Colors.red.withAlpha(26)
                    : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer,
                    size: 24,
                    color: _examRemainingSeconds <= 300
                        ? Colors.red
                        : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '剩余 ${_formatTime(_examRemainingSeconds)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _examRemainingSeconds <= 300
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // 下一题/提交
          if (_currentQuestionIndex < _currentQuestions.length - 1)
            GestureDetector(
              onTap: () {
                if (_typingStarted && !_typingFinished && !_typingPaused) {
                  _pauseInlineTyping();
                }
                setState(() => _currentQuestionIndex++);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('下一题',
                        style: TextStyle(fontSize: 21, color: Colors.white)),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 27, color: Colors.white),
                  ],
                ),
              ),
            )
          else
            // 提交按钮
            GestureDetector(
              onTap: (_isSubmitting || !_canSubmitExam) ? null : _submitExam,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: !_canSubmitExam
                      ? Colors.grey[400]
                      : AppTheme.successColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !_canSubmitExam
                          ? _earlySubmitMinutes > 0
                              ? '$_earlySubmitMinutes 分钟后可交卷'
                              : '等待时间结束'
                          : '提交',
                      style: TextStyle(fontSize: 21, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.check, size: 27, color: Colors.white),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 题型标签
  Widget _buildQuestionTypeTag(Map<String, dynamic> question) {
    String typeName;
    IconData typeIcon;
    Color typeColor;

    switch (question['type']) {
      case 'choice':
        typeName = '选择题';
        typeIcon = Icons.check_box_outlined;
        typeColor = Colors.blue;
        break;
      case 'matching':
        typeName = '连线题';
        typeIcon = Icons.compare_arrows;
        typeColor = Colors.orange;
        break;
      case 'sequential':
        typeName = '顺序题';
        typeIcon = Icons.sort;
        typeColor = Colors.green;
        break;
      case 'typing':
        typeName = '打字题';
        typeIcon = Icons.keyboard;
        typeColor = Colors.purple;
        break;
      case 'operation':
        typeName = '操作题';
        typeIcon = Icons.computer;
        typeColor = Colors.cyan;
        break;
      default:
        typeName = '未知题型';
        typeIcon = Icons.help_outline;
        typeColor = Colors.grey;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: typeColor.withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(typeIcon, size: 16, color: typeColor),
              const SizedBox(width: 4),
              Text(
                typeName,
                style: TextStyle(
                  fontSize: 12,
                  color: typeColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 题目卡片
  Widget _buildQuestionCard(Map<String, dynamic> question) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withAlpha(26),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题型标签
          _buildQuestionTypeTag(question),
          const SizedBox(height: 16),
          // 题目内容
          _buildQuestionContent(question),
        ],
      ),
    );
  }

  /// 左侧题目导航
  Widget _buildQuestionNav() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选择题- 有题目才显示
          if (_choiceQuestions.isNotEmpty) ...[
            _buildTypeSection('选择', 'choice', _choiceQuestions, Colors.blue),
            const SizedBox(height: 8),
          ],
          // 连线题- 有题目才显示
          if (_matchingQuestions.isNotEmpty) ...[
            _buildTypeSection(
                '连线', 'matching', _matchingQuestions, Colors.orange),
            const SizedBox(height: 8),
          ],
          // 顺序题- 有题目才显示
          if (_sequentialQuestions.isNotEmpty) ...[
            _buildTypeSection(
                '顺序', 'sequential', _sequentialQuestions, Colors.green),
            const SizedBox(height: 8),
          ],
          // 打字题- 有题目才显示
          if (_typingQuestions.isNotEmpty) ...[
            _buildTypeSection('打字', 'typing', _typingQuestions, Colors.purple),
            const SizedBox(height: 8),
          ],
          // 操作题- 有题目才显示
          if (_operationQuestions.isNotEmpty) ...[
            _buildTypeSection(
                '操作', 'operation', _operationQuestions, Colors.cyan),
          ],
        ],
      ),
    );
  }

  /// 题型分组
  Widget _buildTypeSection(
      String label, String type, List questions, Color color) {
    final isSelected = _selectedQuestionType == type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题型标题
        GestureDetector(
          onTap: () {
            if (!mounted) return;
            setState(() {
              _selectedQuestionType = type;
              _currentQuestions = [
                ..._choiceQuestions,
                ..._matchingQuestions,
                ..._sequentialQuestions,
                ..._typingQuestions,
              ];
              // 跳转到该题型的第一题（使用全局索引）
              _currentQuestionIndex = _getGlobalIndex(type, 0);
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withAlpha(26),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 题号列表 - 使用Wrap自适应排列
        if (questions.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(questions.length, (index) {
              // 计算全局索引
              int globalIndex = _getGlobalIndex(type, index);
              final isCurrent = globalIndex == _currentQuestionIndex;
              final isAnswered = _answers.containsKey(globalIndex);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedQuestionType = type;
                    _currentQuestionIndex = globalIndex;
                  });
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? color
                          : isAnswered
                              ? color.withAlpha(51)
                              : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCurrent
                            ? color
                            : isAnswered
                                ? color
                                : Colors.grey[300]!,
                        width: isCurrent ? 2 : 1,
                      ),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: color.withAlpha(77),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Colors.white
                              : isAnswered
                                  ? color
                                  : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  /// 获取题型在全局题目列表中的起始索引
  int _getGlobalIndex(String type, int localIndex) {
    if (type == 'choice') {
      return localIndex;
    } else if (type == 'matching') {
      return _choiceQuestions.length + localIndex;
    } else if (type == 'sequential') {
      return _choiceQuestions.length + _matchingQuestions.length + localIndex;
    } else if (type == 'typing') {
      return _choiceQuestions.length +
          _matchingQuestions.length +
          _sequentialQuestions.length +
          localIndex;
    } else if (type == 'operation') {
      return _choiceQuestions.length +
          _matchingQuestions.length +
          _sequentialQuestions.length +
          _typingQuestions.length +
          localIndex;
    }
    return localIndex;
  }

  /// 构建题目内容
  Widget _buildQuestionContent(Map<String, dynamic> question) {
    switch (question['type']) {
      case 'choice':
        return _buildChoiceQuestion(question);
      case 'matching':
        return _buildMatchingQuestion(question);
      case 'sequential':
        return _buildSequentialQuestion(question);
      case 'typing':
        return _buildTypingQuestion(question);
      case 'operation':
        return _buildOperationQuestion(question);
      default:
        return const Text('未知题型');
    }
  }
}
