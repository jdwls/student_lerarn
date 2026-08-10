import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/login_page.dart';
import 'providers/auth_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/user_provider.dart';
import 'services/api_service.dart';
import 'services/quiz_service.dart';
import 'services/socket_service.dart';
import 'services/single_instance_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先初始化 ApiService（读取配置）
  await ApiService.init();
  await QuizService.init();
  // 启动时尝试消费上次网络失败的成绩队列
  await ApiService.drainPendingTypingSubmissions();
  // 小测队列消费与网络初始化失败时不影响启动
  try {
    await QuizService.drainPendingExamSubmissions();
  } catch (_) {}

  // 并行初始化其他服务，任一失败不影响启动
  final results = await Future.wait([
    SingleInstanceService.tryAcquire().catchError((_) => false),
    SocketService.init().catchError((_) {}),
    windowManager.ensureInitialized().catchError((_) {}),
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

class StudentApp extends StatefulWidget {
  final bool useCustomTitleBar;
  const StudentApp({super.key, this.useCustomTitleBar = true});

  @override
  State<StudentApp> createState() => _StudentAppState();
}

class _StudentAppState extends State<StudentApp> with WidgetsBindingObserver {
  bool _cleanupStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _cleanupServices();
    }
  }

  Future<void> _cleanupServices() async {
    if (_cleanupStarted) return;
    _cleanupStarted = true;
    try {
      SocketService.instance.disconnect();
    } catch (_) {}
    try {
      await SingleInstanceService.release();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupServices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService: apiService)),
        ChangeNotifierProvider(
            create: (_) => UserProvider(apiService: apiService)),
        ChangeNotifierProvider(
            create: (_) => ExamProvider(apiService: apiService)),
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
