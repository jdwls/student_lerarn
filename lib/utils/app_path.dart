import 'dart:io';
import 'package:path/path.dart' as path;

/// 应用路径工具类
/// 解决打包后 Directory.current.path 返回工作目录而非exe目录的问题
///
/// 路径规则：
///   debug 模式（flutter run）：information -> <项目根>/student/information/
///   exe  模式（打包运行）：   information -> <exe目录>/information/
class AppPath {
  static String? _appRoot;
  static bool? _isDebugMode;

  /// 获取应用根目录
  static String get appRoot {
    if (_appRoot != null) return _appRoot!;
    _resolvePaths();
    return _appRoot!;
  }

  /// 是否为 debug 模式（flutter run 开发模式）
  static bool get isDebugMode {
    if (_isDebugMode == null) _resolvePaths();
    return _isDebugMode!;
  }

  /// information 目录路径
  /// debug 模式：<项目根>/student/information/
  /// exe   模式：<exe目录>/information/
  static String get informationDir {
    if (isDebugMode) {
      // debug 模式：appRoot 已经是 student/ 目录，直接拼接 information
      return path.join(appRoot, 'information');
    } else {
      return path.join(appRoot, 'information');
    }
  }

  /// 配置文件路径
  static String get configFilePath => path.join(appRoot, 'student_config.json');

  static void _resolvePaths() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    final workingDir = Directory.current.path;

    // ① debug 模式：工作目录有 pubspec.yaml 说明是 flutter run 开发模式
    if (File(path.join(workingDir, 'pubspec.yaml')).existsSync()) {
      _appRoot = workingDir;
      _isDebugMode = true;
      print('AppPath [debug] root: $_appRoot');
      return;
    }

    // ② exe 模式：exe 目录下存在 student_config.json
    if (File(path.join(exeDir, 'student_config.json')).existsSync()) {
      _appRoot = exeDir;
      _isDebugMode = false;
      print('AppPath [exe] root: $_appRoot');
      return;
    }

    // ③ 回退：使用工作目录
    _appRoot = workingDir;
    _isDebugMode = false;
    print('AppPath [fallback] root: $_appRoot');
  }
}
