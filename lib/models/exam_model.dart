class ExamModel {
  final String id;
  final String name;
  final String? description;
  final DateTime? examDate;
  final int? duration;
  final int? totalScore;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ExamModel({
    required this.id,
    required this.name,
    this.description,
    this.examDate,
    this.duration,
    this.totalScore,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory ExamModel.fromJson(Map<String, dynamic> json) {
    return ExamModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      examDate: json['exam_date'] != null
          ? DateTime.tryParse(json['exam_date'].toString())
          : null,
      duration: json['duration'] as int?,
      totalScore: json['total_score'] as int?,
      status: json['status']?.toString(),
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
      'name': name,
      'description': description,
      'exam_date': examDate?.toIso8601String(),
      'duration': duration,
      'total_score': totalScore,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
