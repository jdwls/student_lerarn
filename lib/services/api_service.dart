import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/app_path.dart';
import 'local_storage_service.dart';

class ApiService {
  // API 端口（写死）
  static const int _apiPort = 20020;

  // 从配置文件读取服务器 IP
  static String _serverIp = 'localhost';
  static String get baseUrl => 'http://$_serverIp:$_apiPort/api';

  // 教师端状态检查 URL
  static String get teacherUrl => 'http://$_serverIp:$_apiPort';

  // 使用静态单例Client，避免重复创建和关闭问题
  static final http.Client _sharedClient = http.Client();

  static const Duration _defaultTimeout = Duration(seconds: 10);

  // 暴露共享Client供直接使用
  http.Client get client => _sharedClient;

  /// 静态方法获取共享Client
  static http.Client getSharedClient() => _sharedClient;

  /// 初始化 - 从配置文件读取服务器 IP
  static Future<void> init() async {
    try {
      final configFile = File(AppPath.configFilePath);
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        _serverIp = data['server_ip'] ?? 'localhost';
        print('学生端配置已加载: $_serverIp:$_apiPort');
      } else {
        print('未找到配置文件 student_config.json，使用默认值 localhost');
      }
    } catch (e) {
      print('读取配置文件失败，使用默认值: $e');
    }
  }

  /// 启动时串行消费打字成绩待同步队列；成功后才移除记录。
  static Future<void> drainPendingTypingSubmissions() async {
    try {
      final storage = LocalStorageService.instance;
      // 与写入端共用同一文件锁，避免消费与新增成绩并发读写导致记录丢失
      await storage.withFileLock('pending_typing_submissions.json', () async {
        final pending =
            await storage.readJson('pending_typing_submissions.json');
        final raw = pending['submissions'];
        if (raw is! List || raw.isEmpty) return;

        final remaining = <Map<String, dynamic>>[];
        for (final entry in raw) {
          if (entry is! Map) continue;
          final payload = Map<String, dynamic>.from(entry);
          try {
            final response = await _sharedClient
                .post(
                  Uri.parse('$baseUrl/score/typing'),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode(payload),
                )
                .timeout(const Duration(seconds: 5));
            final data = response.statusCode == 200
                ? json.decode(response.body)
                : null;
            if (data is Map && data['success'] == true) continue;
          } catch (_) {
            // 保留记录，等待下一次启动或网络恢复时重试。
          }
          payload['retry_count'] =
              (payload['retry_count'] is num
                  ? (payload['retry_count'] as num).toInt()
                  : int.tryParse(payload['retry_count']?.toString() ?? '') ?? 0) +
              1;
          payload['last_retry_at'] = DateTime.now().toIso8601String();
          remaining.add(payload);
        }
        await storage.writeJson('pending_typing_submissions.json', {
          'submissions': remaining,
        });
      });
    } catch (_) {
      // 队列损坏或存储不可用时不影响正常启动。
    }
  }

  // 检查教师端是否在线
  Future<bool> checkTeacherActive() async {
    try {
      final response = await client.get(
        Uri.parse('$teacherUrl/api/teacher/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['active'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Map<String, String> _buildHeaders() {
    return {'Content-Type': 'application/json'};
  }

  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: _buildHeaders(),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('请求失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络错误: $e');
    }
  }

  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> data) async {
    try {
      // 检查是否是完整URL
      final url = endpoint.startsWith('http') ? endpoint : '$baseUrl$endpoint';

      final response = await client.post(
        Uri.parse(url),
        headers: _buildHeaders(),
        body: json.encode(data),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('请求失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络错误: $e');
    }
  }

  Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: _buildHeaders(),
        body: json.encode(data),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('请求失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络错误: $e');
    }
  }

  Future<bool> delete(String endpoint) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: _buildHeaders(),
      ).timeout(_defaultTimeout);

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      throw Exception('网络错误: $e');
    }
  }

  // ============ 积分兑换 API ============

  /// 获取积分兑换商品列表
  Future<Map<String, dynamic>> getPointsExchangeItems() async {
    try {
      final response = await client
          .get(
            Uri.parse('$baseUrl/points-exchange'),
            headers: _buildHeaders(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      }
      throw Exception('获取兑换商品失败');
    } catch (e) {
      throw Exception('网络错误: $e');
    }
  }

  /// 兑换商品
  Future<Map<String, dynamic>> redeemItem({
    required String studentId,
    required String studentName,
    required int itemId,
  }) async {
    try {
      final response = await client
          .post(
            Uri.parse('$baseUrl/points-exchange/redeem'),
            headers: _buildHeaders(),
            body: json.encode({
              'student_id': studentId,
              'student_name': studentName,
              'item_id': itemId,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? '兑换失败');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('网络错误: $e');
    }
  }
}
