part of 'quiz_page.dart';

/// Data loader mixin - handles question bank loading, parsing, and syncing
mixin _DataLoaderMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// Load list of available question banks
  Future<void> _loadQuestionBanks() async {
    _quizState.setState(() {
      _quizState._isLoading = true;
      _quizState._errorMessage = null;
    });

    try {
      // Get active bank from teacher
      final activeBank = await QuizService.getActiveBank();

      if (activeBank != null && activeBank.isNotEmpty) {
        // Active bank exists, load it automatically
        await _loadQuestionBank(activeBank);
      } else {
        // No active bank, show waiting prompt
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '等待教师发布题目...';
        });
      }
    } catch (e) {
      _quizState.setState(() {
        _quizState._isLoading = false;
        _quizState._errorMessage = '无法连接服务器：$e';
      });
    }
  }

  /// Load questions from a specific bank
  Future<void> _loadQuestionBank(String bankName) async {
    _quizState.setState(() {
      _quizState._isLoading = true;
      _quizState._errorMessage = null;
    });

    try {
      // 0. Clean up any residual subst drives before loading bank
      await VhdService.cleanupAllSubstDrives();

      // 1. Sync bank files from server (JSON + operation files)
      debugPrint('Starting sync bank: $bankName');
      final syncResult = await QuizService.syncBankFiles(bankName);

      if (syncResult == null) {
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '无法同步题库文件';
        });
        return;
      }

      // 2. Decode the JSON bank content (Base64 encoded)
      final bankContent = syncResult['bank_content'] as String?;
      if (bankContent == null) {
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '题库内容为空';
        });
        return;
      }

      final data = json.decode(bankContent) as Map<String, dynamic>;
      await LocalStorageService.instance.saveQuestionBank(bankName, data);
      debugPrint('Bank saved to local: $bankName');

      // 3. Save operation files to studentExam/$bankName/
      final operationFiles =
          syncResult['operation_files'] as List<dynamic>? ?? [];
      if (operationFiles.isNotEmpty) {
        await _saveOperationFilesToLocal(bankName, operationFiles);
        debugPrint('Operation files saved: ${operationFiles.length}');
      }

      // 4. Download and cache images
      await _downloadAndCacheImages(bankName, data);

      // 5. Parse questions
      final choiceQuestions = (data['choiceQuestions'] as List?)
              ?.map((q) => _parseChoiceQuestion(q as Map<String, dynamic>))
              .toList() ??
          [];

      final matchingQuestions = (data['matchingQuestions'] as List?)
              ?.map((q) => _parseMatchingQuestion(q as Map<String, dynamic>))
              .toList() ??
          [];

      final sequentialQuestions = (data['sequentialQuestions'] as List?)
              ?.map((q) => _parseSequentialQuestion(q as Map<String, dynamic>))
              .toList() ??
          [];

      final typingQuestions = (data['typingQuestions'] as List?)
              ?.map((q) => _parseTypingQuestion(q as Map<String, dynamic>))
              .toList() ??
          [];

      final operationQuestions = (data['operationQuestions'] as List?)
              ?.map((q) => _parseOperationQuestion(q as Map<String, dynamic>))
              .toList() ??
          [];

      // 6. If there are operation questions, mount virtual drive
      if (operationQuestions.isNotEmpty) {
        // Clean up existing subst drives
        await VhdService.cleanupAllSubstDrives();
        // Create virtual drive mapping from local files
        await _createVirtualDriveFromLocal(bankName);
      }

      // Shuffle question order server-side
      choiceQuestions.shuffle();
      matchingQuestions.shuffle();
      sequentialQuestions.shuffle();
      typingQuestions.shuffle();
      operationQuestions.shuffle();

      _quizState.setState(() {
        _quizState._selectedBank = bankName;
        _quizState._choiceQuestions = choiceQuestions;
        _quizState._matchingQuestions = matchingQuestions;
        _quizState._sequentialQuestions = sequentialQuestions;
        _quizState._typingQuestions = typingQuestions;
        _quizState._operationQuestions = operationQuestions;
        _quizState._currentQuestions = [
          ...choiceQuestions,
          ...matchingQuestions,
          ...sequentialQuestions,
          ...typingQuestions,
          ...operationQuestions,
        ];
        // Questions already shuffled, keep order unchanged
        _quizState._selectedQuestionType = 'all';
        _quizState._currentQuestionIndex = 0;
        _quizState._answers.clear();
        _quizState._elapsedSeconds = 0;
        _quizState._isLoading = false;
      });

      // Start timer
      _quizState._startTimer();

      // Get exam time limit and early submit settings
      final examTimeLimit = await QuizService.getExamTimeLimit();
      final earlySubmitMinutes = await QuizService.getEarlySubmitMinutes();
      if (examTimeLimit > 0) {
        _quizState.setState(() {
          _quizState._examTimeLimit = examTimeLimit;
          _quizState._examRemainingSeconds = examTimeLimit * 60;
          _quizState._earlySubmitMinutes = earlySubmitMinutes;
        });
        _startExamTimer();
      }
    } catch (e) {
      _quizState.setState(() {
        _quizState._isLoading = false;
        _quizState._errorMessage = '加载题库失败：$e';
      });
    }
  }

  /// Parse choice question (shuffle option order)
  /// Supports both Chinese keys (teacher storage format) and English keys
  Map<String, dynamic> _parseChoiceQuestion(Map<String, dynamic> q) {
    final items = q['items'] as List<dynamic>?;
    String questionText, questionImage, answer;
    int score;
    String optA, optB, optC, optD;
    String? imgA, imgB, imgC, imgD;

    if (items != null && items.isNotEmpty) {
      final item = items[0] as Map<String, dynamic>;
      // Chinese keys: 题干, 题干图片; English fallback: questionText, questionImage
      questionText = q['题干'] ?? q['questionText'] ?? '';
      questionImage = q['题干图片'] ?? q['questionImage'] ?? '';
      // Chinese keys inside items: 答案, 分值; English fallback: answer, score
      answer = item['答案'] ?? item['answer'] ?? '';
      score = int.tryParse(
              item['分值']?.toString() ?? item['score']?.toString() ?? '5') ??
          5;

      // Collect all options and their images
      final optionLabels = ['A', 'B', 'C', 'D'];
      final options = <Map<String, dynamic>>[];
      for (final label in optionLabels) {
        options.add({
          'label': label,
          // Chinese keys: 选项A/B/C/D; English fallback: optionA/B/C/D
          'text': item['选项$label'] ?? item['option$label'] ?? '',
          // Chinese keys: 图片A/B/C/D; English fallback: imageA/B/C/D
          'image': item['图片$label'] ?? item['image$label'],
        });
      }

      // Shuffle options
      options.shuffle();

      optA = options[0]['text'];
      optB = options[1]['text'];
      optC = options[2]['text'];
      optD = options[3]['text'];
      imgA = options[0]['image'];
      imgB = options[1]['image'];
      imgC = options[2]['image'];
      imgD = options[3]['image'];

      // Remap correct answer
      final newAnswerMap = <String, String>{
        'A': options[0]['label'],
        'B': options[1]['label'],
        'C': options[2]['label'],
        'D': options[3]['label'],
      };
      // Map original label to shuffled label
      String? newAnswer;
      for (final entry in newAnswerMap.entries) {
        if (entry.value == answer) {
          newAnswer = entry.key;
          break;
        }
      }
      answer = newAnswer ?? answer;
    } else {
      // Flat (non-nested) format with Chinese keys
      questionText = q['题干'] ?? q['questionText'] ?? '';
      questionImage = q['题干图片'] ?? q['questionImage'] ?? '';
      answer = q['答案'] ?? q['answer'] ?? '';
      score =
          int.tryParse(q['分值']?.toString() ?? q['score']?.toString() ?? '5') ??
              5;
      optA = q['选项A'] ?? q['optionA'] ?? '';
      optB = q['选项B'] ?? q['optionB'] ?? '';
      optC = q['选项C'] ?? q['optionC'] ?? '';
      optD = q['选项D'] ?? q['optionD'] ?? '';
      imgA = q['图片A'] ?? q['imageA'];
      imgB = q['图片B'] ?? q['imageB'];
      imgC = q['图片C'] ?? q['imageC'];
      imgD = q['图片D'] ?? q['imageD'];
    }

    return {
      'type': 'choice',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': questionText,
      'questionImage': questionImage,
      'optionA': optA,
      'optionB': optB,
      'optionC': optC,
      'optionD': optD,
      'imageA': imgA,
      'imageB': imgB,
      'imageC': imgC,
      'imageD': imgD,
      'answer': answer,
      'score': score,
    };
  }

  /// Parse matching question (shuffle left and right separately)
  /// Supports both Chinese keys (teacher storage format) and English keys
  Map<String, dynamic> _parseMatchingQuestion(Map<String, dynamic> q) {
    final rawItems = (q['items'] as List<dynamic>?) ?? [];

    // Collect left and right items with original indices
    final leftItems = <Map<String, dynamic>>[];
    final rightItems = <Map<String, dynamic>>[];
    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      // Chinese keys: 左侧内容, 左侧图片; English fallback: leftContent, leftText, leftImage
      leftItems.add({
        'text': item['左侧内容'] ?? item['leftContent'] ?? item['leftText'] ?? '',
        'image': item['左侧图片'] ?? item['leftImage'],
        'originalIndex': i,
      });
      // Chinese keys: 右侧内容, 右侧图片, 分值; English fallback: rightContent, rightText, rightImage, score
      rightItems.add({
        'text': item['右侧内容'] ?? item['rightContent'] ?? item['rightText'] ?? '',
        'image': item['右侧图片'] ?? item['rightImage'],
        'originalIndex': i,
        'score': int.tryParse(
                item['分值']?.toString() ?? item['score']?.toString() ?? '5') ??
            5,
      });
    }

    // Shuffle left and right separately
    leftItems.shuffle();
    rightItems.shuffle();

    // Build correct mapping: left index -> right index
    // Original correct: left[i] matched to right[i]
    // After shuffle: find right items share same originalIndex as left
    final correctMapping = <int, int>{}; // leftIndex -> rightIndex
    for (int li = 0; li < leftItems.length; li++) {
      final leftOrig = leftItems[li]['originalIndex'] as int;
      for (int ri = 0; ri < rightItems.length; ri++) {
        if (rightItems[ri]['originalIndex'] == leftOrig) {
          correctMapping[li] = ri;
          break;
        }
      }
    }

    // Build output items
    final items = <Map<String, dynamic>>[];
    for (int i = 0; i < leftItems.length; i++) {
      items.add({
        'leftText': leftItems[i]['text'],
        'rightText': rightItems[i]['text'],
        'leftImage': leftItems[i]['image'],
        'rightImage': rightItems[i]['image'],
        'score': rightItems[i]['score'],
      });
    }

    return {
      'type': 'matching',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      // Chinese keys: 题干, 题干图片; English fallback: questionText, questionImage
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'questionImage': q['题干图片'] ?? q['questionImage'],
      'items': items,
      'correctMapping': correctMapping, // left-to-right correct mapping
    };
  }

  /// Parse sequential question
  /// Supports both Chinese keys (teacher storage format) and English keys
  Map<String, dynamic> _parseSequentialQuestion(Map<String, dynamic> q) {
    final items = (q['items'] as List<dynamic>?)
        ?.map((item) => {
              // Chinese keys: 待排序项目, 项图片, 分值; English fallback: orderText, orderOption, optionImage, image, score
              'text': item['待排序项目'] ??
                  item['orderText'] ??
                  item['orderOption'] ??
                  '',
              'image': item['项图片'] ?? item['optionImage'] ?? item['image'],
              'score': int.tryParse(item['分值']?.toString() ??
                      item['score']?.toString() ??
                      '5') ??
                  5,
            })
        .toList();

    // Shuffle until order differs from correct answer (for safety, limit attempts)
    if (items != null && items.length > 1) {
      final correctOrder = (q['items'] as List<dynamic>?)
          ?.asMap()
          .entries
          .map((e) =>
              e.value['待排序项目'] ??
              e.value['orderText'] ??
              e.value['orderOption'] ??
              '')
          .toList();

      // Loop-shuffle until order is different from correct answer
      bool isCorrect = true;
      int maxAttempts = 100;
      while (isCorrect && maxAttempts > 0) {
        maxAttempts--;
        items.shuffle();
        // Check if matches correct order
        isCorrect = true;
        for (int i = 0; i < items.length; i++) {
          if (items[i]['text'] != correctOrder?[i]) {
            isCorrect = false;
            break;
          }
        }
      }
    }

    return {
      'type': 'sequential',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      // Chinese keys: 题干, 题干图片; English fallback: questionText, questionImage
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'questionImage': q['题干图片'] ?? q['questionImage'],
      'items': items ?? [],
      'answer': (q['items'] as List<dynamic>?)
          ?.asMap()
          .entries
          .map((e) =>
              e.value['待排序项目'] ??
              e.value['orderText'] ??
              e.value['orderOption'] ??
              '')
          .toList(),
    };
  }
/// Parse typing question
  /// Supports both Chinese keys (teacher storage format) and English keys
  Map<String, dynamic> _parseTypingQuestion(Map<String, dynamic> q) {
    return {
      'type': 'typing',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? q['参考文本'] ?? '',
      'typingType': q['打字类型'] ?? q['typingType'] ?? 'chinese',
      'referenceText': q['参考文本'] ?? q['referenceText'] ?? '',
      'timeLimit': q['时间限制'] ?? q['timeLimit'] ?? 5,
      'score': q['分值'] ?? q['score'] ?? 10,
    };
  }

  /// Parse operation question
  /// 初始文件每个条目直接包含检查信息：文件名、文件路径、行号、期望内容、分值
  Map<String, dynamic> _parseOperationQuestion(Map<String, dynamic> q) {
    final initialFileRaw = ((q['初始文件'] ?? q['initialFiles']) as List<dynamic>?)
            ?.map((f) => {
                  'fileName': f['文件名'] ?? f['fileName'] ?? '',
                  'filePath': f['文件路径'] ?? f['filePath'] ?? '',
                  'lineNumber': f['行号'] is int
                      ? f['行号']
                      : (int.tryParse(f['行号']?.toString() ?? '0') ?? 0),
                  'expectedContent':
                      f['期望内容'] ?? f['expectedContent'] ?? '',
                  'score': f['分值'] is int
                      ? f['分值']
                      : (int.tryParse(f['分值']?.toString() ?? '5') ?? 5),
                })
            .toList() ??
        [];

    // 从初始文件中提取有行检查信息的条目作为 answers
    final answers = initialFileRaw
        .where((f) =>
            (f['lineNumber'] as int? ?? 0) > 0 &&
            (f['expectedContent'] as String? ?? '').isNotEmpty)
        .map((f) => {
              'targetPath': f['filePath'] ?? '',
              'lineNumber': f['lineNumber'] ?? 1,
              'expectedContent': f['expectedContent'] ?? '',
              'score': f['score'] ?? 5,
            })
        .toList();

    return {
      'type': 'operation',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'score': q['分值'] ?? q['score'] ?? 10,
      'initialFiles': initialFileRaw,
      'answers': answers,
    };
  }

  /// Save operation files to local storage
  Future<void> _saveOperationFilesToLocal(
    String bankName,
    List<dynamic> operationFiles,
  ) async {
    try {
      final operationFolderPath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      final operationFolder = Directory(operationFolderPath);
      if (!await operationFolder.exists()) {
        await operationFolder.create(recursive: true);
      }

      for (final file in operationFiles) {
        final fileMap = file as Map<String, dynamic>;
        // Support both local format (fileName/filePath) and server format (path key)
        final fileName =
            fileMap['fileName'] as String? ?? fileMap['path'] as String? ?? '';
        final content = fileMap['content'] as String?;
        final filePath = fileMap['filePath'] as String?;

        if (fileName.isEmpty) continue;

        final targetPath =
            '$operationFolderPath${Platform.pathSeparator}$fileName';
        final targetFile = File(targetPath);
        final targetDir = targetFile.parent;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        if (content != null && content.isNotEmpty) {
          // Try to decode base64 content (server format), fallback to plain text
          try {
            final decoded = base64Decode(content);
            await targetFile.writeAsBytes(decoded);
            debugPrint('Writing operation file (base64 decoded): $targetPath');
          } catch (_) {
            // Not base64, write as plain text
            await targetFile.writeAsString(content);
            debugPrint('Writing operation file (plain text): $targetPath');
          }
        } else if (filePath != null && filePath.isNotEmpty) {
          final sourceFile = File(filePath);
          if (await sourceFile.exists()) {
            await sourceFile.copy(targetPath);
            debugPrint('Copying operation file: $filePath -> $targetPath');
          } else {
            await targetFile.writeAsString('');
            debugPrint('Creating empty operation file: $targetPath');
          }
        } else {
          await targetFile.writeAsString('');
          debugPrint('Creating empty operation file: $targetPath');
        }
      }
    } catch (e) {
      debugPrint('Save operation file failed: $e');
    }
  }

  /// Download and cache images
  Future<void> _downloadAndCacheImages(
      String bankName, Map<String, dynamic> data) async {
    try {
      final imageUrls = <String>[];
      final choiceQuestions = data['choiceQuestions'] as List<dynamic>? ?? [];
      for (final q in choiceQuestions) {
        final qMap = q as Map<String, dynamic>;
        // Chinese keys: 题干图片; English fallback: questionImage
        final questionImage = qMap['题干图片'] ?? qMap['questionImage'] ?? '';
        if (questionImage.isNotEmpty) {
          imageUrls.add(questionImage);
        }
        final items = qMap['items'] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          final item = items[0] as Map<String, dynamic>;
          for (final label in ['A', 'B', 'C', 'D']) {
            // Chinese keys: 图片A/B/C/D; English fallback: imageA/B/C/D
            final img = item['图片$label'] ?? item['image$label'];
            if (img != null && img.toString().isNotEmpty) {
              imageUrls.add(img.toString());
            }
          }
        }
      }

      if (imageUrls.isNotEmpty) {
        debugPrint('Downloading ${imageUrls.length} images...');
        final imageCacheDir = Directory(
            '${AppPath.informationDir}${Platform.pathSeparator}image_cache');
        if (!await imageCacheDir.exists()) {
          await imageCacheDir.create(recursive: true);
        }

        for (final url in imageUrls) {
          try {
            if (url.startsWith('C:') ||
                url.startsWith('D:') ||
                url.startsWith('/')) {
              continue;
            }
            final uri = Uri.parse(url);
            final fileName = uri.pathSegments.last;
            if (fileName.isEmpty) continue;

            final targetPath =
                '${imageCacheDir.path}${Platform.pathSeparator}$fileName';
            final targetFile = File(targetPath);
            if (await targetFile.exists()) continue;

            final httpClient = HttpClient();
            final request = await httpClient.getUrl(uri);
            final response = await request.close();
            if (response.statusCode == 200) {
              final bytes = <int>[];
              await for (final chunk in response) {
                bytes.addAll(chunk);
              }
              await targetFile.writeAsBytes(bytes);
              debugPrint('Downloaded image: $url -> $targetPath');
            }
            httpClient.close();
          } catch (e) {
            debugPrint('Download image failed $url: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Download cache image failed: $e');
    }
  }

  /// Create virtual drive from local operation files
  Future<void> _createVirtualDriveFromLocal(String bankName) async {
    try {
      final operationFolderPath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      final operationFolder = Directory(operationFolderPath);
      if (!await operationFolder.exists()) {
        await operationFolder.create(recursive: true);
        debugPrint('Created operation folder: $operationFolderPath');
      }

      // 挂载操作题文件夹到虚拟驱动器（mountPath 内部会先 clean）
      final drive = await VhdService.mountPath(operationFolderPath);
      if (drive != null) {
        debugPrint('Mapped operation drive: $drive -> $operationFolderPath');
      } else {
        debugPrint('Map operation drive failed');
      }
    } catch (e) {
      debugPrint('Create operation drive mapping exception: $e');
    }
  }

  /// 开始考试倒计时
  void _startExamTimer() {
    _quizState._examTimer?.cancel();
    _quizState._examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_quizState.mounted) return;
      _quizState.setState(() {
        _quizState._examRemainingSeconds--;
      });
      if (_quizState._examRemainingSeconds <= 0) {
        _quizState._examTimer?.cancel();
        if (!_quizState._isSubmitting) {
          _onExamTimeUp();
        }
      }
    });
  }

  /// 考试时间到处理
  void _onExamTimeUp() async {
    debugPrint('[时间到] _showingOperationOverlay=$_quizState._showingOperationOverlay');
    debugPrint('[时间到] mountDrive=${VhdService.mountDrive}, isMounted=${VhdService.isMounted}');
    debugPrint('[时间到] currentOperationAnswers=${_quizState._currentOperationAnswers?.length}条');
    debugPrint('[时间到] currentQuestionIndex=$_quizState._currentQuestionIndex');
    // 如果正在操作题小窗页面，先执行批改再关闭小窗
    if (_quizState._showingOperationOverlay) {
      int operationScore = 0;
      try {
        if (_quizState._currentOperationAnswers != null && VhdService.isMounted) {
          debugPrint('[自动提交] 操作题小窗中, 先批改');
          final checkResult = await VhdService.checkAnswersWithDetails(
            _quizState._currentOperationAnswers!.cast<Map<String, dynamic>>(),
          );
          operationScore = checkResult['totalScore'] as int? ?? 0;
        }
      } catch (e) {
        debugPrint('[自动提交] 批改异常: $e');
      }
      // 保存得分然后关闭小窗
      _quizState._stopWindowCheck();
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
      // 恢复窗口大小
      _restoreWindowAfterOperation();
      // 等待窗口恢复后再提交
      await Future.delayed(const Duration(milliseconds: 500));
      _quizState._autoSubmitExam();
    } else {
      _quizState._autoSubmitExam();
    }
  }

  /// 从操作题小窗恢复窗口（回到全屏状态）
  void _restoreWindowAfterOperation() {
    try {
      windowManager.setAlwaysOnTop(false);
      windowManager.setBackgroundColor(Colors.white);
      windowManager.setFullScreen(true);
    } catch (_) {}
  }

  /// 从初始文件列表中查找匹配的文件路径
  /// 例如: 检查项 target="脚本.txt" → 匹配到 initialFiles 中的 filePath="操作题/题目1/脚本.txt"
  Future<void> _copyOperationFolderToExam(String bankName) async {
    try {
      // Source folder: teacher's operation folder
      final sourcePath = 'teacher/exam/$bankName/operation';
      final sourceDir = Directory(sourcePath);

      // Check if source exists
      if (!await sourceDir.exists()) {
        debugPrint('Operation folder not found: $sourcePath');
        return;
      }

      // Target folder: studentExam/operation_$bankName
      final targetPath = '${AppPath.informationDir}/operation_$bankName';
      final targetDir = Directory(targetPath);

      // Remove if target already exists
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }

      // Create target folder
      await targetDir.create(recursive: true);

      // Recursively copy files
      await _copyDirectory(sourceDir, targetDir);

      debugPrint('Operation folder copied: $sourcePath -> $targetPath');
    } catch (e) {
      debugPrint('Copy operation folder exception: $e');
    }
  }

  /// Recursively copy directory
  Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File) {
        final targetFile = File('${target.path}${Platform.pathSeparator}$name');
        await entity.copy(targetFile.path);
        debugPrint('Copying file: ${entity.path} -> ${targetFile.path}');
      } else if (entity is Directory) {
        final targetSubDir =
            Directory('${target.path}${Platform.pathSeparator}$name');
        await targetSubDir.create(recursive: true);
        await _copyDirectory(entity, targetSubDir);
      }
    }
  }

  /// Copy operation files to studentExam folder (called by server)
  Future<void> _copyOperationFilesToExam(
      String bankName, List<Map<String, dynamic>> operationQuestions) async {
    try {
      // Collect all initial files from operation questions
      final allFiles = <Map<String, dynamic>>[];
      for (final question in operationQuestions) {
        final initialFiles = question['initialFiles'] as List<dynamic>? ?? [];
        for (final file in initialFiles) {
          allFiles.add({
            'fileName': file['fileName'] ?? '',
            'filePath': file['filePath'] ?? '',
          });
        }
      }

      if (allFiles.isEmpty) {
        debugPrint('No operation files to copy');
        return;
      }

      // Use VhdService to copy files
      final success = await VhdService.writeInitialFiles(allFiles);

      if (success) {
        debugPrint('Operation files copied to studentExam folder');
      } else {
        debugPrint('Operation file copy failed');
      }
    } catch (e) {
      debugPrint('Copy operation file exception: $e');
    }
  }

  /// Create virtual drive mapping (called by server)
  Future<void> _createVirtualDrive(String bankName) async {
    try {
      // Use AppPath.informationDir for bank path in exe mode, debug uses project structure
      final bankPath = '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      await VhdService.cleanupAllSubstDrives();
      final driveLetter = await VhdService.mountPath(bankPath);

      if (driveLetter != null) {
        debugPrint('Operation drive mapped: $driveLetter');
      } else {
        debugPrint('Operation drive mapping failed');
      }
    } catch (e) {
      debugPrint('Create operation drive mapping exception: $e');
    }
  }
}
