import 'package:flutter/material.dart';
import 'base_typing_page.dart';

/// 英文打字练习页面
class EnglishTypingPage extends BaseTypingPage {
  const EnglishTypingPage({super.key})
      : super(
          config: const TypingConfig(
            type: 'english',
            title: '英文打字练习',
            fontFamily: 'Courier New',
            baseFontSize: 23.4,
            defaultTimeLimitMinutes: 5,
            defaultTargetSpeed: 100,
            defaultTargetChars: 500,
            defaultPointsPerError: 0.2,
            apiConfigEndpoint: '/typing-config/english',
            apiArticlesEndpoint: '/typing-articles/english',
          ),
        );

  // RouteObserver 用于监听页面可见性变化
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  State<EnglishTypingPage> createState() => _EnglishTypingPageState();
}

class _EnglishTypingPageState extends BaseTypingPageState<EnglishTypingPage> {
  @override
  RouteObserver<ModalRoute<void>> get routeObserver =>
      EnglishTypingPage.routeObserver;
}
