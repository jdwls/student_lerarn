part of 'quiz_page.dart';

/// Operation question handler mixin
mixin _OperationHandlerMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// Build operation question UI
  Widget _buildOperationQuestion(Map<String, dynamic> question) {
    final answer =
        _quizState._answers[_quizState._currentQuestionIndex] as Map?;
    final bool isCompleted = answer != null;
    final initialFiles = question['initialFiles'] as List<dynamic>? ?? [];
    final answers = question['answers'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question description
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            question['questionText'] ?? '',
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'SimHei'),
          ),
        ),
        const SizedBox(height: 24),

        // Hint text
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.cyan.withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.computer, size: 16, color: Colors.cyan[700]),
              const SizedBox(width: 6),
              Text(
                '点击下方按钮开始操作',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.cyan[700],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Initial files info
        if (initialFiles.isNotEmpty) ...[
          Text(
            '初始文件：',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: initialFiles.map<Widget>((file) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withAlpha(77)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file,
                        size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 4),
                    Text(
                      file['fileName'] ?? '',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Answer checks info
        if (answers.isNotEmpty) ...[
          Text(
            '答案检查点：',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 8),
          Column(
            children: answers.map<Widget>((ans) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withAlpha(77)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '文件：${ans['targetPath'] ?? ''}',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${ans['score'] ?? 5} 分',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Completion status
        if (isCompleted) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withAlpha(77)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  '操作已完成，得分：${answer['score'] ?? 0} 分',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Start/restart button
        Center(
          child: ElevatedButton.icon(
            onPressed: () => _startOperation(question, initialFiles, answers),
            icon:
                Icon(isCompleted ? Icons.refresh : Icons.play_arrow, size: 18),
            label: Text(isCompleted ? '重新操作' : '开始操作'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isCompleted ? Colors.orange : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
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

    // Step 2: Write initial files to virtual drive BEFORE opening Explorer
    if (driveLetter != null && initialFiles.isNotEmpty) {
      try {
        // Convert initial files to the format expected by VhdService.writeInitialFiles
        // Provide bankPath so writeInitialFiles can find source files in the correct subfolder
        final bankPath = '${AppPath.informationDir}${Platform.pathSeparator}${_quizState._selectedBank}${Platform.pathSeparator}操作题';
        final writeFiles = initialFiles.map<Map<String, dynamic>>((f) {
          final filePath = f['filePath'] ?? '';
          return {
            'fileName': f['fileName'] ?? '',
            'content': f['content'] ?? '',
            'filePath': filePath,
            'bankPath': bankPath,
          };
        }).toList();
        await VhdService.writeInitialFiles(writeFiles);
        debugPrint(
            'Initial files written to virtual drive $driveLetter: ${writeFiles.length} files');
      } catch (e) {
        debugPrint('Write initial files to virtual drive failed: $e');
      }
    }

    // Step 3: Exit fullscreen and resize to small window FIRST
    try {
      await _quizState._exitFullScreen();
      // Temporarily remove minimum size constraint
      await windowManager.setMinimumSize(const Size(1, 1));
      // Set transparent background
      await windowManager.setBackgroundColor(Colors.transparent);
      // Set small window size and position (right 0%)
      await windowManager.setSize(Size(420, 500));
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

    // Step 4: Open Explorer AFTER window operations, with a small delay for stability
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
    final initialFiles = _quizState._currentOperationInitialFiles ?? [];
    final answers = _quizState._currentOperationAnswers ?? [];

    // Return directly without Scaffold (window fits content exactly)
    // Use no rounded corners to avoid gaps between window border and rounded corners
    return Container(
      width: 420,
      height: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD6DBE8)),
      ),
      child: Column(
        children: [
          // Title bar with drag handle (using original GestureDetector, not flickering)
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
                    // Back button
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
              ), // Material
            ), // Container
          ), // GestureDetector
          // Content area
          Expanded(
            child:
                _buildOperationOverlayContent(question, initialFiles, answers),
          ),
        ],
      ),
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
      // Restore background
      await windowManager.setBackgroundColor(Colors.white);
      // 恢复到进入小测前的状态（全屏）
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

  /// Build operation overlay content (replaces OperationQuestionPanel)
  Widget _buildOperationOverlayContent(
    Map<String, dynamic> question,
    List<dynamic> initialFiles,
    List<dynamic> answers,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              question['questionText'] ?? '',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          // Drive info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withAlpha(77)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_open, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      '虚拟驱动器：${VhdService.mountDrive ?? "未挂载"}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final driveLetter = VhdService.mountDrive;
                    if (driveLetter != null) {
                      try {
                        await Process.run('explorer', [driveLetter]);
                      } catch (e) {
                        debugPrint('Open explorer failed: $e');
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('在资源管理器中打开'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Initial files
          if (initialFiles.isNotEmpty) ...[
            Text(
              '初始文件：',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800]),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: initialFiles.map<Widget>((f) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(26),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.withAlpha(77)),
                  ),
                  child: Text(
                    f['fileName'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Answer checks
          if (answers.isNotEmpty) ...[
            Text(
              '答案检查点：',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800]),
            ),
            const SizedBox(height: 8),
            ...answers.map((a) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(26),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.withAlpha(77)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green[700]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${a['targetPath'] ?? ''}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.green[700]),
                      ),
                    ),
                    Text(
                      '${a['score'] ?? 5} 分',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // Complete button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _closeOperationOverlay,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成并返回'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
            (_quizState as dynamic)._saveOperationFilesToLocal(
                _quizState._selectedBank!, operationFiles);
            debugPrint('Operation files resynced: ${operationFiles.length}');
            localFilesExist = true;
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
