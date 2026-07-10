import 'package:flutter/widgets.dart';

/// 禁止复制粘贴的文本输入控制器
/// 通过监听文本变化来检测粘贴行为：
/// - 如果一次性新增多个字符且不是输入法 composing 状态，则只保留最后一个字符
/// - 这样可以防止用户通过右键菜单、Ctrl+V、输入法工具栏等方式粘贴大段文本
class NoCopyPasteTextEditingController extends TextEditingController {
  NoCopyPasteTextEditingController({super.text});

  String _previousText = '';
  bool _isComposing = false;

  @override
  set value(TextEditingValue newValue) {
    // 检测 composing 状态变化
    final wasComposing = _isComposing;
    _isComposing = newValue.composing != TextRange.empty;

    // 如果刚刚从 composing 状态结束（拼音上屏），允许正常设置
    if (wasComposing && !_isComposing) {
      _previousText = newValue.text;
      super.value = newValue;
      return;
    }

    // 如果正在 composing 中，允许正常设置
    if (_isComposing) {
      _previousText = newValue.text;
      super.value = newValue;
      return;
    }

    // 检测是否为粘贴行为：新文本比旧文本多出超过1个字符
    final oldText = _previousText;
    final newText = newValue.text;

    if (newText.length > oldText.length + 1) {
      // 一次性新增了多个字符，很可能是粘贴
      // 只保留最后一个新增的字符
      final lastChar = newText.substring(newText.length - 1);
      final filteredText = oldText + lastChar;
      final newSelection = TextSelection.collapsed(offset: filteredText.length);
      _previousText = filteredText;
      super.value = TextEditingValue(
        text: filteredText,
        selection: newSelection,
        composing: TextRange.empty,
      );
      return;
    }

    _previousText = newValue.text;
    super.value = newValue;
  }

  @override
  set text(String newText) {
    // 检测是否为粘贴行为
    if (!_isComposing && newText.length > _previousText.length + 1) {
      final lastChar = newText.substring(newText.length - 1);
      final filteredText = _previousText + lastChar;
      _previousText = filteredText;
      super.text = filteredText;
      return;
    }
    _previousText = newText;
    super.text = newText;
  }

  /// 重置前文本记录（用于重新开始打字时清空状态）
  void resetPreviousText() {
    _previousText = text;
  }
}
