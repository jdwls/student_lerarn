import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'wrong_questions_page.dart';

/// 答题结果页面
class ResultPage extends StatefulWidget {
  final int score;
  final int totalScore;
  final int correctCount;
  final int totalCount;
  final int elapsedSeconds;
  final List<Map<String, dynamic>> wrongQuestions;
  final Map<int, dynamic> userAnswers;

  /// 按题目类型统计的数据
  final Map<String, Map<String, dynamic>> typeStats;

  const ResultPage({
    super.key,
    required this.score,
    required this.totalScore,
    required this.correctCount,
    required this.totalCount,
    required this.elapsedSeconds,
    this.wrongQuestions = const [],
    this.userAnswers = const {},
    this.typeStats = const {},
  }) : assert(score >= 0, 'score不能为负数'),
       assert(totalScore > 0, 'totalScore必须大于0'),
       assert(correctCount >= 0, 'correctCount不能为负数'),
       assert(totalCount >= 0, 'totalCount不能为负数'),
       assert(elapsedSeconds >= 0, 'elapsedSeconds不能为负数'),
       assert(score <= totalScore, 'score不能超过totalScore'),
       assert(correctCount <= totalCount, 'correctCount不能超过totalCount');

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  @override
  void initState() {
    super.initState();
    // 重置窗口参数（操作题浮动窗口可能修改了窗口状态）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetWindowState();
    });
  }

  /// 重置窗口状态（恢复到进入小测前的窗口大小，非全屏）
  Future<void> _resetWindowState() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setMinimumSize(const Size(1280, 720));
      await windowManager.setAlignment(Alignment.center);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      // 退出全屏，恢复到进入小测前的窗口大小（1280x720）
      await windowManager.setFullScreen(false);
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
      debugPrint('ResultPage 窗口已恢复为正常大小');
    } catch (e) {
      debugPrint('ResultPage 窗口状态重置失败: $e');
    }
  }

  /// 格式化时间
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 返回主界面
  void _returnToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 获取题型显示名称
  String _getTypeName(String type) {
    switch (type) {
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
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    '答题完成',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '类型',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '正确',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '错误',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '分数',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...widget.typeStats.entries.map((entry) {
                          final typeName = _getTypeName(entry.key);
                          final value = entry.value;
                          int safeInt(dynamic v, int fallback) =>
                              v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
                          final correct = safeInt(value['correct'], 0);
                          final wrong = safeInt(value['wrong'], 0);
                          final score = safeInt(value['score'], 0);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey[200]!),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    typeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[800],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '$correct',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '$wrong',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.red[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '$score',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[800],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                            '得分', '${widget.score}/${widget.totalScore}'),
                        Container(
                            width: 1, height: 40, color: Colors.grey[200]),
                        _buildStatItem(
                            '用时', _formatTime(widget.elapsedSeconds)),
                        Container(
                            width: 1, height: 40, color: Colors.grey[200]),
                        _buildStatItem('正确率',
                            '${widget.totalCount > 0 ? ((widget.correctCount / widget.totalCount) * 100).round() : 0}%'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      if (widget.wrongQuestions.isNotEmpty)
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => WrongQuestionsPage(
                                      wrongQuestions: widget.wrongQuestions,
                                      userAnswers: widget.userAnswers,
                                    ),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.book_outlined, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    '错题本 (${widget.wrongQuestions.length})',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.wrongQuestions.isNotEmpty)
                        const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _returnToHome,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '返回主界面',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}