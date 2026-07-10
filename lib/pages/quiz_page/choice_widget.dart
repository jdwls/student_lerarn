part of 'quiz_page.dart';

/// 选择题图片相关 mixin
mixin _ChoiceWidgetMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// 选择题
  Widget _buildChoiceQuestion(Map<String, dynamic> question) {
    final selectedAnswer =
        _quizState._answers[_quizState._currentQuestionIndex] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题干
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question['questionText'] ?? '',
                style: const TextStyle(
                    fontSize: 31.2,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'SimHei'),
              ),
              if (question['questionImage'] != null &&
                  question['questionImage'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                _quizState._buildImage(question['questionImage'].toString()),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 选项 - 一行一个
        Column(
          children: [
            _buildOptionCard('A', question['optionA'] ?? '',
                question['imageA']?.toString(), selectedAnswer),
            const SizedBox(height: 12),
            _buildOptionCard('B', question['optionB'] ?? '',
                question['imageB']?.toString(), selectedAnswer),
            const SizedBox(height: 12),
            _buildOptionCard('C', question['optionC'] ?? '',
                question['imageC']?.toString(), selectedAnswer),
            const SizedBox(height: 12),
            _buildOptionCard('D', question['optionD'] ?? '',
                question['imageD']?.toString(), selectedAnswer),
          ],
        ),
      ],
    );
  }

  /// 构建图片widget
  Widget _buildImage(String? imageUrl, {String? bankName}) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();

    final bank = bankName ?? _quizState._selectedBank ?? '';

    return FutureBuilder<String?>(
      future: _getLocalImageFilePath(bank, imageUrl),
      builder: (context, snapshot) {
        Widget imageWidget;

        if (snapshot.hasData && snapshot.data != null) {
          // 使用本地图片
          imageWidget = Image.file(
            File(snapshot.data!),
            height: 150,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildNetworkImage(imageUrl);
            },
          );
        } else {
          // 使用网络图片
          imageWidget = _buildNetworkImage(imageUrl);
        }

        return GestureDetector(
          onTap: () => _showFullScreenImage(context, imageUrl, bank),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageWidget,
          ),
        );
      },
    );
  }

  /// 显示全屏图片
  void _showFullScreenImage(
      BuildContext context, String imageUrl, String bank) {
    final controller = TransformationController();
    // 设置初始缩为100%
    controller.value = Matrix4.identity();

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Scaffold(
                backgroundColor: Colors.black54,
                body: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    transformationController: controller,
                    child: GestureDetector(
                      onTap: () {},
                      child: FutureBuilder<String?>(
                        future: _getLocalImageFilePath(bank, imageUrl),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return Image.file(
                              File(snapshot.data!),
                              fit: BoxFit.contain,
                            );
                          }
                          return Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.white, size: 64),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 获取本地图片文件路径（处理各种文件名格）
  Future<String?> _getLocalImageFilePath(
      String bankName, String imageUrl) async {
    // 尝试获取所有可能的文件
    final files = await LocalStorageService.instance.getImagePath(bankName);
    final dir = Directory(files);

    if (!dir.existsSync()) return null;

    // 从URL提取可能的文件名模式（使用 path 语义统一处理）
    String urlFileName = imageUrl.split('/').last;

    // 去掉时间戳后缀（如 _20260429_132256.jpg）
    String baseName = urlFileName;
    final timestampMatch =
        RegExp(r'_\d{8}_\d{6}(?=\.[^.]+$)').firstMatch(urlFileName);
    if (timestampMatch != null) {
      baseName = urlFileName.substring(0, timestampMatch.start) +
          urlFileName.substring(timestampMatch.end);
    }

    // 列出目录中的所有文件，查找匹配
    for (var entity in dir.listSync()) {
      if (entity is File) {
        // 统一使用 path 语义获取文件名（兼容所有平台）
        String fileName = entity.path.split(RegExp(r'[/\\]')).last;
        // 检查是否匹配（带时间戳或不带时间戳）
        if (fileName == urlFileName ||
            fileName == baseName ||
            fileName.contains(baseName.split('.').first)) {
          return entity.path;
        }
      }
    }
    return null;
  }

  /// 构建网络图片
  Widget _buildNetworkImage(String imageUrl) {
    return Image.network(
      imageUrl,
      height: 150,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 80,
          color: Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.grey[400]),
                const SizedBox(height: 4),
                Text(
                  '图片载失败',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: 80,
          color: Colors.grey[100],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  /// 构建选项卡片
  Widget _buildOptionCard(
      String label, String text, String? imageUrl, String? selectedAnswer) {
    final isSelected = selectedAnswer == label;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () {
        _quizState.setState(() {
          _quizState._answers[_quizState._currentQuestionIndex] = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color:
              isSelected ? AppTheme.primaryColor.withAlpha(26) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withAlpha(51),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            // 标签圆圈
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(31),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryColor.withAlpha(77),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 28.6,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 选项文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 26,
                      color: isSelected ? AppTheme.primaryColor : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SimHei',
                    ),
                  ),
                  if (hasImage) ...[
                    const SizedBox(height: 8),
                    _buildImage(imageUrl),
                  ],
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 12),
              Icon(
                Icons.check_circle,
                color: AppTheme.primaryColor,
                size: 28,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
