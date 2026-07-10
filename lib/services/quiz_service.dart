import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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

  /// 初始化 - 从配置文件读取服务器 IP
  static Future<void> init() async {
    try {
      final configFile = File('student_config.json');
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
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return (data['data'] as List)
              .map((b) => b['name'].toString())
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
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true &&
            data['bank'] != null &&
            data['bank'] != '') {
          return data['bank'] as String;
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
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return (data['exam_time_limit'] as int?) ?? 30;
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
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return (data['early_submit_minutes'] as int?) ?? 25;
        }
      }
      return 25; // 默认25分钟
    } catch (e) {
      return 25; // 默认25分钟
    }
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
      final response = await _client
          .post(
            Uri.parse('$apiBaseUrl/sync-bank-files'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'bank': bankName}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        }
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
