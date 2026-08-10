part of 'quiz_page.dart';

/// Operation question handler mixin
mixin _OperationHandlerMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  String? _safeContainedPath(String root, String relative) {
    final normalizedRoot = path.normalize(root);
    final candidate = path.normalize(path.join(normalizedRoot, relative));
    final prefix = normalizedRoot.endsWith(Platform.pathSeparator)
        ? normalizedRoot
        : '$normalizedRoot${Platform.pathSeparator}';
    if (candidate != normalizedRoot && !candidate.startsWith(prefix)) {
      return null;
    }
    return candidate;
  }


  Widget _buildOperationQuestion(Map<String, dynamic> question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question description with scale
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            question['questionText'] ?? '',
            style: TextStyle(
                fontSize: 26 * _quizState._contentScale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'SimHei'),
          ),
        ),
      ],
    );
  }

  /// Start operation question (resize window to small floating mode)
  Future<void> _startOperation(Map<String, dynamic> question,
      List<dynamic> initialFiles, List<dynamic> answers) async {
    // Save current question state
    _quizState.setState(() {
      _quizState._currentOperationQuestion = question;
      _quizState._currentOperationInitialFiles = initialFiles;
      _quizState._currentOperationAnswers = answers;
      _quizState._showingOperationOverlay = true;
    });

    // Step 1: Ensure virtual drive is mounted (try remount if not)
    String? driveLetter = VhdService.mountDrive;
    if (driveLetter == null) {
      debugPrint('Virtual drive not mounted, attempting mount...');
      if (_quizState._selectedBank != null) {
        final operationPath =
            '${AppPath.informationDir}${Platform.pathSeparator}${_quizState._selectedBank!}${Platform.pathSeparator}操作题';
        driveLetter = await VhdService.mountPath(operationPath);
        if (driveLetter != null) {
          debugPrint('Virtual drive mounted: $driveLetter');
          debugPrint('mountDrive after mount: ${VhdService.mountDrive}, isMounted: ${VhdService.isMounted}');
        } else {
          debugPrint('Virtual drive mount failed');
        }
      }
    }

    // Step 2: Exit fullscreen and resize to small window FIRST
    try {
      await _quizState._exitFullScreen();
      // Temporarily remove minimum size constraint
      await windowManager.setMinimumSize(const Size(350, 400));
      // Set transparent background
      await windowManager.setBackgroundColor(Colors.transparent);
      // Set small window size and position (right 0%)
      await windowManager.setSize(const Size(420, 500));
      // Place on right side of screen
      await windowManager.setAlignment(Alignment.centerRight);
      // Set always on top
      await windowManager.setAlwaysOnTop(true);
      // Ensure window is visible
      await windowManager.show();
      await windowManager.focus();
      // Start window state monitoring (Win+D recovery)
      _quizState._startWindowCheck();
      debugPrint('Window resized to small floating mode');
    } catch (e) {
      debugPrint('Resize window failed: $e');
    }

    // Step 3: Open Explorer AFTER window operations, with a small delay for stability
    if (driveLetter != null) {
      try {
        // Small delay to ensure subst mapping is stable after window operations
        await Future.delayed(const Duration(milliseconds: 300));
        await Process.run('explorer', [driveLetter]);
        debugPrint('Opening explorer: $driveLetter');
      } catch (e) {
        debugPrint('Open explorer failed: $e');
      }
    }
  }

  /// Build operation overlay window (small floating mode, no title bar)
  Widget _buildOperationOverlayWindow() {
    if (_quizState._currentOperationQuestion == null)
      return const SizedBox.shrink();

    final question = _quizState._currentOperationQuestion!;

    // Return directly without Scaffold (window fits content exactly)
    // Use no rounded corners to avoid gaps between window border and rounded corners
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD6DBE8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar with drag handle
              GestureDetector(
                onPanStart: (_) {
                  windowManager.startDragging();
                },
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2563EB),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        const Icon(Icons.computer, color: Colors.white, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '操作题 ${question['number'] ?? '1'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Back button (far right)
                        GestureDetector(
                          onTap: _closeOperationOverlay,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(51),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 4),
                                Text(
                                  '返回答题',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Content area (scrollable question text)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    question['questionText'] ?? '',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              // Bottom buttons
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  border: Border(
                    top: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // Refetch button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _refetchCurrentFileFromDocument(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重新获取', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Complete button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _closeOperationOverlay,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('完成并返回', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        },
      );
    }

  /// Close operation overlay
  void _closeOperationOverlay() async {
    // Stop window state monitoring
    _quizState._stopWindowCheck();

    // Check operation answers and calculate score
    int operationScore = 0;
    try {
      if (_quizState._currentOperationAnswers != null && VhdService.isMounted) {
        debugPrint('[批改] 开始批改操作题答案, answers=${_quizState._currentOperationAnswers!.length}条');
        final checkResult = await VhdService.checkAnswersWithDetails(
          _quizState._currentOperationAnswers!.cast<Map<String, dynamic>>(),
        );
        operationScore = checkResult['totalScore'] as int? ?? 0;
        debugPrint('[批改] 批改结果: totalScore=$operationScore, maxScore=${checkResult['maxScore']}');
        debugPrint('[批改] 批改详情: ${checkResult['details']}');
      } else {
        debugPrint('[批改] 批改跳过: isMounted=${VhdService.isMounted}, answers=${_quizState._currentOperationAnswers?.length}');
      }
    } catch (e) {
      debugPrint('[批改] 批改异常: $e');
    }

    // Restore window size and state
    try {
      // Remove always-on-top
      await windowManager.setAlwaysOnTop(false);
      // Restore background to transparent (same as main.dart init)
      await windowManager.setBackgroundColor(Colors.transparent);
      // Restore minimum size to normal (was set to 350x400 in _startOperation)
      await windowManager.setMinimumSize(const Size(1280, 720));
      // Restore alignment to default
      await windowManager.setAlignment(Alignment.center);
      // Restore hidden title bar style (student app uses TitleBarStyle.hidden)
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      // 恢复到全屏
      await windowManager.setFullScreen(true);
      debugPrint('Window restored to fullscreen');
    } catch (e) {
      debugPrint('Restore window failed: $e');
    }

    // Do not restore fullscreen, just keep window size
    // Restore main page
    _quizState.setState(() {
      _quizState._showingOperationOverlay = false;
      _quizState._currentOperationQuestion = null;
      _quizState._currentOperationInitialFiles = null;
      _quizState._currentOperationAnswers = null;
      _quizState._answers[_quizState._currentQuestionIndex] = {
        'score': operationScore,
        'completed': true,
      };
    });
  }

  /// 从 Documents/题库/{题库名称}/操作题/ 重新获取当前题目的操作题文件
  /// 复制到虚拟驱动器，覆盖原有文件
  Future<void> _refetchCurrentFileFromDocument() async {
    try {
      // 1. 获取题库名称
      final bankName = _quizState._selectedBank;
      if (bankName == null) {
        _showDialog('获取失败，请联系老师');
        return;
      }

      // 2. 获取用户文档目录路径
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isEmpty) {
        _showDialog('获取失败，请联系老师');
        return;
      }
      final documentOperationPath = '$userProfile\\Documents\\题库\\$bankName\\操作题';
      final docDir = Directory(documentOperationPath);
      if (!await docDir.exists()) {
        debugPrint('Document operation path not found: $documentOperationPath');
        _showDialog('获取失败，请联系老师');
        return;
      }

      // 3. 获取当前题目的初始文件列表
      final initialFiles = _quizState._currentOperationInitialFiles;
      if (initialFiles == null || initialFiles.isEmpty) {
        _showDialog('获取失败，请联系老师');
        return;
      }

      // 4. 获取虚拟驱动器盘符
      final driveLetter = VhdService.mountDrive;
      if (driveLetter == null) {
        _showDialog('获取失败，请联系老师');
        return;
      }

      int copiedCount = 0;

      // 5. 遍历所有初始文件，从 Documents 复制到虚拟驱动器
      for (final file in initialFiles) {
        final fileName = file['fileName'] ?? '';
        final filePath = file['filePath'] ?? '';

        if (fileName.isEmpty && filePath.isEmpty) continue;

        // 规范化 filePath：去除 "题库/{bankName}/操作题/" 前缀
        final normalizedPath = _DataLoaderMixin._normalizeOperationFilePath(filePath);
        final rawRelativePath = normalizedPath.isNotEmpty ? normalizedPath : fileName;

        // 安全校验：只接受相对路径，并在源、目标根目录内解析。
        final segments = rawRelativePath.replaceAll('\\', '/').split('/');
        if (segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
            RegExp(r'^[A-Za-z]:').hasMatch(rawRelativePath) ||
            rawRelativePath.startsWith('/') || rawRelativePath.startsWith('\\')) {
          debugPrint('警告: 拒绝非法操作题路径: $rawRelativePath');
          continue;
        }
        final relativePath = segments.join(Platform.pathSeparator);
        final sourceRoot = await docDir.resolveSymbolicLinks();
        final targetRoot = await Directory(driveLetter + Platform.pathSeparator)
            .resolveSymbolicLinks();
        final sourcePath = _safeContainedPath(sourceRoot, relativePath);
        final targetPath = _safeContainedPath(targetRoot, relativePath);
        if (sourcePath == null || targetPath == null) continue;

        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) {
          debugPrint('Source file not found: ${sourceFile.path}');
          continue;
        }

        // 目标路径：虚拟驱动器
        final targetFile = File('$driveLetter${Platform.pathSeparator}$relativePath');
        await targetFile.parent.create(recursive: true);
        await sourceFile.copy(targetFile.path);
        copiedCount++;
        debugPrint('Copied: ${sourceFile.path} -> ${targetFile.path}');
      }

      if (copiedCount > 0) {
        _showDialog('重新获取题目成功');
      } else {
        _showDialog('获取失败，请联系老师');
      }
    } catch (e) {
      debugPrint('Refetch file from document failed: $e');
      _showDialog('获取失败，请联系老师');
    }
  }

  /// 使用 showDialog 弹窗提示（小窗无 Scaffold，不能用 SnackBar）
  void _showDialog(String message) {
    if (_quizState.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  /// Refresh current operation question (only refreshes current question files, not all files)
  /// Includes robust checks: local file detection, server sync, drive mount, etc.
  void _refreshCurrentOperationQuestion() async {
    if (_quizState._selectedBank == null) return;
    if (_quizState._currentOperationInitialFiles == null ||
        _quizState._currentOperationInitialFiles!.isEmpty) {
      if (_quizState.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前题目没有初始文件'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    debugPrint('Refreshing current operation question...');

    try {
      // 统一使用 AppPath.informationDir（information/ 目录），与 _saveOperationFilesToLocal 保持一致
      final operationPath =
          '${AppPath.informationDir}${Platform.pathSeparator}${_quizState._selectedBank!}${Platform.pathSeparator}操作题';
      final operationDir = Directory(operationPath);

      // 1. Check if local operation folder exists
      bool localFilesExist = await operationDir.exists();
      if (!localFilesExist) {
        debugPrint(
            'Local operation folder not found, resyncing from server...');
        if (_quizState.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('操作文件未找到，正在从服务器同步...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Sync operation files from server
        final syncResult =
            await QuizService.syncBankFiles(_quizState._selectedBank!);
        if (syncResult != null) {
          final operationFiles =
              syncResult['operation_files'] as List<dynamic>? ?? [];
          if (operationFiles.isNotEmpty) {
            // Use _quizState cast to call _DataLoaderMixin method
            final saveSuccess = await (_quizState as dynamic)._saveOperationFilesToLocal(
                _quizState._selectedBank!, operationFiles);
            if (saveSuccess) {
              debugPrint('Operation files resynced: ${operationFiles.length}');
              localFilesExist = true;
            } else {
              debugPrint('操作题文件保存失败，重新同步失败');
              if (_quizState.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('操作题文件保存失败，请稍后重试'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          }
        }
      }

      // 2. Check if virtual drive is mounted
      bool vhdMounted = VhdService.isMounted;
      if (!vhdMounted && localFilesExist) {
        debugPrint('Operation drive not mounted, remounting...');
        if (_quizState.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('操作驱动器未挂载，正在重新挂载...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Remount virtual drive
        final driveLetter = await VhdService.mountPath(operationPath);
        if (driveLetter != null) {
          debugPrint('Operation drive remounted: $driveLetter');
          vhdMounted = true;
        } else {
          debugPrint('Operation drive remount failed');
          if (_quizState.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('驱动器挂载失败，请检查系统权限'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      // 3. Write current question initial files to virtual drive
      if (vhdMounted) {
        // 使用 AppPath.informationDir 作为 bankPath，与 _saveOperationFilesToLocal 保持一致
        final bankPath =
            '${AppPath.informationDir}${Platform.pathSeparator}${_quizState._selectedBank!}';
        final initialFiles = _quizState._currentOperationInitialFiles!
            .map((f) => <String, dynamic>{
                  'fileName': f['fileName'] ?? '',
                  'filePath': f['filePath'] ?? '',
                  'bankPath': bankPath,
                })
            .toList();
        await VhdService.writeInitialFiles(initialFiles);
        debugPrint('Current question initial files written to operation drive');
      }

      debugPrint('Current question refreshed');

      if (_quizState.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前题目已刷新'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Refresh current operation question exception: $e');
      if (_quizState.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
