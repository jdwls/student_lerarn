part of 'quiz_page.dart';

/// 顺序题相关 mixin
mixin _SequentialWidgetMixin on State<QuizPage> {
  _QuizPageState get _quizState => this as _QuizPageState;

  /// 顺序题
  Widget _buildSequentialQuestion(Map<String, dynamic> question) {
    final items = question['items'] as List<dynamic>? ?? [];
    final itemIds =
        items.map((item) => (item as Map)['id']?.toString() ?? '').toList();
    final savedAnswer =
        _quizState._answers[_quizState._currentQuestionIndex] as List?;
    final savedIds = savedAnswer
        ?.map((e) => e.toString())
        .where((id) => itemIds.contains(id))
        .toList();
    final userOrder = (savedIds?.length == itemIds.length)
        ? List<String>.from(savedIds!)
        : List<String>.from(itemIds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题干
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            question['questionText'] ?? '',
            style: TextStyle(
                fontSize: 31.2 * _quizState._contentScale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'SimHei'),
          ),
        ),
        const SizedBox(height: 16),
        // 提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_indicator, size: 16, color: Colors.green[700]),
              const SizedBox(width: 6),
              Text(
                '拖拽调整顺序',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 拖拽列表
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: userOrder.length,
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) {
            _quizState.setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = userOrder.removeAt(oldIndex);
              userOrder.insert(newIndex, item);
              _quizState._answers[_quizState._currentQuestionIndex] =
                  List.from(userOrder);
            });
          },
          itemBuilder: (context, index) {
            final itemId = userOrder[index];
            final itemIndex = itemIds.indexOf(itemId);
            if (itemIndex < 0 || itemIndex >= items.length) {
              return const SizedBox.shrink();
            }
            final item = items[itemIndex];

            return ReorderableDragStartListener(
              key: ValueKey(itemId),
              index: index,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  leading: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withAlpha(77),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item['text'] ?? '',
                        style: TextStyle(
                          fontSize: 30 * _quizState._contentScale,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'SimHei',
                        ),
                      ),
                      if (item['image'] != null &&
                          item['image'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _quizState._buildImage(item['image'].toString()),
                      ],
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.drag_handle,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
