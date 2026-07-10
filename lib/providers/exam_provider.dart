import 'package:flutter/foundation.dart';
import '../models/exam_model.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';

class ExamProvider extends ChangeNotifier {
  final ApiService _apiService;
  List<ExamModel> _exams = [];
  ExamModel? _currentExam;
  List<QuestionModel> _questions = [];
  List<Map<String, dynamic>> _answers = [];
  int _currentQuestionIndex = 0;
  bool _isLoading = false;
  String? _error;
  bool _isFinished = false;

  ExamProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<ExamModel> get exams => _exams;
  ExamModel? get currentExam => _currentExam;
  List<QuestionModel> get questions => _questions;
  List<Map<String, dynamic>> get answers => _answers;
  int get currentQuestionIndex => _currentQuestionIndex;
  bool get isLoading => _isLoading;
  bool get isFinished => _isFinished;
  String? get error => _error;

  QuestionModel? get currentQuestion =>
      _questions.isNotEmpty && _currentQuestionIndex < _questions.length
          ? _questions[_currentQuestionIndex]
          : null;

  bool get hasNextQuestion => _currentQuestionIndex < _questions.length - 1;
  bool get hasPreviousQuestion => _currentQuestionIndex > 0;

  int get correctCount => _answers.where((a) => a['is_correct'] == true).length;
  int get totalQuestions => _questions.length;
  int get score =>
      totalQuestions > 0 ? ((correctCount / totalQuestions) * 100).round() : 0;

  Future<void> loadExams() async {
    // 延迟到下一个帧，避免在 build 阶段调用 notifyListeners
    await Future.delayed(const Duration(milliseconds: 1));

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/exams');
      if (response.containsKey('data')) {
        final List<dynamic> data = response['data'];
        _exams = data.map((json) => ExamModel.fromJson(json)).toList();
      }
    } catch (e) {
      // API失败时使用模拟数据
      _loadMockExams();
    }

    _isLoading = false;
    notifyListeners();
  }

  void _loadMockExams() {
    _exams = [
      ExamModel(
        id: '1',
        name: '数学小测',
        description: '初一数学第一章测试',
        duration: 300,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ExamModel(
        id: '2',
        name: '语文小测',
        description: '初一语文第一单元测试',
        duration: 300,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      ExamModel(
        id: '3',
        name: '英语小测',
        description: '初一英语第一单元测试',
        duration: 300,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];
  }

  Future<void> loadExamQuestions(String examId) async {
    _isLoading = true;
    _isFinished = false;
    _answers = [];
    _currentQuestionIndex = 0;
    notifyListeners();

    try {
      final response = await _apiService.get('/exams/$examId/questions');
      if (response.containsKey('data')) {
        final List<dynamic> data = response['data'];
        _questions = data.map((json) => QuestionModel.fromJson(json)).toList();
      }
    } catch (e) {
      // API失败时使用模拟题目
      _loadMockQuestions(examId);
    }

    _isLoading = false;
    notifyListeners();
  }

  void _loadMockQuestions(String examId) {
    if (examId == '1') {
      // 数学小测
      _questions = [
        QuestionModel(
          id: 'q1',
          content: '1 + 1 = ?',
          options: '1\n2\n3\n4',
          correctAnswer: '2',
          type: 'single',
        ),
        QuestionModel(
          id: 'q2',
          content: '5 × 3 = ?',
          options: '10\n12\n15\n18',
          correctAnswer: '15',
          type: 'single',
        ),
        QuestionModel(
          id: 'q3',
          content: '10 ÷ 2 = ?',
          options: '3\n4\n5\n6',
          correctAnswer: '5',
          type: 'single',
        ),
        QuestionModel(
          id: 'q4',
          content: '8 + 7 = ?',
          options: '13\n14\n15\n16',
          correctAnswer: '15',
          type: 'single',
        ),
        QuestionModel(
          id: 'q5',
          content: '20 - 8 = ?',
          options: '10\n11\n12\n13',
          correctAnswer: '12',
          type: 'single',
        ),
      ];
    } else if (examId == '2') {
      // 语文小测
      _questions = [
        QuestionModel(
          id: 'q1',
          content: '"春风又绿江南岸"的下一句是？',
          options: '明月何时照我还\n春风不度玉门关\n春眠不觉晓\n春江水暖鸭先知',
          correctAnswer: '明月何时照我还',
          type: 'single',
        ),
        QuestionModel(
          id: 'q2',
          content: '下列哪个是象形字？',
          options: '日\n江\n河\n湖',
          correctAnswer: '日',
          type: 'single',
        ),
        QuestionModel(
          id: 'q3',
          content: '"举头望明月"的上一句是？',
          options: '床前明月光\n疑是地上霜\n举头望明月\n低头思故乡',
          correctAnswer: '床前明月光',
          type: 'single',
        ),
        QuestionModel(
          id: 'q4',
          content: '汉字有多少个基本笔画？',
          options: '5\n8\n10\n12',
          correctAnswer: '8',
          type: 'single',
        ),
        QuestionModel(
          id: 'q5',
          content: '《静夜思》的作者是？',
          options: '杜甫\n李白\n白居易\n王维',
          correctAnswer: '李白',
          type: 'single',
        ),
      ];
    } else {
      // 英语小测
      _questions = [
        QuestionModel(
          id: 'q1',
          content: 'How do you say "你好" in English?',
          options: 'Hello\nGoodbye\nThank you\nYes',
          correctAnswer: 'Hello',
          type: 'single',
        ),
        QuestionModel(
          id: 'q2',
          content: 'What is the plural of "apple"?',
          options: 'Apples\nApple\nAppled\nAppleing',
          correctAnswer: 'Apples',
          type: 'single',
        ),
        QuestionModel(
          id: 'q3',
          content: 'Complete: "The quick brown ___ jumps over the lazy dog."',
          options: 'fox\ndog\ncat\nbird',
          correctAnswer: 'fox',
          type: 'single',
        ),
        QuestionModel(
          id: 'q4',
          content: 'Which word means "large"?',
          options: 'Big\nSmall\nShort\nTall',
          correctAnswer: 'Big',
          type: 'single',
        ),
        QuestionModel(
          id: 'q5',
          content: 'What is the opposite of "hot"?',
          options: 'Cold\nWarm\nCool\nWet',
          correctAnswer: 'Cold',
          type: 'single',
        ),
      ];
    }
  }

  void setCurrentExam(ExamModel exam) {
    _currentExam = exam;
    notifyListeners();
  }

  void answerQuestion(String answer) {
    if (currentQuestion == null) return;

    final isCorrect = answer == currentQuestion!.correctAnswer;
    _answers.add({
      'question_id': currentQuestion!.id,
      'answer': answer,
      'is_correct': isCorrect,
      'timestamp': DateTime.now(),
    });
    notifyListeners();
  }

  void nextQuestion() {
    if (hasNextQuestion) {
      _currentQuestionIndex++;
      notifyListeners();
    }
  }

  void previousQuestion() {
    if (hasPreviousQuestion) {
      _currentQuestionIndex--;
      notifyListeners();
    }
  }

  void goToQuestion(int index) {
    if (index >= 0 && index < _questions.length) {
      _currentQuestionIndex = index;
      notifyListeners();
    }
  }

  void submitExam() {
    _isFinished = true;
    notifyListeners();
  }

  void clearExam() {
    _currentExam = null;
    _questions = [];
    _answers = [];
    _currentQuestionIndex = 0;
    _isFinished = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
