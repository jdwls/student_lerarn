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
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  @override
  void initState() {
    super.initState();
    _enterFullScreen();
  }

  @override
  void dispose() {
    _exitFullScreen();
    super.dispose();
  }

  /// 进入全屏模式
  Future<void> _enterFullScreen() async {
    try {
      // 恢复窗口大小（清除小窗限制）
      await windowManager.maximize();
    } catch (e) {
      debugPrint('窗口最大化失败: $e');
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
    }
  }

  /// 格式化时间
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 获取主题色（基于得分率）
  Color _getThemeColor() {
    final percentage = widget.totalScore > 0
        ? (widget.score / widget.totalScore * 100).round()
        : 0;
    if (percentage >= 90) return const Color(0xFF22C55E);
    if (percentage >= 80) return const Color(0xFF3B82F6);
    if (percentage >= 60) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
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
                          final correct = entry.value['correct'] as int? ?? 0;
                          final wrong = entry.value['wrong'] as int? ?? 0;
                          final score = entry.value['score'] as int? ?? 0;
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
