class QuestionModel {
  final String id;
  final String content;
  final String? type;
  final String? options;
  final String? correctAnswer;
  final int? score;
  final String? difficulty;
  final String? chapter;
  final String? analysis;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  QuestionModel({
    required this.id,
    required this.content,
    this.type,
    this.options,
    this.correctAnswer,
    this.score,
    this.difficulty,
    this.chapter,
    this.analysis,
    this.createdAt,
    this.updatedAt,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id']?.toString() ?? '',
      content:
          json['content']?.toString() ?? json['question']?.toString() ?? '',
      type: json['type']?.toString(),
      options: json['options']?.toString(),
      correctAnswer:
          json['correct_answer']?.toString() ?? json['answer']?.toString(),
      score: json['score'] as int?,
      difficulty: json['difficulty']?.toString(),
      chapter: json['chapter']?.toString(),
      analysis: json['analysis']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'options': options,
      'correct_answer': correctAnswer,
      'score': score,
      'difficulty': difficulty,
      'chapter': chapter,
      'analysis': analysis,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // 解析选项为列表
  List<String> get optionsList {
    if (options == null || options!.isEmpty) return [];
    return options!.split('\n').where((o) => o.trim().isNotEmpty).toList();
  }
}
