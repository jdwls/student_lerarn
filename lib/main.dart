import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/login_page.dart';
import 'providers/auth_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/user_provider.dart';
import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/single_instance_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 并行初始化
  final results = await Future.wait([
    SingleInstanceService.tryAcquire(),
    ApiService.init(),
    SocketService.init(),
    windowManager.ensureInitialized(),
  ]);

  final isSingleInstance = results[0] as bool;
  if (!isSingleInstance) {
    runApp(const AlreadyRunningApp());
    return;
  }

  bool useCustomTitleBar = true;
  try {
    try {
      const windowOptions = WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: Size(1280, 720),
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      useCustomTitleBar = false;
      try {
        const fallbackOptions = WindowOptions(
          size: Size(1280, 720),
          center: true,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.normal,
          title: '学生端',
          minimumSize: Size(1280, 720),
        );
        await windowManager.waitUntilReadyToShow(fallbackOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      } catch (e2) {
        print('窗口初始化失败: $e2');
      }
    }
  } catch (e) {
    useCustomTitleBar = false;
    print('窗口管理器初始化失败: $e');
  }

  runApp(StudentApp(useCustomTitleBar: useCustomTitleBar));
}
class StudentApp extends StatelessWidget {
  final bool useCustomTitleBar;
  const StudentApp({super.key, this.useCustomTitleBar = true});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ExamProvider()),
      ],
      child: MaterialApp(
        title: '学生端',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const LoginPage(),
      ),
    );
  }
}

/// 操作题提示窗口数据（静态变量，用于跨窗口传递）
class OperationGuideData {
  static String questionText = '';
  static List<Map<String, dynamic>> initialFiles = [];
  static List<Map<String, dynamic>> answers = [];
  static String? driveLetter;
  static int? windowId;
}

/// 已有实例运行时的提示页面
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '学生端已在运行',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '一台电脑只能启动一个学生端程序',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => exit(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('退出'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}