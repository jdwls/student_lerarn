part of 'quiz_page.dart';

/// Data loader mixin - handles question bank loading, parsing, and syncing
mixin _DataLoaderMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// Load list of available question banks
  Future<void> _loadQuestionBanks() async {
    if (!_quizState.mounted) return;
    _quizState.setState(() {
      _quizState._isLoading = true;
      _quizState._errorMessage = null;
    });

    try {
      final activeBank = await QuizService.getActiveBank();

      if (activeBank != null && activeBank.isNotEmpty) {
        await _loadQuestionBank(activeBank);
      } else {
        if (!_quizState.mounted) return;
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '等待教师发布题目...';
        });
      }
    } catch (e) {
      if (!_quizState.mounted) return;
      _quizState.setState(() {
        _quizState._isLoading = false;
        _quizState._errorMessage = '无法连接服务器：$e';
      });
    }
  }

  Future<void> _loadQuestionBank(String bankName) async {
    if (!_quizState.mounted) return;
    final generation = ++_quizState._loadGeneration;
    bool current() => _quizState._isCurrentLoad(generation);
    _quizState.setState(() {
      _quizState._isLoading = true;
      _quizState._errorMessage = null;
    });

    try {
      await VhdService.cleanupAllSubstDrives();
      if (!current()) return;

      debugPrint('Starting sync bank: $bankName');
      final syncResult = await QuizService.syncBankFiles(bankName);
      if (!current()) return;

      if (syncResult == null) {
        if (!_quizState.mounted) return;
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '无法同步题库文件';
        });
        return;
      }

      final bankContent = syncResult['bank_content'];
      if (bankContent == null ||
          (bankContent is String && bankContent.isEmpty)) {
        if (!_quizState.mounted) return;
        if (!_quizState.mounted) return;
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '题库内容为空';
        });
        return;
      }

      final Map<String, dynamic> data;
      if (bankContent is Map) {
        data = Map<String, dynamic>.from(bankContent);
      } else if (bankContent is String) {
        data = json.decode(bankContent) as Map<String, dynamic>;
      } else {
        if (!_quizState.mounted) return;
        if (!_quizState.mounted) return;
        _quizState.setState(() {
          _quizState._isLoading = false;
          _quizState._errorMessage = '题库数据格式错误';
        });
        return;
      }
      await LocalStorageService.instance.saveQuestionBank(bankName, data);
      if (!current()) return;
      debugPrint('Bank saved to local: $bankName');

      final operationFiles =
          syncResult['operation_files'] as List<dynamic>? ?? [];
      if (operationFiles.isNotEmpty) {
        await _saveOperationFilesToLocal(bankName, operationFiles);
        if (!current()) return;
        debugPrint('Operation files saved: ${operationFiles.length}');
      }

      await _downloadAndCacheImages(bankName, data);
      if (!current()) return;

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

      if (operationQuestions.isNotEmpty) {
        await VhdService.cleanupAllSubstDrives();
        if (!current()) return;
        await _createVirtualDriveFromLocal(bankName);
        if (!current()) return;
      }

      choiceQuestions.shuffle();
      matchingQuestions.shuffle();
      sequentialQuestions.shuffle();
      typingQuestions.shuffle();
      operationQuestions.shuffle();

      if (!_quizState.mounted) return;
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
        _quizState._selectedQuestionType = 'all';
        _quizState._currentQuestionIndex = 0;
        _quizState._answers.clear();
        // 清理旧打字题状态，避免 TextEditingController 泄漏
        for (final ts in _quizState._typingStates.values) {
          ts.dispose();
        }
        _quizState._typingStates.clear();
        _quizState._matchingMeasured = false;
        _quizState._elapsedSeconds = 0;
        _quizState._isLoading = false;
      });

      _quizState._startTimer();

      final examTimeLimit = await QuizService.getExamTimeLimit();
      if (!current()) return;
      final earlySubmitMinutes = await QuizService.getEarlySubmitMinutes();
      if (!current()) return;
      if (examTimeLimit > 0) {
        if (!_quizState.mounted) return;
        _quizState.setState(() {
          _quizState._examTimeLimit = examTimeLimit;
          _quizState._examRemainingSeconds = examTimeLimit * 60;
          _quizState._earlySubmitMinutes = earlySubmitMinutes;
        });
        _startExamTimer();
      }

      if (!current()) return;
      _copyOperationToDocumentsAfterDelay(bankName, generation);
    } catch (e) {
      if (!_quizState.mounted) return;
      _quizState.setState(() {
        _quizState._isLoading = false;
        _quizState._errorMessage = '加载题库失败：$e';
      });
    }
  }

  Map<String, dynamic> _parseChoiceQuestion(Map<String, dynamic> q) {
    final items = q['items'] as List<dynamic>?;
    String questionText, questionImage, answer;
    int score;
    String optA, optB, optC, optD;
    String? imgA, imgB, imgC, imgD;

    if (items != null && items.isNotEmpty) {
      final item = items[0] as Map<String, dynamic>;
      questionText = q['题干'] ?? q['questionText'] ?? '';
      questionImage = q['题干图片'] ?? q['questionImage'] ?? '';
      answer = item['答案'] ?? item['answer'] ?? '';
      score = int.tryParse(
              item['分值']?.toString() ?? item['score']?.toString() ?? '5') ??
          5;

      final optionLabels = ['A', 'B', 'C', 'D'];
      final options = <Map<String, dynamic>>[];
      for (final label in optionLabels) {
        options.add({
          'label': label,
          'text': item['选项$label'] ?? item['option$label'] ?? '',
          'image': item['图片$label'] ?? item['image$label'],
        });
      }

      options.shuffle();

      optA = options[0]['text'];
      optB = options[1]['text'];
      optC = options[2]['text'];
      optD = options[3]['text'];
      imgA = options[0]['image'];
      imgB = options[1]['image'];
      imgC = options[2]['image'];
      imgD = options[3]['image'];

      final newAnswerMap = <String, String>{
        'A': options[0]['label'],
        'B': options[1]['label'],
        'C': options[2]['label'],
        'D': options[3]['label'],
      };
      String? newAnswer;
      for (final entry in newAnswerMap.entries) {
        if (entry.value == answer) {
          newAnswer = entry.key;
          break;
        }
      }
      answer = newAnswer ?? answer;
    } else {
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

  Map<String, dynamic> _parseMatchingQuestion(Map<String, dynamic> q) {
    final rawItems = (q['items'] as List<dynamic>?) ?? [];
    final questionScore = q['score'] is num
        ? (q['score'] as num).toInt()
        : int.tryParse(q['score']?.toString() ?? '') ??
            rawItems.fold<int>(
                0,
                (sum, item) =>
                    sum +
                    (int.tryParse(item['分值']?.toString() ??
                            item['score']?.toString() ??
                            '5') ??
                        5));
    final leftItems = <Map<String, dynamic>>[];
    final rightItems = <Map<String, dynamic>>[];
    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      leftItems.add({
        'text': item['左侧内容'] ?? item['leftContent'] ?? item['leftText'] ?? '',
        'image': item['左侧图片'] ?? item['leftImage'],
        'originalIndex': i,
      });
      rightItems.add({
        'text': item['右侧内容'] ?? item['rightContent'] ?? item['rightText'] ?? '',
        'image': item['右侧图片'] ?? item['rightImage'],
        'originalIndex': i,
        'score': int.tryParse(
                item['分值']?.toString() ?? item['score']?.toString() ?? '5') ??
            5,
      });
    }

    leftItems.shuffle();
    rightItems.shuffle();

    final correctMapping = <String, String>{};
    for (final leftItem in leftItems) {
      Map<String, dynamic>? rightItem;
      for (final candidate in rightItems) {
        if (candidate['originalIndex'] == leftItem['originalIndex']) {
          rightItem = candidate;
          break;
        }
      }
      if (rightItem != null) {
        correctMapping[leftItem['originalIndex'].toString()] =
            rightItem['originalIndex'].toString();
      }
    }

    final items = <Map<String, dynamic>>[];
    for (int i = 0; i < leftItems.length; i++) {
      items.add({
        'leftText': leftItems[i]['text'],
        'rightText': rightItems[i]['text'],
        'leftImage': leftItems[i]['image'],
        'rightImage': rightItems[i]['image'],
        'leftId': leftItems[i]['originalIndex'].toString(),
        'rightId': rightItems[i]['originalIndex'].toString(),
        'score': rightItems[i]['score'],
      });
    }

    return {
      'type': 'matching',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'questionImage': q['题干图片'] ?? q['questionImage'],
      'score': questionScore,
      'items': items,
      'correctMapping': correctMapping,
    };
  }

  Map<String, dynamic> _parseSequentialQuestion(Map<String, dynamic> q) {
    final rawItems = (q['items'] as List<dynamic>?) ?? [];
    final questionScore = q['score'] is num
        ? (q['score'] as num).toInt()
        : int.tryParse(q['score']?.toString() ?? '') ??
            rawItems.fold<int>(
                0,
                (sum, item) =>
                    sum +
                    (int.tryParse(item['分值']?.toString() ??
                            item['score']?.toString() ??
                            '5') ??
                        5));
    final items = <Map<String, dynamic>>[];
    final correctOrder = <String>[];
    for (int index = 0; index < rawItems.length; index++) {
      final item = rawItems[index];
      final id = item['序号']?.toString() ?? '$index';
      correctOrder.add(id);
      items.add({
        'id': id,
        'text': item['待排序项目'] ?? item['orderText'] ?? item['orderOption'] ?? '',
        'image': item['项图片'] ?? item['optionImage'] ?? item['image'],
        'score': int.tryParse(
                item['分值']?.toString() ?? item['score']?.toString() ?? '5') ??
            5,
      });
    }

    if (items.length > 1) {
      items.shuffle();
    }

    return {
      'type': 'sequential',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'questionImage': q['题干图片'] ?? q['questionImage'],
      'score': questionScore,
      'items': items,
      // 答案保存为题库中的稳定 ID 顺序，不受展示随机排序影响。
      'answer': correctOrder,
    };
  }

  Map<String, dynamic> _parseTypingQuestion(Map<String, dynamic> q) {
    int safeInt(dynamic value, int fallback) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? fallback;
    return {
      'type': 'typing',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? q['参考文本'] ?? '',
      'typingType': q['打字类型'] ?? q['typingType'] ?? 'chinese',
      'referenceText': q['参考文本'] ?? q['referenceText'] ?? '',
      'timeLimit': safeInt(q['时间限制'] ?? q['timeLimit'], 5),
      'score': safeInt(q['分值'] ?? q['score'], 10),
    };
  }

  /// 规范化操作题路径：去除 "题库/{bankName}/操作题/" 前缀，只保留题目目录及文件名
  /// 例如: "题库/2/操作题/题目1/新建文本文档.txt" -> "题目1/新建文本文档.txt"
  /// 同时将正斜杠替换为系统路径分隔符
  static String _normalizeOperationFilePath(String path) {
    if (path.isEmpty) return '';
    // 统一使用系统路径分隔符
    String result = path.replaceAll('/', Platform.pathSeparator);
    // 查找 "操作题" 并取其后部分
    final keyPart = '${Platform.pathSeparator}操作题${Platform.pathSeparator}';
    final idx = result.indexOf(keyPart);
    if (idx >= 0) {
      result = result.substring(idx + keyPart.length);
    }
    return result;
  }

  /// Parse operation question — 从检查行中提取检查项
  Map<String, dynamic> _parseOperationQuestion(Map<String, dynamic> q) {
    final initialFileRaw = ((q['初始文件'] ?? q['initialFiles']) as List<dynamic>?)
            ?.map((f) => {
                  'fileName': f['文件名'] ?? f['fileName'] ?? '',
                  'filePath': f['文件路径'] ?? f['filePath'] ?? '',
                  'checkLines': f['检查行'] as List<dynamic>? ?? [],
                })
            .toList() ??
        [];

    final answers = <Map<String, dynamic>>[];
    for (final file in initialFileRaw) {
      final rawPath = file['filePath'] ?? '';
      // 规范化路径：去除 "题库/{bankName}/操作题/" 前缀
      final normalizedPath = _normalizeOperationFilePath(rawPath);
      final checkLines = file['checkLines'] as List<dynamic>? ?? [];
      for (final cl in checkLines) {
        final clMap = cl as Map<String, dynamic>;
        answers.add({
          'targetPath': normalizedPath,
          'lineNumber': clMap['行号'] is int
              ? clMap['行号']
              : (int.tryParse(clMap['行号']?.toString() ?? '0') ?? 0),
          'expectedContent': clMap['期望内容']?.toString().isNotEmpty == true
              ? clMap['期望内容'].toString()
              : clMap['内容']?.toString() ?? '',
          'score': clMap['分值'] is int
              ? clMap['分值']
              : (int.tryParse(clMap['分值']?.toString() ?? '5') ?? 5),
        });
      }
    }

    // 从检查项分值累加计算操作题总分（如果未显式设置分值）
    final operationScore = q['分值'] ?? q['score'];
    final calculatedScore = operationScore != null
        ? (int.tryParse(operationScore.toString()) ?? 10)
        : answers.fold<int>(0, (sum, a) => sum + (a['score'] as int));

    return {
      'type': 'operation',
      'number': q['题号']?.toString() ?? q['number'] ?? '1',
      'questionText': q['题干'] ?? q['questionText'] ?? '',
      'score': calculatedScore,
      'initialFiles': initialFileRaw,
      'answers': answers,
    };
  }

  /// 保存操作题文件到本地（事务模式：临时目录 → 原子替换）
  /// 返回 true 表示成功，false 表示失败
  Future<bool> _saveOperationFilesToLocal(
      String bankName, List<dynamic> operationFiles) async {
    if (operationFiles.isEmpty) {
      debugPrint('操作题文件列表为空');
      return true;
    }

    try {
      // 1. 确定正式目录和临时目录
      final operationFolderPath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      final tempFolderPath = '$operationFolderPath.tmp';
      final operationFolder = Directory(operationFolderPath);
      final tempFolder = Directory(tempFolderPath);

      // 2. 清理临时目录（如果存在）
      if (await tempFolder.exists()) {
        await tempFolder.delete(recursive: true);
      }

      // 3. 创建临时目录
      await tempFolder.create(recursive: true);

      int successCount = 0;
      int failureCount = 0;
      int totalBytes = 0;

      // 4. 所有文件写入到临时目录
      for (final file in operationFiles) {
        final fileMap = file is Map<String, dynamic>
            ? file
            : Map<String, dynamic>.from(file as Map);
        final rawPath =
            (fileMap['fileName'] ?? fileMap['path'])?.toString() ?? '';
        final content = fileMap['content'] as String?;
        final filePath = fileMap['filePath'] as String?;

        if (rawPath.isEmpty) {
          failureCount++;
          continue;
        }

        // 路径验证
        final segments = rawPath.replaceAll('\\', '/').split('/');
        if (segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
            rawPath.startsWith('/') ||
            RegExp(r'^[A-Za-z]:').hasMatch(rawPath)) {
          debugPrint('警告: 拒绝非法操作题路径: $rawPath');
          failureCount++;
          continue;
        }

        try {
          final safePath = segments.join(Platform.pathSeparator);
          final rootPath = await tempFolder.resolveSymbolicLinks();
          final targetPath = path.normalize(path.join(rootPath, safePath));
          final prefix = rootPath.endsWith(Platform.pathSeparator)
              ? rootPath
              : '$rootPath${Platform.pathSeparator}';

          // 防止目录穿越
          if (!targetPath.startsWith(prefix)) {
            debugPrint('警告: 目录穿越尝试: $rawPath');
            failureCount++;
            continue;
          }

          final targetFile = File(targetPath);
          final targetDir = targetFile.parent;
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }

          // 写入文件
          if (content != null && content.isNotEmpty) {
            try {
              final decoded = base64Decode(content);
              await targetFile.writeAsBytes(decoded);
              totalBytes += decoded.length;
            } catch (_) {
              await targetFile.writeAsString(content);
              totalBytes += content.length;
            }
          } else if (filePath != null && filePath.isNotEmpty) {
            final sourceFile = File(filePath);
            if (await sourceFile.exists()) {
              await sourceFile.copy(targetPath);
              final stat = await sourceFile.stat();
              totalBytes += stat.size;
            } else {
              await targetFile.writeAsString('');
            }
          } else {
            await targetFile.writeAsString('');
          }

          successCount++;
        } catch (e) {
          debugPrint('写入操作题文件失败: $rawPath, 错误: $e');
          failureCount++;
        }
      }

      // 5. 检查是否有失败
      if (failureCount > 0) {
        debugPrint('操作题文件保存部分失败: 成功=$successCount, 失败=$failureCount, 总字节=$totalBytes');
        // 保留临时目录用于调试，但返回失败
        return false;
      }

      debugPrint('操作题文件临时写入成功: 文件数=$successCount, 总字节=$totalBytes');

      // 6. 原子替换：删除旧目录，rename临时目录
      try {
        if (await operationFolder.exists()) {
          await operationFolder.delete(recursive: true);
        }
        await tempFolder.rename(operationFolderPath);
        debugPrint('操作题目录已更新: $operationFolderPath');
        return true;
      } catch (e) {
        debugPrint('操作题目录替换失败: $e, 临时目录保留在 $tempFolderPath');
        return false;
      }
    } catch (e) {
      debugPrint('操作题文件保存异常: $e');
      return false;
    }
  }

  Future<void> _downloadAndCacheImages(
      String bankName, Map<String, dynamic> data) async {
    try {
      final imageUrls = <String>[];
      final choiceQuestions = data['choiceQuestions'] as List<dynamic>? ?? [];
      for (final q in choiceQuestions) {
        final qMap = q as Map<String, dynamic>;
        final questionImage = qMap['题干图片'] ?? qMap['questionImage'] ?? '';
        if (questionImage.isNotEmpty) {
          imageUrls.add(questionImage);
        }
        final items = qMap['items'] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          final item = items[0] as Map<String, dynamic>;
          for (final label in ['A', 'B', 'C', 'D']) {
            final img = item['图片$label'] ?? item['image$label'];
            if (img != null && img.toString().isNotEmpty) {
              imageUrls.add(img.toString());
            }
          }
        }
      }

      if (imageUrls.isNotEmpty) {
        for (final url in imageUrls) {
          try {
            // 跳过本地绝对路径
            if (url.startsWith('C:') ||
                url.startsWith('D:') ||
                url.startsWith('/')) {
              continue;
            }
            // 已经是 HTTP URL，直接下载
            if (url.startsWith('http://') || url.startsWith('https://')) {
              final uri = Uri.parse(url);
              final fileName = uri.pathSegments.last;
              if (fileName.isEmpty) continue;
              await LocalStorageService.instance
                  .downloadAndSaveImage(bankName, url, fileName);
              continue;
            }
            // 相对路径（如 "题库名称/图片/文件名.jpg"），拼接教师端文件服务URL
            final fullUrl =
                '${QuizService.serverBaseUrl}/files/$url';
            // 从路径中提取文件名
            final fileName = url.split('/').last;
            if (fileName.isEmpty) continue;
            await LocalStorageService.instance
                .downloadAndSaveImage(bankName, fullUrl, fileName);
          } catch (e) {
            debugPrint('Download image failed $url: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Download cache image failed: $e');
    }
  }

  Future<void> _createVirtualDriveFromLocal(String bankName) async {
    try {
      final operationFolderPath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      final operationFolder = Directory(operationFolderPath);
      if (!await operationFolder.exists()) {
        await operationFolder.create(recursive: true);
      }

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

  void _startExamTimer() {
    _quizState._examTimer?.cancel();
    _quizState._examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_quizState.mounted) return;
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

  void _onExamTimeUp() async {
    if (_quizState._showingOperationOverlay) {
      int operationScore = 0;
      try {
        if (_quizState._currentOperationAnswers != null &&
            VhdService.isMounted) {
          final checkResult = await VhdService.checkAnswersWithDetails(
            _quizState._currentOperationAnswers!.cast<Map<String, dynamic>>(),
          );
          operationScore = checkResult['totalScore'] as int? ?? 0;
        }
      } catch (e) {
        debugPrint('[自动提交] 批改异常: $e');
      }
      _quizState._stopWindowCheck();
      if (!_quizState.mounted) return;
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
      _restoreWindowAfterOperation();
      await Future.delayed(const Duration(milliseconds: 500));
      _quizState._autoSubmitExam();
    } else {
      _quizState._autoSubmitExam();
    }
  }

  void _restoreWindowAfterOperation() {
    try {
      windowManager.setAlwaysOnTop(false);
      windowManager.setBackgroundColor(Colors.white);
      windowManager.setFullScreen(true);
    } catch (_) {}
  }

  Future<void> _copyOperationFolderToExam(String bankName) async {
    try {
      final sourcePath = 'teacher/exam/$bankName/operation';
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        debugPrint('Operation folder not found: $sourcePath');
        return;
      }
      final targetPath = '${AppPath.informationDir}/operation_$bankName';
      final targetDir = Directory(targetPath);
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);
      await _copyDirectory(sourceDir, targetDir);
    } catch (e) {
      debugPrint('Copy operation folder exception: $e');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File) {
        final targetFile = File('${target.path}${Platform.pathSeparator}$name');
        await entity.copy(targetFile.path);
      } else if (entity is Directory) {
        final targetSubDir =
            Directory('${target.path}${Platform.pathSeparator}$name');
        await targetSubDir.create(recursive: true);
        await _copyDirectory(entity, targetSubDir);
      }
    }
  }

  Future<void> _copyOperationFilesToExam(
      String bankName, List<Map<String, dynamic>> operationQuestions) async {
    try {
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
      if (allFiles.isEmpty) return;
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

  Future<void> _createVirtualDrive(String bankName) async {
    try {
      final bankPath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
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

  /// 延迟3秒后，将操作题从 information 复制到 Documents/题库/{bankName}/操作题/
  Future<void> _copyOperationToDocumentsAfterDelay(
      String bankName, int generation) async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      if (!_quizState._isCurrentLoad(generation)) return;
      await _copyOperationToDocuments(bankName);
    } catch (e) {
      debugPrint('Copy operation to documents after delay failed: $e');
    }
  }

  /// 将操作题从 information/{bankName}/操作题/ 复制到 Documents/题库/{bankName}/操作题/
  Future<void> _copyOperationToDocuments(String bankName) async {
    try {
      // 源路径：information/{bankName}/操作题/
      final sourcePath =
          '${AppPath.informationDir}${Platform.pathSeparator}$bankName${Platform.pathSeparator}操作题';
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        debugPrint('Source operation path not found: $sourcePath');
        return;
      }

      // 目标路径：Documents/题库/{bankName}/操作题/
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isEmpty) {
        debugPrint('Cannot get user profile path');
        return;
      }
      final targetPath = '$userProfile\\Documents\\题库\\$bankName\\操作题';
      final targetDir = Directory(targetPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      } else {
        // 先删除旧目录，再重新创建，确保完全覆盖
        await targetDir.delete(recursive: true);
        await targetDir.create(recursive: true);
      }

      // 递归复制所有文件
      await _copyDirectory(sourceDir, targetDir);
      debugPrint(
          'Operation files copied to Documents: $sourcePath -> $targetPath');
    } catch (e) {
      debugPrint('Copy operation to documents failed: $e');
    }
  }
}
