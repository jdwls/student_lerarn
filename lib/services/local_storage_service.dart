import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'quiz_service.dart';

/// 本地存储服务
/// 用于将题库保存到用户文档目录并加密
class LocalStorageService {
  static LocalStorageService? _instance;
  static LocalStorageService get instance => _instance ??= LocalStorageService._();

  LocalStorageService._();

  static const String _folderName = 'studentExam';

  /// 按文件名串行化读改写操作，避免并发读写同一文件导致数据丢失。
  /// key 通常是文件名；同一文件同时只有一个异步操作执行。
  final Map<String, Future<void>> _fileLocks = {};

  /// 在指定文件的锁内执行 action，串行化对该文件的访问。
  Future<T> withFileLock<T>(String key, Future<T> Function() action) async {
    final previous = _fileLocks[key];
    final current = Completer<void>();
    _fileLocks[key] = current.future;
    if (previous != null) {
      await previous.catchError((_) {});
    }
    try {
      return await action();
    } finally {
      if (!current.isCompleted) current.complete();
      if (identical(_fileLocks[key], current.future)) {
        _fileLocks.remove(key);
      }
    }
  }

  /// 获取题库本地存储根目录
  Future<String> get _basePath async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final basePath = p.join(documentsDir.path, _folderName);

    // 确保目录存在
    final dir = Directory(basePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return basePath;
  }

  /// 获取某个题库的目录
  Future<String> getBankPath(String bankName) async {
    final base = await _basePath;
    final bankPath = p.join(base, bankName);

    final dir = Directory(bankPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return bankPath;
  }

  /// 安全写入JSON文件（使用临时文件 + flush + 原子替换）
  Future<bool> _writeJsonSafely(
    String filePath,
    Map<String, dynamic> data, {
    bool isEncoded = false,
  }) async {
    try {
      final file = File(filePath);
      final tempFile = File('${file.path}.tmp');

      // 1. 写入临时文件
      String content;
      if (isEncoded) {
        // Base64 编码内容
        final jsonString = json.encode(data);
        content = base64Encode(utf8.encode(jsonString)).toString();
      } else {
        content = json.encode(data);
      }

      await tempFile.writeAsString(content, flush: true);

      // 2. 验证 JSON 格式（重新读取并解析）
      final readBack = await tempFile.readAsString();
      if (isEncoded) {
        json.decode(utf8.decode(base64Decode(readBack)));
      } else {
        json.decode(readBack);
      }

      // 3. 原子替换
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(filePath);

      return true;
    } catch (e) {
      print('安全写入JSON失败: $e');
      // 清理临时文件
      try {
        final tempFile = File('$filePath.tmp');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  /// 保存题库（Base64加密）
  Future<bool> saveQuestionBank(String bankName, Map<String, dynamic> data) async {
    try {
      final bankPath = await getBankPath(bankName);
      final file = File(p.join(bankPath, '题库.json'));
      return await _writeJsonSafely(file.path, data, isEncoded: true);
    } catch (e) {
      print('保存题库失败: $e');
      return false;
    }
  }

  /// 加载题库（Base64解码）
  Future<Map<String, dynamic>?> loadQuestionBank(String bankName) async {
    try {
      final bankPath = await getBankPath(bankName);
      final file = File(p.join(bankPath, '题库.json'));

      if (!file.existsSync()) {
        return null;
      }

      final encoded = await file.readAsString();
      final decoded = utf8.decode(base64Decode(encoded));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      print('加载题库失败: $e');
      return null;
    }
  }

  /// 检查题库是否存在
  Future<bool> hasQuestionBank(String bankName) async {
    final bankPath = await getBankPath(bankName);
    final file = File(p.join(bankPath, '题库.json'));
    return file.existsSync();
  }

  /// 获取图片本地目录
  Future<String> getImagePath(String bankName) async {
    final bankPath = await getBankPath(bankName);
    final imagePath = p.join(bankPath, '图片');

    final dir = Directory(imagePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return imagePath;
  }

  /// 保存图片到本地
  Future<String?> saveImage(String bankName, String imageName, List<int> bytes) async {
    try {
      final imagePath = await getImagePath(bankName);
      final file = File(p.join(imagePath, imageName));

      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      print('保存图片失败: $e');
      return null;
    }
  }

  /// 下载并保存远程图片
  Future<String?> downloadAndSaveImage(String bankName, String remoteUrl, String fileName) async {
    if (remoteUrl.isEmpty) return null;

    try {
      String fullUrl = remoteUrl;

      // 确保是有效的URL
      if (!remoteUrl.startsWith('http://') && !remoteUrl.startsWith('https://')) {
        // 相对路径，拼接服务器地址
        // 例如: "5/图片/题干_1_20260429_132256.jpg" -> "http://localhost:20020/files/5/图片/题干_1_20260429_132256.jpg"
        fullUrl = '${QuizService.serverBaseUrl}/files/$remoteUrl';
      }

      print('下载图片: $fullUrl');
      final response = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return await saveImage(bankName, fileName, response.bodyBytes);
      } else {
        print('图片下载失败，状态码: ${response.statusCode}');
      }
    } on TimeoutException {
      print('下载图片超时: $remoteUrl');
    } catch (e) {
      print('下载图片失败: $e');
    }
    return null;
  }

  /// 检查本地图片是否存在
  Future<bool> imageExists(String bankName, String imageName) async {
    final imagePath = await getImagePath(bankName);
    final file = File(p.join(imagePath, imageName));
    return file.existsSync();
  }

  /// 获取本地图片文件路径
  Future<String?> getLocalImageFilePath(String bankName, String imageName) async {
    final imagePath = await getImagePath(bankName);
    final file = File(p.join(imagePath, imageName));
    if (file.existsSync()) {
      return file.path;
    }
    return null;
  }

  /// 获取本地图片路径
  Future<String> getLocalImagePath(String bankName, String imageName) async {
    final imagePath = await getImagePath(bankName);
    return p.join(imagePath, imageName);
  }

  /// 获取题库列表（本地已缓存的）
  Future<List<String>> getLocalBanks() async {
    try {
      final base = await _basePath;
      final dir = Directory(base);

      if (!dir.existsSync()) {
        return [];
      }

      final banks = <String>[];
      for (final entity in dir.listSync()) {
        if (entity is Directory) {
          final file = File(p.join(entity.path, '题库.json'));
          if (file.existsSync()) {
            banks.add(p.basename(entity.path));
          }
        }
      }

      return banks;
    } catch (e) {
      print('获取本地题库列表失败: $e');
      return [];
    }
  }

  /// 删除本地题库
  Future<bool> deleteQuestionBank(String bankName) async {
    try {
      final bankPath = await getBankPath(bankName);
      final dir = Directory(bankPath);

      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      return true;
    } catch (e) {
      print('删除题库失败: $e');
      return false;
    }
  }

  // ============ 通用JSON读写方法 ============

  /// 读取JSON文件（串行化，避免并发读写冲突）
  Future<Map<String, dynamic>> readJson(String filename) async {
    return withFileLock('read_$filename', () async {
      try {
        final base = await _basePath;
        final file = File(p.join(base, filename));

        if (!file.existsSync()) {
          return {};
        }

        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      } catch (e) {
        return {};
      }
    });
  }

  /// 写入JSON文件（安全写入 + 串行化，返回bool表示成功/失败）
  Future<bool> writeJson(String filename, Map<String, dynamic> data) async {
    return withFileLock('write_$filename', () async {
      try {
        final base = await _basePath;
        final file = File(p.join(base, filename));
        return await _writeJsonSafely(file.path, data, isEncoded: false);
      } catch (e) {
        print('写入JSON失败: $e');
        return false;
      }
    });
  }

  /// 删除文件
  Future<void> deleteFile(String filename) async {
    try {
      final base = await _basePath;
      final file = File(p.join(base, filename));

      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      print('删除文件失败: $e');
    }
  }

  /// 检查文件是否存在
  Future<bool> fileExists(String filename) async {
    final base = await _basePath;
    final file = File(p.join(base, filename));
    return file.existsSync();
  }
}
