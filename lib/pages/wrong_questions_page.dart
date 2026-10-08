import 'package:flutter/material.dart';
import '../services/window_mode_service.dart';

/// 错题本页面
class WrongQuestionsPage extends StatefulWidget {
  final List<Map<String, dynamic>> wrongQuestions;
  final Map<int, dynamic> userAnswers;

  const WrongQuestionsPage({
    super.key,
    required this.wrongQuestions,
    required this.userAnswers,
  });

  @override
  State<WrongQuestionsPage> createState() => _WrongQuestionsPageState();
}

class _WrongQuestionsPageState extends State<WrongQuestionsPage> {
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

  Future<void> _enterFullScreen() async {
    try {
      await WindowModeService.capturePreQuizState();
      await WindowModeService.enterQuizFullScreen();
    } catch (e) {
      debugPrint('进入全屏失败: $e');
    }
  }

  Future<void> _exitFullScreen() async {
    try {
      await WindowModeService.exitQuizFullScreen();
    } catch (e) {
      debugPrint('退出全屏失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '错题本',
            style: TextStyle(
              color: Colors.grey[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: widget.wrongQuestions.isEmpty
            ? _buildEmptyState()
            : _buildWrongQuestionsList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '没有错题',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '本次答题全部正确',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWrongQuestionsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.wrongQuestions.length,
      itemBuilder: (context, index) {
        final question = widget.wrongQuestions[index];
        final questionIndex = question['index'] is int
            ? question['index'] as int
            : int.tryParse(question['index']?.toString() ?? '0') ?? 0;
        final userAnswer = widget.userAnswers[questionIndex];
        final questionType = question['type'] as String? ?? 'choice';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 题号和题型标签
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '第${index + 1} 题',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getTypeColor(questionType).withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      question['typeText']?.toString() ?? '选择题',
                      style: TextStyle(
                        fontSize: 12,
                        color: _getTypeColor(questionType),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 根据题型显示不同内容
              _buildQuestionDetail(question, userAnswer, questionType),
            ],
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'choice':
        return Colors.blue;
      case 'matching':
        return Colors.orange;
      case 'sequential':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// 根据题型构建题目详情
  Widget _buildQuestionDetail(
      Map<String, dynamic> question, dynamic userAnswer, String questionType) {
    switch (questionType) {
      case 'choice':
        return _buildChoiceDetail(question, userAnswer);
      case 'matching':
        return _buildMatchingDetail(question, userAnswer);
      case 'sequential':
        return _buildSequentialDetail(question, userAnswer);
      default:
        return _buildSimpleDetail(question, userAnswer);
    }
  }

  /// 选择题详情
  Widget _buildChoiceDetail(Map<String, dynamic> question, dynamic userAnswer) {
    final content = question['content'] as String? ?? '';
    final optA = question['optionA'] as String? ?? '';
    final optB = question['optionB'] as String? ?? '';
    final optC = question['optionC'] as String? ?? '';
    final optD = question['optionD'] as String? ?? '';
    final selectedAnswer = userAnswer as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题干
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 选项
        _buildChoiceOption('A', optA, selectedAnswer == 'A'),
        const SizedBox(height: 8),
        _buildChoiceOption('B', optB, selectedAnswer == 'B'),
        const SizedBox(height: 8),
        _buildChoiceOption('C', optC, selectedAnswer == 'C'),
        const SizedBox(height: 8),
        _buildChoiceOption('D', optD, selectedAnswer == 'D'),
        const SizedBox(height: 16),
        // 你的答案
        _buildUserAnswerTag('你的答案: $selectedAnswer'),
      ],
    );
  }

  /// 构建选择题选项
  Widget _buildChoiceOption(String label, String text, bool isSelected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.red[300]! : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isSelected ? Colors.red : Colors.grey[300],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.red[700] : Colors.black87,
              ),
            ),
          ),
          if (isSelected) Icon(Icons.close, size: 18, color: Colors.red[400]),
        ],
      ),
    );
  }

  /// 连线题详情
  Widget _buildMatchingDetail(
      Map<String, dynamic> question, dynamic userAnswer) {
    final content = question['content'] as String? ?? '';
    final items = question['items'] as List? ?? [];
    final connections = (userAnswer as Map?)?.map(
          (k, v) => MapEntry(
              int.tryParse(k.toString()) ?? 0, int.tryParse(v.toString()) ?? 0),
        ) ??
        <int, int>{};

    // 连线配色方案
    const lineColors = [
      Color(0xFF2563EB),
      Color(0xFFF97316),
      Color(0xFF059669),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题干
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 连线区域
        _buildMatchingDisplay(items, connections, lineColors),
        const SizedBox(height: 16),
        // 你的连线
        _buildUserAnswerTag('你的连线: ${_formatMatchingAnswer(connections)}'),
      ],
    );
  }

  /// 构建连线题显示（带连线可视化）
  Widget _buildMatchingDisplay(
    List items,
    Map<int, int> connections,
    List<Color> lineColors,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // 左列
          Expanded(
            child: Column(
              children: List.generate(items.length, (idx) {
                final item = items[idx] is Map
                    ? items[idx] as Map
                    : <String, dynamic>{};
                final leftText = item['leftText']?.toString() ?? '';
                final isConnected = connections.containsKey(idx);
                final colorIndex = connections.keys.toList().indexOf(idx);
                final color = isConnected
                    ? lineColors[colorIndex % lineColors.length]
                    : Colors.grey[300] ?? Colors.grey;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: color, width: isConnected ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + idx),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          leftText,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          // 连线指示
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: List.generate(items.length, (index) {
                final isConnected = connections.containsKey(index);
                final colorIndex = connections.keys.toList().indexOf(index);
                final color = isConnected
                    ? lineColors[colorIndex % lineColors.length]
                    : Colors.grey[200];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Icon(
                    isConnected ? Icons.link : Icons.remove,
                    color: color,
                    size: 20,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          // 右列
          Expanded(
            child: Column(
              children: List.generate(items.length, (index) {
                final rightText = items[index]['rightText'] as String? ?? '';
                final isConnected = connections.containsValue(index);
                int? colorIndex;
                if (isConnected) {
                  final sortedKeys = connections.keys.toList()..sort();
                  for (int i = 0; i < sortedKeys.length; i++) {
                    if (connections[sortedKeys[i]] == index) {
                      colorIndex = i;
                      break;
                    }
                  }
                }
                final color = colorIndex != null
                    ? lineColors[colorIndex % lineColors.length]
                    : Colors.grey[300] ?? Colors.grey;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: color, width: isConnected ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rightText,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMatchingAnswer(Map<int, int> connections) {
    final sortedKeys = connections.keys.toList()..sort();
    return sortedKeys
        .map((k) => '${String.fromCharCode(65 + k)}→${connections[k]! + 1}')
        .join(', ');
  }

  /// 顺序题详情
  Widget _buildSequentialDetail(
      Map<String, dynamic> question, dynamic userAnswer) {
    final content = question['content'] as String? ?? '';
    final items = question['items'] as List? ?? [];
    final userOrder = (userAnswer as List?)
            ?.map((e) => int.tryParse(e.toString()) ?? 0)
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题干
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 选项列表（按你的顺序显示）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sort, size: 16, color: Colors.red[400]),
                  const SizedBox(width: 6),
                  Text(
                    '你的排列顺序',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 按用户顺序显示
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(userOrder.length, (index) {
                  final itemIndex = userOrder[index];
                  final item =
                      items.length > itemIndex ? items[itemIndex] : null;
                  final text = item?['text'] as String? ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 所有选项
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '原选项',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(items.length, (index) {
                  final text = items[index]['text'] as String? ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 简单详情（用于未知题型）
  Widget _buildSimpleDetail(Map<String, dynamic> question, dynamic userAnswer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            question['content'] as String? ?? '',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildUserAnswerTag('你的答案: ${_formatAnswer(userAnswer)}'),
      ],
    );
  }

  /// 构建用户答案标签
  Widget _buildUserAnswerTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.close, size: 18, color: Colors.red[400]),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.red[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAnswer(dynamic answer) {
    if (answer == null) return '未作答';
    if (answer is String) return answer;
    if (answer is List) {
      return answer.map((e) => e.toString()).join(' → ');
    }
    if (answer is Map) {
      return answer.entries.map((e) => '${e.key}→${e.value}').join(', ');
    }
    return answer.toString();
  }
}
