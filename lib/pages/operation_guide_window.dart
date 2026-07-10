import 'dart:convert';
import 'package:flutter/material.dart';

/// 操作题提示窗口 - 在独立子窗口中显示操作题要求
class OperationGuideWindow extends StatefulWidget {
  final String questionText;
  final List<Map<String, dynamic>> initialFiles;
  final List<Map<String, dynamic>> answers;
  final String? driveLetter;
  final VoidCallback? onComplete;

  const OperationGuideWindow({
    super.key,
    required this.questionText,
    this.initialFiles = const [],
    this.answers = const [],
    this.driveLetter,
    this.onComplete,
  });

  @override
  State<OperationGuideWindow> createState() => _OperationGuideWindowState();

  /// 从 JSON 字符串解析参数（用于子窗口通信）
  static Map<String, dynamic> parseArgs(String jsonArgs) {
    try {
      return jsonDecode(jsonArgs) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// 将参数编码为 JSON 字符串（用于子窗口通信）
  static String encodeArgs({
    required String questionText,
    required List<Map<String, dynamic>> initialFiles,
    required List<Map<String, dynamic>> answers,
    String? driveLetter,
  }) {
    return jsonEncode({
      'questionText': questionText,
      'initialFiles': initialFiles,
      'answers': answers,
      'driveLetter': driveLetter,
    });
  }
}

class _OperationGuideWindowState extends State<OperationGuideWindow> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.computer, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '操作题要求',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const Spacer(),
                    if (widget.driveLetter != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(26),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '磁盘: ${widget.driveLetter}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 题目说明
              if (widget.questionText.isNotEmpty) ...[
                const Text(
                  '题目说明：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    widget.questionText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 初始文件列表
              if (widget.initialFiles.isNotEmpty) ...[
                const Text(
                  '初始文件：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.initialFiles.map((file) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(26),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withAlpha(77)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.insert_drive_file,
                              size: 14, color: Colors.blue[700]),
                          const SizedBox(width: 4),
                          Text(
                            file['fileName'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // 检查项
              if (widget.answers.isNotEmpty) ...[
                const Text(
                  '检查项：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.answers.length,
                    itemBuilder: (context, index) {
                      final ans = widget.answers[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(13),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withAlpha(51)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 14, color: Colors.green[700]),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '文件: ${ans['targetPath'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              '${ans['score'] ?? 5} 分',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 完成操作按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (widget.onComplete != null) {
                      widget.onComplete!();
                    }
                    // 关闭窗口
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('完成操作，返回答题'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
