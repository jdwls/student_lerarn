import 'package:flutter/material.dart';
import 'base_typing_page.dart';

/// 中文打字练习页面
class ChineseTypingPage extends BaseTypingPage {
  const ChineseTypingPage({super.key})
      : super(
          config: const TypingConfig(
            type: 'chinese',
            title: '中文打字练习',
            fontFamily: 'NSimSun',
            baseFontSize: 26.0,
            defaultTimeLimitMinutes: 5,
            defaultTargetSpeed: 20,
            defaultTargetChars: 100,
            defaultPointsPerError: 1.0,
            apiConfigEndpoint: '/typing-config/chinese',
            apiArticlesEndpoint: '/typing-articles/chinese',
          ),
        );

  // RouteObserver 用于监听页面可见性变化
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  State<ChineseTypingPage> createState() => _ChineseTypingPageState();
}

class _ChineseTypingPageState extends BaseTypingPageState<ChineseTypingPage> {
  @override
  RouteObserver<ModalRoute<void>> get routeObserver =>
      ChineseTypingPage.routeObserver;
}
