import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 虚拟驱动器管理服务
/// 负责虚拟驱动器（subst）的挂载、卸载、文件写入和答案检查
class VhdService {
  static String? _mountDrive;
  static bool _isMounted = false;

  /// 当前挂载的驱动器盘符（如 "Z:"）
  static String? get mountDrive => _mountDrive;

  /// 是否已挂载
  static bool get isMounted => _isMounted;

  /// 清理所有 subst 虚拟驱动器
  static Future<void> cleanupAllSubstDrives() async {
    try {
      // 只解除本服务自己记录的盘符，不能卸载系统中其他应用的 subst 映射。
      if (_mountDrive != null) {
        await Process.run('subst', ['$_mountDrive', '/d']);
      }
      _mountDrive = null;
      _isMounted = false;
    } catch (e) {
      _mountDrive = null;
      _isMounted = false;
    }
  }

  /// 挂载路径为虚拟驱动器
  static Future<String?> mountPath(String path) async {
    try {
      // 验证路径是否存在
      if (!Directory(path).existsSync()) {
        print('VhdService: path does not exist: $path');
        return null;
      }

      // 先清理旧挂载
      await cleanupAllSubstDrives();

      // 查找可用盘符（从 Z: 倒序查找）
      for (int i = 90; i >= 68; i--) {
        final drive = String.fromCharCode(i);
        final driveLetter = '$drive:';
        // 跳过实际存在的物理/逻辑盘符
        if (Directory('$driveLetter\\').existsSync()) continue;

        final result = await Process.run('subst', [driveLetter, path]);
        if (result.exitCode == 0) {
          _mountDrive = driveLetter;
          _isMounted = true;
          print('VhdService: mounted $driveLetter -> $path');
          return _mountDrive;
        }
      }
      print('VhdService: no available drive letter for $path');
    } catch (e) {
      print('VhdService: mountPath error: $e');
    }
    return null;
  }

  /// 挂载 subst 驱动器
  static Future<String?> mountSubstDrive({String? questionId}) async {
    if (questionId == null) return null;
    return mountPath(questionId);
  }

  /// 创建并挂载 VHD 虚拟硬盘（桩方法）
  static Future<String?> createAndMountVhd({String? questionId, int sizeMB = 100}) async {
    // TODO: 实现 VHD 创建与挂载逻辑
    return null;
  }

  /// 规范化并校验操作题相对路径，拒绝绝对路径和路径遍历。
  static String? _safeRelativePath(String rawPath) {
    if (rawPath.isEmpty || rawPath.codeUnits.contains(0)) return null;
    var result = rawPath.replaceAll('/', Platform.pathSeparator);
    final keyPart = '${Platform.pathSeparator}操作题${Platform.pathSeparator}';
    final idx = result.indexOf(keyPart);
    if (idx >= 0) result = result.substring(idx + keyPart.length);
    if (result.startsWith(Platform.pathSeparator) ||
        RegExp(r'^[A-Za-z]:').hasMatch(result) ||
        result.startsWith('\\\\')) return null;
    final normalized = p.normalize(result);
    if (normalized.isEmpty || normalized == '.' || p.isAbsolute(normalized)) {
      return null;
    }
    final parts = normalized.split(Platform.pathSeparator);
    if (parts.any((part) => part.isEmpty || part == '..')) return null;
    return normalized;
  }

  static Future<String?> _safePathWithin(
      String rootPath, String relativePath) async {
    final relative = _safeRelativePath(relativePath);
    if (relative == null) return null;
    try {
      final root = p.normalize(await Directory(rootPath).resolveSymbolicLinks());
      final candidate = p.normalize(p.join(root, relative));
      final prefix = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      if (candidate != root && !candidate.startsWith(prefix)) return null;
      return candidate;
    } catch (_) {
      return null;
    }
  }

  /// 写入初始文件到虚拟驱动器
  static Future<bool> writeInitialFiles(List<Map<String, dynamic>> files) async {
    if (!_isMounted || _mountDrive == null) return false;
    try {
      for (final file in files) {
        final fileName = file['fileName'] as String? ?? '';
        final content = file['content'] as String?;
        final filePath = file['filePath'] as String?;
        final bankPath = file['bankPath'] as String?;

        if (fileName.isEmpty) continue;

        // 如果提供了 bankPath，从本地复制文件
        if (bankPath != null && filePath != null && filePath.isNotEmpty) {
          final normalizedFilePath = _safeRelativePath(filePath);
          if (normalizedFilePath == null) continue;
          final sourcePath = await _safePathWithin(bankPath, normalizedFilePath);
          final targetPath = await _safePathWithin(_mountDrive!, normalizedFilePath);
          if (sourcePath == null || targetPath == null) continue;
          final sourceFile = File(sourcePath);
          debugPrint('[writeFiles] 尝试复制: ${sourceFile.path}, exists=${await sourceFile.exists()}');
          if (await sourceFile.exists()) {
            final targetFile = File(targetPath);
            await targetFile.parent.create(recursive: true);
            await sourceFile.copy(targetFile.path);
            debugPrint('[writeFiles] 复制成功: ${sourceFile.path} -> ${targetFile.path}');
            continue;
          }
        }

        // 写入内容到虚拟驱动器（使用规范化后的相对路径，保留子目录结构）
        if (filePath != null && filePath.isNotEmpty) {
          final effectiveRelPath = _safeRelativePath(filePath);
          if (effectiveRelPath == null) continue;
          final targetPath = await _safePathWithin(_mountDrive!, effectiveRelPath);
          if (targetPath == null) continue;
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);
          if (content != null && content.isNotEmpty) {
            await targetFile.writeAsString(content);
          } else {
            await targetFile.writeAsString('');
          }
        } else {
          final effectiveRelPath = _safeRelativePath(fileName);
          if (effectiveRelPath == null) continue;
          final targetPath = await _safePathWithin(_mountDrive!, effectiveRelPath);
          if (targetPath == null) continue;
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);
          if (content != null && content.isNotEmpty) {
            await targetFile.writeAsString(content);
          } else {
            await targetFile.writeAsString('');
          }
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查操作题答案
  /// 逐行检查逻辑：
  /// - 读取指定行号的内容，与期望内容对比
  /// - 匹配则给分，不匹配不给分
  /// - 文件不存在直接 0 分
  static Future<Map<String, dynamic>> checkAnswersWithDetails(
    List<Map<String, dynamic>> answers,
  ) async {
    if (!_isMounted || _mountDrive == null) {
      debugPrint('[checkAnswers] 驱动器未挂载');
      return {'totalScore': 0, 'maxScore': 0, 'details': []};
    }

    int totalScore = 0;
    int maxScore = 0;
    final details = <Map<String, dynamic>>[];

    debugPrint('[checkAnswers] 开始批改, 共 ${answers.length} 个检查项, 驱动器: $_mountDrive');

    try {
      for (int ai = 0; ai < answers.length; ai++) {
        final answer = answers[ai];
        // 扁平结构：每个 answer 就是一个行检查项
        final rawTargetPath = answer['targetPath'] as String? ?? '';
        final lineNumber = answer['lineNumber'] as int? ?? 1;
        final expectedContent = answer['expectedContent'] as String? ?? '';
        final itemScore = answer['score'] as int? ?? 5;

        maxScore += itemScore;
        int earnedScore = 0;
        bool passed = true;

        // 规范化目标路径
        final targetPath = _safeRelativePath(rawTargetPath);
        debugPrint('[checkAnswers] 检查项 $ai: rawTargetPath="$rawTargetPath", normalizedPath="$targetPath", lineNumber=$lineNumber, expected="$expectedContent", score=$itemScore');

        if (targetPath != null && lineNumber > 0 && expectedContent.isNotEmpty) {
          // 逐行检查：读取指定行号的内容，与期望内容对比
          final fullPath = '$_mountDrive${Platform.pathSeparator}$targetPath';
          debugPrint('[checkAnswers]   行检查: 文件="$fullPath", 行号=$lineNumber, 期望="$expectedContent", 分值=$itemScore');

          final lineFile = File(fullPath);
          if (await lineFile.exists()) {
            try {
              final lineContent = await lineFile.readAsString();
              final lines = lineContent.split('\n');
              debugPrint('[checkAnswers]   文件内容共 ${lines.length} 行');
              if (lineNumber <= lines.length) {
                final actualLine = lines[lineNumber - 1];
                debugPrint('[checkAnswers]   第 $lineNumber 行内容: "${actualLine.replaceAll('\r', '\\r')}" (长度: ${actualLine.length})');
                debugPrint('[checkAnswers]   期望内容:   "$expectedContent" (长度: ${expectedContent.length})');
                if (actualLine.trimRight() == expectedContent.trimRight()) {
                  earnedScore = itemScore;
                  debugPrint('[checkAnswers]   => 行检查通过 +$itemScore');
                } else {
                  debugPrint('[checkAnswers]   => 行检查不匹配');
                }
              } else {
                debugPrint('[checkAnswers]   文件只有 ${lines.length} 行, 但需要的行号是 $lineNumber');
              }
            } catch (e) {
              debugPrint('[checkAnswers]   读取文件失败: $e');
            }
          } else {
            debugPrint('[checkAnswers]   文件不存在: $fullPath');
          }
        } else if (targetPath != null && targetPath.isNotEmpty) {
          // 没有行号/期望内容时，文件存在即得分
          final fullPath = '$_mountDrive${Platform.pathSeparator}$targetPath';
          debugPrint('[checkAnswers]   无行检查, 直接检查文件存在: $fullPath');
          final targetFile = File(fullPath);
          if (await targetFile.exists()) {
            earnedScore = itemScore;
            debugPrint('[checkAnswers]   文件存在, 得 $itemScore 分');
          } else {
            passed = false;
            debugPrint('[checkAnswers]   文件不存在');
          }
        }

        totalScore += earnedScore;
        details.add({
          'targetPath': targetPath ?? '',
          'passed': passed,
          'earnedScore': earnedScore,
          'maxScore': itemScore,
        });
        debugPrint('[checkAnswers]   检查项 $ai 结束: 得分=$earnedScore/$itemScore, passed=$passed');
      }
    } catch (e) {
      debugPrint('[checkAnswers] 批改方法异常: $e');
    }

    debugPrint('[checkAnswers] 批改完成: totalScore=$totalScore, maxScore=$maxScore');
    return {
      'totalScore': totalScore,
      'maxScore': maxScore,
      'details': details,
    };
  }

  /// 卸载并清理虚拟驱动器
  static Future<void> unmountAndCleanup() async {
    await cleanupAllSubstDrives();
  }

  /// 读取虚拟驱动器中的所有文件内容
  static Future<List<Map<String, dynamic>>> readAllFiles() async {
    if (!_isMounted || _mountDrive == null) return [];
    try {
      final files = <Map<String, dynamic>>[];
      final dir = Directory(_mountDrive!);
      if (!await dir.exists()) return files;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final content = await entity.readAsString();
          files.add({
            'path': entity.path,
            'fileName': entity.path.split(Platform.pathSeparator).last,
            'content': content,
          });
        }
      }
      return files;
    } catch (e) {
      return [];
    }
  }
}