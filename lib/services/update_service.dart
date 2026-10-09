import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'api_service.dart';
import 'socket_service.dart';
import '../utils/app_path.dart';

/// 更新信息
class UpdateInfo {
  final String version;
  final String fileName;
  final int fileSize;

  /// 安装包 MD5（为空表示教师端未提供，跳过校验）
  final String md5Hex;

  /// 是否强制更新（进度对话框不可取消）
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.fileName,
    required this.fileSize,
    this.md5Hex = '',
    this.forceUpdate = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      md5Hex: (json['md5'] ?? '').toString().trim(),
      forceUpdate: json['force_update'] == true,
    );
  }
}

/// 收集 MD5 分块计算结果（配合 md5.startChunkedConversion，避免整包读进内存）
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// 分块计算文件 MD5，返回小写十六进制字符串
Future<String> computeFileMd5(String filePath) async {
  final sink = _DigestSink();
  final input = md5.startChunkedConversion(sink);
  await for (final chunk in File(filePath).openRead()) {
    input.add(chunk);
  }
  input.close();
  return sink.value?.toString() ?? '';
}

/// 学生端在线升级服务
/// 负责检查更新、断点续传下载、静默替换安装
class UpdateService {
  static UpdateService? _instance;
  static UpdateService get instance => _instance ??= UpdateService._();

  /// 学生端当前版本（从 student_config.json 读取）
  static String _currentVersion = '1.0.0';

  Timer? _checkTimer;
  bool _isDownloading = false;
  bool _cancelRequested = false;

  /// 当前登录学生 ID（定时检查用）
  String? _studentId;

  /// 发现新版本时的回调（由页面负责下载安装）
  void Function(UpdateInfo info)? _onUpdateAvailable;

  static const Duration _checkInterval = Duration(minutes: 30);
  static const Duration _downloadTimeout = Duration(minutes: 10);

  UpdateService._();

  /// 学生端配置文件路径
  static String get _configPath => AppPath.configFilePath;

  /// 由 update.bat 在 exe 替换成功后写入的"待应用版本号"文件
  /// 只有替换成功才会写，避免"版本号变了但程序没换"
  static String get _pendingVersionPath => '${_configPath}.pending';

  /// 初始化：先应用上次安装留下的"待定版本号"，再读取当前版本
  static Future<void> init() async {
    await _applyPendingVersion();
    try {
      final configFile = File(_configPath);
      if (await configFile.exists()) {
        final data = json.decode(await configFile.readAsString())
            as Map<String, dynamic>;
        final version = data['version']?.toString() ?? '';
        if (version.isNotEmpty) {
          _currentVersion = version;
        }
        debugPrint('学生端在线升级: 当前版本=$_currentVersion');
      }
    } catch (e) {
      debugPrint('读取学生端版本配置失败: $e');
    }
  }

  /// 应用"待定版本号"文件（只有 exe 替换成功的 update.bat 才会写它）
  static Future<void> _applyPendingVersion() async {
    try {
      final pendingFile = File(_pendingVersionPath);
      if (!await pendingFile.exists()) return;

      final raw = (await pendingFile.readAsString()).trim();
      // 无论解析是否成功都删除，避免坏文件反复被读取
      await pendingFile.delete();
      if (raw.isEmpty) return;

      final version =
          (json.decode(raw) as Map<String, dynamic>)['version']?.toString() ??
              '';
      if (version.isEmpty) return;

      final configFile = File(_configPath);
      Map<String, dynamic> config = {};
      if (await configFile.exists()) {
        try {
          config = json.decode(await configFile.readAsString())
              as Map<String, dynamic>;
        } catch (_) {}
      }
      config['version'] = version;
      final tmp = File('${configFile.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
        flush: true,
      );
      await tmp.rename(configFile.path);
      _currentVersion = version;
      debugPrint('已应用待定版本号: $version');
    } catch (e) {
      debugPrint('应用待定版本号失败: $e');
    }
  }

  String get currentVersion => _currentVersion;

  /// 语义化版本比较：v1 > v2 返回 1，v1 < v2 返回 -1，相等返回 0
  /// 非数字段按 0 处理，长度不足补 0
  static int compareVersions(String v1, String v2) {
    final parts1 =
        v1.trim().split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 =
        v2.trim().split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    while (parts1.length < maxLen) {
      parts1.add(0);
    }
    while (parts2.length < maxLen) {
      parts2.add(0);
    }
    for (var i = 0; i < maxLen; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    return 0;
  }

  /// 开始定时检查更新（每 30 分钟一次）
  /// [onUpdateAvailable] 发现新版本时回调（由页面负责下载安装）
  void startPeriodicCheck(
    String studentId, {
    void Function(UpdateInfo info)? onUpdateAvailable,
  }) {
    _studentId = studentId;
    _onUpdateAvailable = onUpdateAvailable;
    _checkTimer?.cancel();
    // 立即检查由 checkNow() 触发，这里只负责定时，避免重复请求
    // 下载进行中跳过本轮检查：避免传输超过周期时二次弹窗误报"下载失败"
    _checkTimer = Timer.periodic(_checkInterval, (_) {
      if (_isDownloading) {
        debugPrint('更新下载进行中，跳过本轮定时检查');
        return;
      }
      checkNow();
    });
  }

  void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 立即检查一次；发现新版本时触发 startPeriodicCheck 注册的回调
  ///
  /// 考试进行中（socket 状态 = exam）暂停升级：不检查、不下载、不弹窗，
  /// 本轮直接跳过，等待下一个周期。
  Future<void> checkNow() async {
    if (SocketService.instance.currentStatus == 'exam') {
      debugPrint('考试进行中，跳过本轮更新检查');
      return;
    }
    final id = _studentId ?? '';
    final info = await checkForUpdate(id);
    if (info == null) return;
    _onUpdateAvailable?.call(info);
  }

  /// 检查更新（供外部调用）
  Future<UpdateInfo?> checkForUpdate(String studentId) async {
    return _checkForUpdate(studentId);
  }

  Future<UpdateInfo?> _checkForUpdate(String studentId) async {
    try {
      final apiService = ApiService();
      final response = await apiService.get(
          '/student-update/check?student_id=$studentId&current_version=$_currentVersion');

      if (response['success'] == true && response['update_available'] == true) {
        final versionData = response['version'] as Map<String, dynamic>?;
        if (versionData != null) {
          final info = UpdateInfo.fromJson(versionData);
          if (info.fileName.isEmpty) {
            debugPrint('检查更新：教师端未提供安装包文件名，跳过');
            return null;
          }
          // 客户端兜底：目标版本与当前版本完全一致才跳过（防抖动）。
          // 非"仅高于"判定：教师端目标版本与实际版本不一致即更新，含降级场景。
          if (info.version == _currentVersion) {
            debugPrint('检查更新：目标版本 ${info.version} 与当前版本一致，跳过');
            return null;
          }
          debugPrint('发现新版本: ${info.version}, 文件: ${info.fileName}');
          return info;
        }
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
    }
    return null;
  }

  /// 请求取消当前下载（下一个数据块到达时中止，已下载部分保留以便续传）
  void cancelDownload() {
    _cancelRequested = true;
  }

  /// 下载更新文件（断点续传）
  /// - 本地文件名带版本号，避免"同名不同包"被续传拼坏
  /// - 断点续传前校验已完成字节数（超过目标大小则删除重下）
  /// - 下载完成后按 file_size 做完整性校验
  ///
  /// 考试进行中禁止下载（可能因为回到首页触发回调）。
  Future<String?> downloadUpdate(
    UpdateInfo info, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (_isDownloading) return null;
    if (SocketService.instance.currentStatus == 'exam') {
      debugPrint('考试进行中，取消更新下载');
      return null;
    }
    _isDownloading = true;
    _cancelRequested = false;

    final fileName = info.fileName;
    final expectedSize = info.fileSize;
    // 本地用"版本号_原文件名"，换包（版本变了）就不会拼到旧文件上
    final localName = 'v${info.version}_$fileName';

    try {
      final tempDir = Directory.systemTemp;
      final updateDir = Directory(path.join(tempDir.path, 'student_update'));
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }
      final targetPath = path.join(updateDir.path, localName);
      final targetFile = File(targetPath);

      // 断点续传
      int resumeOffset = 0;
      if (await targetFile.exists()) {
        final existing = await targetFile.length();
        if (expectedSize > 0 && existing >= expectedSize) {
          // 已下载达到/超过目标大小 → 残包或旧包，删除重下
          debugPrint('本地已有文件大小 $existing 不小于目标 $expectedSize，删除后重新下载');
          await targetFile.delete();
          resumeOffset = 0;
        } else {
          resumeOffset = existing;
          debugPrint('发现本地已有部分文件: $resumeOffset 字节, 尝试断点续传');
        }
      }

      final client = http.Client();
      try {
        final request = http.Request(
          'GET',
          Uri.parse('${ApiService.baseUrl}/student-update/download/$fileName'),
        );
        if (resumeOffset > 0) {
          request.headers['Range'] = 'bytes=$resumeOffset-';
        }

        final streamedResponse =
            await client.send(request).timeout(_downloadTimeout);

        if (!(streamedResponse.statusCode == 200 ||
            streamedResponse.statusCode == 206)) {
          debugPrint('下载更新文件失败: HTTP ${streamedResponse.statusCode}');
          return null;
        }

        final totalLength = streamedResponse.contentLength ?? 0;
        final total = resumeOffset + totalLength;

        final randomAccessFile = await targetFile.open(mode: FileMode.append);
        int received = resumeOffset;
        try {
          await for (final chunk in streamedResponse.stream) {
            if (_cancelRequested) {
              // 保留已下载部分，下次可续传
              debugPrint('用户取消了更新下载（已接收 $received 字节）');
              return null;
            }
            await randomAccessFile.writeFrom(chunk);
            received += chunk.length;
            onProgress(received, total);
          }
          await randomAccessFile.flush();
        } finally {
          await randomAccessFile.close();
        }

        // 完整性校验：教师端提供了 file_size 时按大小校验
        if (expectedSize > 0 && received != expectedSize) {
          debugPrint('更新文件大小校验失败: 期望 $expectedSize 字节, 实际 $received 字节');
          try {
            await targetFile.delete();
          } catch (_) {}
          return null;
        }

        // MD5 校验：教师端提供了 md5 时逐块校验内容（防截断/篡改）
        final expectedMd5 = info.md5Hex.toLowerCase();
        if (expectedMd5.isNotEmpty) {
          final actualMd5 = await computeFileMd5(targetPath);
          if (actualMd5 != expectedMd5) {
            debugPrint('更新文件 MD5 校验失败: 期望 $expectedMd5, 实际 $actualMd5');
            try {
              await targetFile.delete();
            } catch (_) {}
            return null;
          }
          debugPrint('更新文件 MD5 校验通过: $actualMd5');
        }

        debugPrint('更新文件下载完成: $targetPath, 大小: $received 字节');
        return targetPath;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('下载更新文件异常: $e');
    } finally {
      _isDownloading = false;
    }
    return null;
  }

  /// 静默替换安装（整包覆盖）—— 由独立升级器 mini_updater.exe 完成
  ///
  /// 【为什么不能只换 exe】Flutter Windows 应用的 Dart 逻辑在 `data/app.so` 里，
  /// 主程序 exe 只是个几百 KB 的启动壳。只替换 exe 等于没有更新。
  /// 因此这里用发布方打好的 zip 整包覆盖整个安装目录，职责划分：
  ///   - Dart：下载、MD5 校验、本地缓存（本方法只负责"交棒"）
  ///   - mini_updater.exe（纯 Win32 C++，零依赖，源码在
  ///     student_online_update/mini_updater/）：等待主进程退出 → 备份 exe/data
  ///     → 解压 zip → 覆盖安装 → 校验 → 写待定版本号 → 重启/回滚
  ///
  /// 注意 1：必须"不等待"升级器结束——它会死等本进程退出，await 会互锁卡死。
  /// 注意 2：升级器被拷到 %TEMP%\student_update\ 下运行，安装目录（含它自己）
  ///         可以被无例外地整包覆盖，避免"运行中的 exe 无法被替换"。
  /// 注意 3：版本号由升级器在替换成功后写 [_pendingVersionPath]，下次启动由
  ///         [_applyPendingVersion] 应用，避免"版本号变了但程序没换"。
  /// 注意 4：只接受 .zip 整包；传 exe 会直接拒绝（否则会得到一个"假成功"）。
  Future<bool> silentInstall(
      String downloadedFilePath, String newVersion) async {
    try {
      // 0. 守卫：升级包必须是 zip 整包
      if (!downloadedFilePath.toLowerCase().endsWith('.zip')) {
        debugPrint('静默安装失败: 升级包必须是以 .zip 结尾的整包，实际为 $downloadedFilePath');
        return false;
      }

      // 1. 当前安装位置信息
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // 2. 定位升级器（正式位置在安装目录，随整包一起更新）
      final packExe = File(path.join(exeDir, 'mini_updater.exe'));
      if (!await packExe.exists()) {
        debugPrint('静默安装失败: 找不到升级器 ${packExe.path}');
        return false;
      }

      // 3. 拷到临时工作区再启动（见注意 2）
      final updateDir =
          Directory(path.join(Directory.systemTemp.path, 'student_update'));
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }
      final runtimeExe = File(path.join(updateDir.path, 'mini_updater.exe'));
      try {
        if (await runtimeExe.exists()) await runtimeExe.delete();
      } catch (_) {
        // 上一次升级器实例尚未完全退出时删除会失败 → 放弃本次安装，
        // 下次周期检查会重试（不影响当前程序运行）
        debugPrint('静默安装失败: 升级器文件被占用，稍后重试');
        return false;
      }
      await packExe.copy(runtimeExe.path);

      // 4. detached 启动（不走 shell），传参后立即返回；调用方随后退出进程触发替换
      await Process.start(
        runtimeExe.path,
        [
          '--pid=$pid',
          '--exe=$exePath',
          '--zip=$downloadedFilePath',
          '--version=$newVersion',
          '--pending=$_pendingVersionPath',
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      debugPrint('静默安装失败: $e');
      return false;
    }
  }

  void dispose() {
    stopPeriodicCheck();
  }
}
