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
        final operationScore = (answer is Map ? answer['score'] : null) as int? ?? 0;
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
      List<Map<String, dynamic>> questionsDetail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_submissions') ?? [];
      pending.add(json.encode({
        'studentId': _quizState.widget.studentId,
        'studentName': _quizState.widget.studentName,
        'bankName': _quizState._selectedBank ?? '',
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
            result.totalScore, answers, questionsDetail);
      }

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

  /// Auto-submit when time runs out
  Future<void> _autoSubmitExam() async {
    debugPrint('Time\'s up, auto-submitting...');
    if (_quizState._isSubmitting) return;

    _quizState.setState(() => _quizState._isSubmitting = true);

    try {
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
            result.totalScore, answers, questionsDetail);
      }

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
        final correctMapping =
            question['correctMapping'] as Map<dynamic, dynamic>? ?? {};
        final userMapping = answer as Map<dynamic, dynamic>? ?? {};
        if (correctMapping.length != userMapping.length) return false;
        for (final entry in correctMapping.entries) {
          if (userMapping[entry.key] != entry.value) return false;
        }
        return true;
      case 'sequential':
        final correct = question['answer'] as List<dynamic>? ?? [];
        final userAnswer = answer as List<dynamic>? ?? [];
        if (correct.length != userAnswer.length) return false;
        for (int i = 0; i < correct.length; i++) {
          if (correct[i] != userAnswer[i]) return false;
        }
        return true;
      case 'typing':
        return (answer is Map) && answer.containsKey('score');
      case 'operation':
        return answer is Map;
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
        answers[number.toString()] = {
          'type': type,
          'answer': answer,
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
