import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_path.dart';

/// 课堂小测题库服务
/// 通过API获取教师端题库
class QuizService {
  // 后端API地址 - 从配置文件读取
  static String _serverIp = 'localhost';
  static const int _apiPort = 20020;
  static String get apiBaseUrl => 'http://$_serverIp:$_apiPort/api';
  static String get serverBaseUrl => 'http://$_serverIp:$_apiPort';

  /// 共享HTTP客户端（避免每次请求都创建新客户端）
  static final http.Client _client = http.Client();

  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _syncTimeout = Duration(seconds: 30);

  /// 初始化 - 从 AppPath.configFilePath 读取服务器 IP
  static Future<void> init() async {
    try {
      final configFile = File(AppPath.configFilePath);
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        _serverIp = data['server_ip'] ?? 'localhost';
        print('QuizService配置已加载: $_serverIp:$_apiPort');
      } else {
        print('QuizService: 未找到配置文件，使用默认值 localhost');
      }
    } catch (e) {
      print('QuizService: 读取配置文件失败，使用默认值: $e');
    }
  }

  /// 检查服务是否在线
  static Future<bool> checkServiceOnline() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$apiBaseUrl/health'),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取题库列表
  static Future<List<String>> getQuestionBanks() async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/question-banks'),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true && data['data'] is List) {
          return (data['data'] as List)
              .whereType<Map>()
              .map((b) => b['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 获取当前激活的题库
  static Future<String?> getActiveBank() async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/active-bank'),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true &&
            data['bank'] != null &&
            data['bank'] != '') {
          return data['bank']?.toString();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取考试时间限制（分钟）
  static Future<int> getExamTimeLimit() async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/exam-time-limit'),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final value = data['exam_time_limit'];
          return value is num
              ? value.toInt()
              : int.tryParse(value?.toString() ?? '') ?? 30;
        }
      }
      return 30; // 默认30分钟
    } catch (e) {
      return 30; // 默认30分钟
    }
  }

  /// 获取提前交卷时间（考试开始多少分钟后可交卷，分钟）
  static Future<int> getEarlySubmitMinutes() async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/early-submit-minutes'),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final value = data['early_submit_minutes'];
          return value is num
              ? value.toInt()
              : int.tryParse(value?.toString() ?? '') ?? 25;
        }
      }
      return 25; // 默认25分钟
    } catch (e) {
      return 25; // 默认25分钟
    }
  }

  /// 启动时消费小测待提交队列。
  static Future<void> drainPendingExamSubmissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('pending_submissions') ?? [];
      if (raw.isEmpty) return;
      final remaining = <String>[];
      for (final encoded in raw) {
        try {
          final data = json.decode(encoded);
          if (data is! Map) continue;
          final ok = await submitExam(
            studentId: data['studentId']?.toString() ?? '',
            studentName: data['studentName']?.toString() ?? '',
            bankName: data['bankName']?.toString() ?? '',
            answers: data['answers'] is Map
                ? Map<String, dynamic>.from(data['answers'] as Map)
                : {},
            score: data['score'] is num
                ? (data['score'] as num).toInt()
                : int.tryParse(data['score']?.toString() ?? '') ?? 0,
            classId: data['classId']?.toString() ?? '',
            questionsDetail: data['questionsDetail'] is List
                ? (data['questionsDetail'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
                : [],
          );
          if (!ok) remaining.add(encoded);
        } catch (_) {
          remaining.add(encoded);
        }
      }
      await prefs.setStringList('pending_submissions', remaining);
    } catch (_) {}
  }

  /// 获取题库内容
  static Future<Map<String, dynamic>?> getQuestionBank(String bankName) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$apiBaseUrl/question-banks/$bankName'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 提交答题结果（含错题详情）
  static Future<bool> submitExam({
    required String studentId,
    required String studentName,
    required String bankName,
    required Map<String, dynamic> answers,
    required int score,
    required String classId,
    required List<Map<String, dynamic>> questionsDetail,
  }) async {
    try {
      final url = '$apiBaseUrl/exam/submit';
      final body = json.encode({
        'student_id': studentId,
        'student_name': studentName,
        'bank_name': bankName,
        'answers': answers,
        'score': score,
        'class_id': classId,
        'questions_detail': questionsDetail,
      });
      print('submitExam: POST $url');
      print('submitExam: body length = ${body.length}');
      final response = await _client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      print('submitExam: statusCode = ${response.statusCode}');
      print('submitExam: response = ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('submitExam 异常: $e');
      return false;
    }
  }

  /// 同步题库文件（题库JSON + 操作题文件夹）
  /// 教师端主动调用，将题库文件传输到学生端
  static Future<Map<String, dynamic>?> syncBankFiles(String bankName) async {
    try {
      print('syncBankFiles: 请求同步题库 $bankName');
      final response = await _client
          .post(
            Uri.parse('$apiBaseUrl/sync-bank-files'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'bank': bankName}),
          )
          .timeout(_syncTimeout);

      print('syncBankFiles: 状态码 ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        }
        print('syncBankFiles: success=false, error=${data['error']}');
      } else {
        print('syncBankFiles: 响应体 ${response.body}');
      }
      return null;
    } catch (e) {
      print('syncBankFiles 异常: $e');
      return null;
    }
  }

  /// 获取学生答题记录
  static Future<List<Map<String, dynamic>>> getExamResults(
      String studentId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$apiBaseUrl/exam/results/$studentId'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
