part of 'quiz_page.dart';

/// 评分结果结构体
class _ScoreResult {
  final int totalScore;
  final int correctCount;
  final int totalCount;
  final List<Map<String, dynamic>> wrongQuestions;
  final Map<int, dynamic> userAnswers;
  final Map<String, Map<String, dynamic>> typeStats;

  _ScoreResult(this.totalScore, this.correctCount, this.totalCount,
      this.wrongQuestions, this.userAnswers, this.typeStats);
}

/// Scoring utils mixin - handles exam submission, scoring, and navigation
mixin _ScoringUtilsMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// 公共评分方法
  _ScoreResult _calculateScore() {
    int totalScore = 0;
    int correctCount = 0;
    int totalCount = _quizState._currentQuestions.length;
    final wrongQuestions = <Map<String, dynamic>>[];
    final userAnswers = <int, dynamic>{};
    final typeStats = <String, Map<String, dynamic>>{};

    final typeInitials = {
      'choice': '选择题',
      'matching': '连线题',
      'sequential': '顺序题',
      'typing': '打字题',
      'operation': '操作题',
    };

    // 惰性初始化：遇到未知题型时自动创建统计条目
    for (final key in typeInitials.values) {
      typeStats[key] = {'correct': 0, 'wrong': 0, 'score': 0};
    }

    for (int i = 0; i < _quizState._currentQuestions.length; i++) {
      final question = _quizState._currentQuestions[i];
      final answer = _quizState._answers[i];
      final questionScore = question['score'] as int? ?? 0;
      final type = question['type'] as String? ?? '';
      final typeName = typeInitials[type] ?? '未知题型';
      // 确保 typeStats 中有该题型的条目
      typeStats[typeName] ??= {'correct': 0, 'wrong': 0, 'score': 0};

      if (type == 'operation') {
        // 操作题：不管有没有作答，都使用实际批改得分
        final operationScore =
            (answer is Map ? answer['score'] : null) as int? ?? 0;
        totalScore += operationScore;
        typeStats[typeName]!['score'] =
            (typeStats[typeName]!['score'] as int? ?? 0) + operationScore;
        if (operationScore > 0) {
          typeStats[typeName]!['correct'] =
              (typeStats[typeName]!['correct'] as int? ?? 0) + 1;
          correctCount++;
        } else {
          typeStats[typeName]!['wrong'] =
              (typeStats[typeName]!['wrong'] as int? ?? 0) + 1;
        }
        if (answer != null) {
          userAnswers[i] = answer;
        }
      } else if (answer != null) {
        userAnswers[i] = answer;
        final isCorrect = _isAnswerCorrect(question, answer);
        if (isCorrect) {
          totalScore += questionScore;
          correctCount++;
          typeStats[typeName]!['correct'] =
              (typeStats[typeName]!['correct'] as int? ?? 0) + 1;
          typeStats[typeName]!['score'] =
              (typeStats[typeName]!['score'] as int? ?? 0) + questionScore;
        } else {
          typeStats[typeName]!['wrong'] =
              (typeStats[typeName]!['wrong'] as int? ?? 0) + 1;
          wrongQuestions.add({
            'index': i,
            'number': question['number'] ?? '${i + 1}',
            'type': type,
            'questionText': question['questionText'] ?? '',
            'correctAnswer': question['answer'],
            'userAnswer': answer,
            'score': questionScore,
          });
        }
      }
    }
    return _ScoreResult(totalScore, correctCount, totalCount, wrongQuestions,
        userAnswers, typeStats);
  }

  /// 本地保存提交数据，用于失败时重试
  Future<void> _savePendingSubmission(
      int totalScore,
      Map<String, dynamic> answers,
      List<Map<String, dynamic>> questionsDetail,
      String classId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_submissions') ?? [];
      pending.add(json.encode({
        'studentId': _quizState.widget.studentId,
        'studentName': _quizState.widget.studentName,
        'bankName': _quizState._selectedBank ?? '',
        'classId': classId,
        'score': totalScore,
        'answers': answers,
        'questionsDetail': questionsDetail,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      await prefs.setStringList('pending_submissions', pending);
      debugPrint('提交已保存到本地，待稍后重试');
    } catch (e) {
      debugPrint('保存待提交数据失败: $e');
    }
  }

  /// 批改所有未批改的操作题（提交前调用）
  Future<void> _gradeAllOperationQuestions() async {
    if (!VhdService.isMounted) {
      debugPrint('[批改] 批量批改跳过: 驱动器未挂载');
      return;
    }

    for (int i = 0; i < _quizState._currentQuestions.length; i++) {
      final question = _quizState._currentQuestions[i];
      if (question['type'] != 'operation') continue;

      // 每次提交前重新批改，不信任本地缓存中的 score 字段

      // 获取该题目的检查点
      final answers = question['answers'] as List<dynamic>? ?? [];
      if (answers.isEmpty) {
        debugPrint('[批改] 操作题 $i 没有检查点，跳过');
        continue;
      }

      try {
        final checkResult = await VhdService.checkAnswersWithDetails(
          answers
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
        );
        final operationScore = checkResult['totalScore'] as int? ?? 0;

        _quizState._answers[i] = {
          'score': operationScore,
          'completed': true,
        };
        debugPrint('[批改] 提交前批量批改操作题 $i: score=$operationScore');
      } catch (e) {
        debugPrint('[批改] 操作题 $i 批改异常: $e');
        // 批改异常时记为0分
        _quizState._answers[i] = {
          'score': 0,
          'completed': true,
        };
      }
    }
  }

  /// Submit exam
  Future<void> _submitExam() async {
    if (!_quizState._canSubmitExam || _quizState._isSubmitting) return;

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认提交'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要提交吗？'),
            const SizedBox(height: 8),
            Text(
              '已答 ${_quizState._answers.length}/${_quizState._currentQuestions.length} 题',
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              '用时：${_quizState._formatTime(_quizState._elapsedSeconds)}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _quizState.setState(() => _quizState._isSubmitting = true);

    try {
      // 提交前批改所有未批改的操作题
      await _gradeAllOperationQuestions();
      if (!_quizState.mounted) return;
      final result = _calculateScore();
      final answers = _convertAnswersForJson();
      final questionsDetail = _buildQuestionsDetail();

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final classId = authProvider.currentUser?.classId ?? '';

      final success = await QuizService.submitExam(
        studentId: _quizState.widget.studentId,
        studentName: _quizState.widget.studentName,
        bankName: _quizState._selectedBank ?? '',
        answers: answers,
        score: result.totalScore,
        classId: classId,
        questionsDetail: questionsDetail,
      );

      if (!success) {
        await _savePendingSubmission(
            result.totalScore, answers, questionsDetail, classId);
      }

      // 提交后清理虚拟磁盘
      await _cleanupVirtualDriveAfterSubmit();

      if (_quizState.mounted) {
        _navigateToResult(
            result.totalScore,
            result.correctCount,
            result.totalCount,
            result.wrongQuestions,
            result.userAnswers,
            result.typeStats);
      }
    } catch (e) {
      debugPrint('Submit failed: $e');
      if (_quizState.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('提交失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (_quizState.mounted) {
        _quizState.setState(() => _quizState._isSubmitting = false);
      }
    }
  }

  /// 提交后清理虚拟磁盘（卸载 subst 虚拟驱动器）并恢复窗口
  Future<void> _cleanupVirtualDriveAfterSubmit() async {
    // 停止窗口状态监控
    _quizState._stopWindowCheck();
    // 卸载并清理虚拟驱动器
    try {
      await VhdService.unmountAndCleanup();
      debugPrint('提交后虚拟磁盘已清理');
    } catch (e) {
      debugPrint('提交后清理虚拟磁盘失败: $e');
    }
    // 恢复窗口状态（如果操作题浮动窗口还在，重置窗口参数）
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setMinimumSize(const Size(1280, 720));
      await windowManager.setAlignment(Alignment.center);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } catch (e) {
      debugPrint('提交后恢复窗口状态失败: $e');
    }
  }

  /// Auto-submit when time runs out
  Future<void> _autoSubmitExam() async {
    debugPrint('Time\'s up, auto-submitting...');
    if (_quizState._isSubmitting) return;

    _quizState.setState(() => _quizState._isSubmitting = true);

    try {
      // 提交前批改所有未批改的操作题
      await _gradeAllOperationQuestions();
      if (!_quizState.mounted) return;
      final result = _calculateScore();
      final answers = _convertAnswersForJson();
      final questionsDetail = _buildQuestionsDetail();

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final classId = authProvider.currentUser?.classId ?? '';

      final success = await QuizService.submitExam(
        studentId: _quizState.widget.studentId,
        studentName: _quizState.widget.studentName,
        bankName: _quizState._selectedBank ?? '',
        answers: answers,
        score: result.totalScore,
        classId: classId,
        questionsDetail: questionsDetail,
      );

      if (!success) {
        await _savePendingSubmission(
            result.totalScore, answers, questionsDetail, classId);
      }

      // 自动提交后清理虚拟磁盘
      await _cleanupVirtualDriveAfterSubmit();

      if (_quizState.mounted) {
        _navigateToResult(
            result.totalScore,
            result.correctCount,
            result.totalCount,
            result.wrongQuestions,
            result.userAnswers,
            result.typeStats);
      }
    } catch (e) {
      debugPrint('Auto-submit failed: $e');
      if (_quizState.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('自动提交失败，请联系教师'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Navigate to result page
  void _navigateToResult(
    int totalScore,
    int correctCount,
    int totalCount,
    List<Map<String, dynamic>> wrongQuestions,
    Map<int, dynamic> userAnswers,
    Map<String, Map<String, dynamic>> typeStats,
  ) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultPage(
          score: totalScore,
          totalScore: _calculateMaxScore(),
          correctCount: correctCount,
          totalCount: totalCount,
          elapsedSeconds: _quizState._elapsedSeconds,
          wrongQuestions: wrongQuestions,
          userAnswers: userAnswers,
          typeStats: typeStats,
        ),
      ),
    );
  }

  /// Calculate maximum possible score
  int _calculateMaxScore() {
    int max = 0;
    for (final question in _quizState._currentQuestions) {
      max += question['score'] as int? ?? 0;
    }
    return max;
  }

  /// Check if answer is correct
  bool _isAnswerCorrect(Map<String, dynamic> question, dynamic answer) {
    switch (question['type']) {
      case 'choice':
        return answer == question['answer'];
      case 'matching':
        final rawCorrect = question['correctMapping'];
        final correctMapping = <String, String>{};
        if (rawCorrect is Map) {
          rawCorrect.forEach((key, value) {
            correctMapping[key.toString()] = value.toString();
          });
        }
        final userMapping = <String, String>{};
        if (answer is Map) {
          final hasStableMapping = answer['mapping'] is Map;
          final rawMapping =
              hasStableMapping ? answer['mapping'] as Map : answer;
          final items = question['items'] as List<dynamic>? ?? [];
          rawMapping.forEach((key, value) {
            if (hasStableMapping) {
              userMapping[key.toString()] = value.toString();
              return;
            }
            final leftIndex = int.tryParse(key.toString());
            final rightIndex = int.tryParse(value.toString());
            if (leftIndex != null &&
                rightIndex != null &&
                leftIndex >= 0 &&
                leftIndex < items.length &&
                rightIndex >= 0 &&
                rightIndex < items.length) {
              final leftId =
                  items[leftIndex]['leftId']?.toString() ?? '$leftIndex';
              final rightId =
                  items[rightIndex]['rightId']?.toString() ?? '$rightIndex';
              userMapping[leftId] = rightId;
            }
          });
        }
        if (correctMapping.length != userMapping.length) return false;
        for (final entry in correctMapping.entries) {
          if (userMapping[entry.key] != entry.value) return false;
        }
        return true;
      case 'sequential':
        final correct = (question['answer'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final userAnswer =
            (answer as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        if (correct.length != userAnswer.length) return false;
        for (int i = 0; i < correct.length; i++) {
          if (correct[i] != userAnswer[i]) return false;
        }
        return true;
      case 'typing':
        return (answer is Map) && answer.containsKey('score');
      case 'operation':
        // 操作题判断：必须是Map且得分大于0才算正确
        return answer is Map &&
            (answer['score'] is int
                    ? answer['score'] as int
                    : int.tryParse(answer['score']?.toString() ?? '0') ?? 0) >
                0;
      default:
        return false;
    }
  }

  /// Get question type text
  String _getQuestionTypeText(Map<String, dynamic> question) {
    switch (question['type']) {
      case 'choice':
        return '选择题';
      case 'matching':
        return '连线题';
      case 'sequential':
        return '顺序题';
      case 'typing':
        return '打字题';
      case 'operation':
        return '操作题';
      default:
        return '未知题型';
    }
  }

  /// Convert answers to JSON-friendly format
  Map<String, dynamic> _convertAnswersForJson() {
    final answers = <String, dynamic>{};
    for (int i = 0; i < _quizState._currentQuestions.length; i++) {
      final question = _quizState._currentQuestions[i];
      final answer = _quizState._answers[i];

      if (answer != null) {
        final type = question['type'] as String? ?? '';
        final number = question['number'] as String? ?? '${i + 1}';
        // 将 answer 中的 Map key 转换为 String，避免 JsonUnsupportedObjectError
        Object? jsonSafe = answer;
        if (answer is Map) {
          if (type == 'matching') {
            final stableMapping = <String, dynamic>{};
            final items = question['items'] as List<dynamic>? ?? [];
            answer.forEach((leftIndex, rightIndex) {
              final li = int.tryParse(leftIndex.toString());
              final ri = int.tryParse(rightIndex.toString());
              if (li != null &&
                  ri != null &&
                  li >= 0 &&
                  li < items.length &&
                  ri >= 0 &&
                  ri < items.length) {
                final leftId = items[li]['leftId']?.toString() ?? '$li';
                final rightId = items[ri]['rightId']?.toString() ?? '$ri';
                stableMapping[leftId] = rightId;
              }
            });
            jsonSafe = {
              'mapping': stableMapping,
              // 保留旧索引映射，兼容教师端旧版本。
              'index_mapping': answer.map((k, v) => MapEntry(k.toString(), v)),
            };
          } else {
            jsonSafe = answer.map((k, v) => MapEntry(k.toString(), v));
          }
        }
        answers[number.toString()] = {
          'type': type,
          'answer': jsonSafe,
          'correct': _isAnswerCorrect(question, answer),
        };
      }
    }
    return answers;
  }

  /// Build questions detail for result page
  List<Map<String, dynamic>> _buildQuestionsDetail() {
    final details = <Map<String, dynamic>>[];
    for (int i = 0; i < _quizState._currentQuestions.length; i++) {
      final question = _quizState._currentQuestions[i];
      final answer = _quizState._answers[i];
      final isCorrect = answer != null && _isAnswerCorrect(question, answer);

      // 操作题使用实际批改得分
      int earnedScore;
      if (question['type'] == 'operation' && answer is Map) {
        earnedScore = (answer['score'] as int? ?? 0);
      } else {
        earnedScore = isCorrect ? (question['score'] ?? 0) : 0;
      }

      details.add({
        'index': i,
        'number': question['number'] ?? '${i + 1}',
        'type': _getQuestionTypeText(question),
        'score': question['score'] ?? 0,
        'earnedScore': earnedScore,
        'isAnswered': answer != null,
        'isCorrect': isCorrect,
        'questionText': question['questionText'] ?? '',
      });
    }
    return details;
  }
}
