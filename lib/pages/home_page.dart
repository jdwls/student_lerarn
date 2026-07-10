import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_title_bar.dart';
import 'chinese_typing_page.dart';
import 'english_typing_page.dart';
import 'quiz_page/quiz_page.dart';
import 'points_exchange_page.dart';

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  // RouteObserver 用于监听页面可见性变化
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> with RouteAware {
  String? _activeClassId; // 教师端当前活跃班级
  Timer? _activeClassTimer;
  bool _isPollingPaused = false; // 标记轮询是否暂停
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        final userProvider = context.read<UserProvider>();
        userProvider.setUser(auth.currentUser!);
        userProvider.loadUserData(auth.currentUser!.id);
      }
    });
    // 获取教师端活跃班级
    _fetchActiveClass();
    // 定时查询教师端活跃班级变化
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      MainHomePage.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _activeClassTimer?.cancel();
    MainHomePage.routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// 当其他页面覆盖当前页面时，暂停轮询
  @override
  void didPushNext() {
    if (!_isPollingPaused) {
      _isPollingPaused = true;
      _activeClassTimer?.cancel();
      debugPrint('首页轮询已暂停（页面被覆盖）');
    }
  }

  /// 当覆盖的页面返回时，恢复轮询
  @override
  void didPopNext() {
    if (_isPollingPaused) {
      _isPollingPaused = false;
      _startPolling();
      debugPrint('首页轮询已恢复（页面返回）');
    }
  }

  /// 启动轮询
  void _startPolling() {
    _activeClassTimer?.cancel();
    _activeClassTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchActiveClass();
    });
  }

  /// 从教师端获取当前活跃班级
  Future<void> _fetchActiveClass() async {
    try {
      final response = await _apiService.get('/active-class');
      if (response['success'] == true) {
        final activeClassId = response['class_id'] as String? ?? '';
        if (activeClassId.isNotEmpty && activeClassId != _activeClassId) {
          debugPrint('教师端活跃班级变化: $_activeClassId -> $activeClassId');
          setState(() {
            _activeClassId = activeClassId;
          });
          // 班级变化时重新获取学生信息（积分等）
          _refreshStudentInfo();
        }
      }
    } catch (e) {
      debugPrint('获取活跃班级失败: $e');
    }
  }

  /// 班级切换时重新获取学生信息（姓名、积分等）
  Future<void> _refreshStudentInfo() async {
    try {
      // 在async gap之前捕获provider，避免use_build_context_synchronously警告
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      final user = auth.currentUser;
      if (user == null) return;

      final computerName = user.computerName ?? '';
      final ip = user.ip ?? '';
      if (computerName.isEmpty || ip.isEmpty) return;

      debugPrint('重新获取学生信息: computer=$computerName, ip=$ip');
      final response = await _apiService.post('/student/find', {
        'computer_name': computerName,
        'ip': ip,
      });

      if (response.containsKey('student') && response['student'] != null) {
        final student = response['student'] as Map<String, dynamic>;
        final newName = student['name'] as String? ?? '';
        final newClassId = student['class_id'] as String? ?? '';
        final newPoints = student['points'] as int? ?? 0;

        debugPrint(
            '获取到学生信息: name=$newName, class=$newClassId, points=$newPoints');

        // 更新 AuthProvider 中的用户信息
        final updatedUser = user.copyWith(
          name: newName,
          classId: newClassId,
        );
        auth.updateCurrentUser(updatedUser);

        // 更新 UserProvider
        userProvider.setUser(updatedUser);
        userProvider.setPointsDirectly(newPoints);
      }
    } catch (e) {
      debugPrint('重新获取学生信息失败: $e');
    }
  }

  /// 获取当前使用的班级ID（优先使用教师端活跃班级）
  String get _currentClassId {
    return _activeClassId ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(title: 'Student - 学生端'),
          _buildTopBar(),
          _buildNavBar(),
          Expanded(
            child: HomeTab(activeClassId: _currentClassId),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Consumer2<AuthProvider, UserProvider>(
      builder: (context, auth, userProvider, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFF8FBFF), Color(0xFFEEF5FF)],
            ),
            border: Border.all(color: const Color(0xFFD6DBE8)),
            borderRadius: BorderRadius.circular(26),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.currentUser?.name ?? '未登录',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '欢迎登录平台查看你的学习数据',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PointsExchangePage()),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: const Color(0xFFECFDF5).withAlpha(128)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.card_giftcard,
                          size: 16, color: Color(0xFF047857)),
                      const SizedBox(width: 6),
                      Text(
                        '积分: ${userProvider.points}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildBadge(
                  '班级: ${_activeClassId ?? userProvider.classLabel ?? '--'}',
                  const Color(0xFFEEF2FF),
                  const Color(0xFF4338CA)),
              const SizedBox(width: 14),
              OutlinedButton(
                onPressed: () async {
                  await auth.logout();
                  exit(0);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(80, 42),
                ),
                child: const Text('退出登录'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bgColor.withAlpha(128)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        border: Border.all(color: const Color(0xFFD6DBE8)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _buildNavButton(
            text: '中文打字',
            icon: Icons.keyboard,
            color: const Color(0xFF3B82F6),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChineseTypingPage()),
              );
            },
          ),
          const SizedBox(width: 10),
          _buildNavButton(
            text: '英文打字',
            icon: Icons.abc,
            color: const Color(0xFF22C55E),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EnglishTypingPage()),
              );
            },
          ),
          const SizedBox(width: 10),
          _buildNavButton(
            text: '考试小测',
            icon: Icons.quiz,
            color: const Color(0xFF16A34A),
            onTap: () {
              final auth = context.read<AuthProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuizPage(
                    studentId: auth.currentUser?.id ?? '',
                    studentName: auth.currentUser?.name ?? '',
                  ),
                ),
              );
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(128)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 首页 Tab（图表区） ====================

class ChartDataPoint {
  final DateTime date;
  final double value;
  ChartDataPoint(this.date, this.value);
}

class HomeTab extends StatefulWidget {
  final String activeClassId;

  const HomeTab({super.key, required this.activeClassId});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;

  List<ChartDataPoint> _examData = [];
  List<ChartDataPoint> _chineseTypingData = [];
  List<ChartDataPoint> _englishTypingData = [];
  List<ChartDataPoint> _pointsData = [];

  int _examTouchIndex = -1;
  int _chineseTouchIndex = -1;
  int _englishTouchIndex = -1;
  int _pointsTouchIndex = -1;

  final ScrollController _detailScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScoreData();
    });
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeClassId != widget.activeClassId) {
      _loadScoreData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台恢复/其他页面返回时刷新数据
    if (state == AppLifecycleState.resumed) {
      _loadScoreData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detailScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScoreData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      // 优先使用教师端活跃班级，否则使用学生注册班级
      final classId = widget.activeClassId.isNotEmpty
          ? widget.activeClassId
          : (auth.currentUser?.classId ?? '');
      final studentId = auth.currentUser?.id ?? '';
      debugPrint('=== 加载成绩数据 ===');
      debugPrint('classId: $classId, studentId: $studentId');

      if (classId.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = '未获取到班级信息';
        });
        return;
      }

      final encodedClassId = Uri.encodeComponent(classId);
      debugPrint('请求URL: /score/summary/$encodedClassId');
      final response = await _apiService.get('/score/summary/$encodedClassId');
      debugPrint('API 响应: success=${response['success']}');
      debugPrint(
          'exam_records: ${(response['exam_records'] as List?)?.length ?? 0}');
      debugPrint(
          'typing_records: ${(response['typing_records'] as List?)?.length ?? 0}');
      debugPrint(
          'points_records: ${(response['points_records'] as List?)?.length ?? 0}');

      if (response['success'] == true) {
        final now = DateTime.now();
        final twoMonthsAgo = DateTime(now.year, now.month - 2, now.day);

        // 处理小测成绩
        final allExamRecords =
            (response['exam_records'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
        debugPrint('全部小测记录: ${allExamRecords.length}');
        for (final r in allExamRecords) {
          debugPrint(
              '  student_id=${r['student_id']}, exam=${r['exam_name']}, score=${r['score']}, time=${r['submit_time']}');
        }
        final examRecords =
            allExamRecords.where((r) => r['student_id'] == studentId).toList();
        debugPrint('匹配studentId=$studentId 的小测: ${examRecords.length}');
        _examData = _processExamData(examRecords, twoMonthsAgo);
        debugPrint('处理小测数据点: ${_examData.length}');

        // 处理打字成绩
        final allTypingRecords =
            (response['typing_records'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
        final typingRecords = allTypingRecords
            .where((r) => r['student_id'] == studentId)
            .toList();
        _chineseTypingData =
            _processTypingData(typingRecords, 'chinese', twoMonthsAgo);
        _englishTypingData =
            _processTypingData(typingRecords, 'english', twoMonthsAgo);

        // 处理积分记录
        final allPointsRecords =
            (response['points_records'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
        final pointsRecords = allPointsRecords
            .where((r) => r['student_id'] == studentId)
            .toList();
        _pointsData = _processPointsData(pointsRecords, twoMonthsAgo);
      } else {
        _error = response['error']?.toString() ?? '获取数据失败';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载成绩数据异常: $e');
      setState(() {
        _isLoading = false;
        _error = '网络请求失败: $e';
      });
    }
  }

  List<ChartDataPoint> _processExamData(
      List<Map<String, dynamic>> records, DateTime since) {
    // 去重：保留每个key的最高分及其对应的时间
    final Map<String, ({double score, DateTime time})> deduped = {};

    for (final r in records) {
      final submitTimeStr = r['submit_time'] as String? ?? '';
      if (submitTimeStr.isEmpty) continue;
      final submitTime = DateTime.tryParse(submitTimeStr);
      if (submitTime == null || submitTime.isBefore(since)) continue;

      final examName = r['exam_name'] as String? ?? '';
      final score = (r['score'] as num?)?.toDouble() ?? 0;
      final dateStr = '${submitTime.month}/${submitTime.day}';
      final key = '${examName}_$dateStr';

      if (!deduped.containsKey(key) || score > deduped[key]!.score) {
        deduped[key] = (score: score, time: submitTime);
      }
    }

    // 直接从去重Map构建结果，避免排序丢失数据
    final result = deduped.entries
        .map((e) => ChartDataPoint(e.value.time, e.value.score))
        .toList();

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  List<ChartDataPoint> _processTypingData(
      List<Map<String, dynamic>> records, String type, DateTime since) {
    final Map<String, double> deduped = {};
    final Map<String, DateTime> dateMap = {};

    for (final r in records) {
      if (r['type'] != type) continue;
      final submitTimeStr = r['submit_time'] as String? ?? '';
      if (submitTimeStr.isEmpty) continue;
      final submitTime = DateTime.tryParse(submitTimeStr);
      if (submitTime == null || submitTime.isBefore(since)) continue;

      final score = (r['score'] as num?)?.toDouble() ?? 0;
      final dateKey =
          '${submitTime.year}-${submitTime.month.toString().padLeft(2, '0')}-${submitTime.day.toString().padLeft(2, '0')}';

      if (!deduped.containsKey(dateKey) || score > deduped[dateKey]!) {
        deduped[dateKey] = score;
        dateMap[dateKey] = submitTime;
      }
    }

    final result = dateMap.entries.map((e) {
      return ChartDataPoint(e.value, deduped[e.key]!);
    }).toList();

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  List<ChartDataPoint> _processPointsData(
      List<Map<String, dynamic>> records, DateTime since) {
    final List<Map<String, dynamic>> filtered = [];

    for (final r in records) {
      final dateStr = r['date'] as String? ?? '';
      if (dateStr.isEmpty) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(since)) continue;
      filtered.add(r);
    }

    filtered.sort((a, b) {
      final da =
          DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime.now();
      final db =
          DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime.now();
      return da.compareTo(db);
    });

    double cumulative = 0;
    final result = <ChartDataPoint>[];
    for (final r in filtered) {
      final date =
          DateTime.tryParse(r['date'] as String? ?? '') ?? DateTime.now();
      final points = (r['points'] as num?)?.toDouble() ?? 0;
      cumulative += points;
      result.add(ChartDataPoint(date, cumulative));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载成绩数据...',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildDetailCard(),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 1,
                      child: _buildLineChartCard(
                        title: '中文打字成绩',
                        data: _chineseTypingData,
                        color: const Color(0xFF3B82F6),
                        touchIndex: _chineseTouchIndex,
                        onTouched: (index) {
                          setState(() => _chineseTouchIndex = index);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildLineChartCard(
                        title: '学习积分变化',
                        data: _pointsData,
                        color: const Color(0xFFF97316),
                        touchIndex: _pointsTouchIndex,
                        onTouched: (index) {
                          setState(() => _pointsTouchIndex = index);
                        },
                        isCumulative: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 1,
                      child: _buildLineChartCard(
                        title: '学生小测成绩趋势',
                        data: _examData,
                        color: const Color(0xFF8B5CF6),
                        touchIndex: _examTouchIndex,
                        onTouched: (index) {
                          setState(() => _examTouchIndex = index);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 1,
                      child: _buildLineChartCard(
                        title: '英文打字成绩',
                        data: _englishTypingData,
                        color: const Color(0xFF22C55E),
                        touchIndex: _englishTouchIndex,
                        onTouched: (index) {
                          setState(() => _englishTouchIndex = index);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 合并所有成绩记录为统一列表（按时间倒序）
  List<Map<String, dynamic>> _buildMergedRecords() {
    final records = <Map<String, dynamic>>[];

    // 小测记录
    for (final d in _examData) {
      records.add({
        'time': d.date,
        'type': '小测',
        'score': d.value,
        'points': (d.value * 0.1).round(),
      });
    }

    // 中文打字记录
    for (final d in _chineseTypingData) {
      records.add({
        'time': d.date,
        'type': '中文打字',
        'score': d.value,
        'points': (d.value * 0.1).round(),
      });
    }

    // 英文打字记录
    for (final d in _englishTypingData) {
      records.add({
        'time': d.date,
        'type': '英文打字',
        'score': d.value,
        'points': (d.value * 0.1).round(),
      });
    }

    // 按时间倒序排列
    records.sort(
        (a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

    return records;
  }

  Widget _buildDetailCard() {
    final mergedRecords = _buildMergedRecords();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD6DBE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '学习概览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _loadScoreData(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD6DBE8)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh,
                          size: 14, color: AppTheme.primaryColor),
                      SizedBox(width: 4),
                      Text(
                        '刷新',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              border: Border.all(color: const Color(0xFFD6DBE8)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    '时间',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '类型',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '成绩',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '积分',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          // 列表数据（可滚动）
          Expanded(
            child: mergedRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.table_chart_outlined,
                          size: 40,
                          color: AppTheme.textSecondary.withAlpha(100),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '暂无成绩记录',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD6DBE8)),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      child: Scrollbar(
                        controller: _detailScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _detailScrollController,
                          itemCount: mergedRecords.length,
                          itemBuilder: (context, index) {
                            final record = mergedRecords[index];
                            final time = record['time'] as DateTime;
                            final type = record['type'] as String;
                            final score = record['score'] as double;
                            final points = record['points'] as int;
                            final isEven = index % 2 == 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isEven
                                    ? Colors.white
                                    : const Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(
                                    color: const Color(0xFFE2E8F0),
                                    width: index < mergedRecords.length - 1
                                        ? 1
                                        : 0,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _getTypeColor(type),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        type,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _getTypeTextColor(type),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${score.toStringAsFixed(0)}分',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '+$points',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF047857),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.errorColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case '小测':
        return const Color(0xFFF3E8FF);
      case '中文打字':
        return const Color(0xFFDBEAFE);
      case '英文打字':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getTypeTextColor(String type) {
    switch (type) {
      case '小测':
        return const Color(0xFF7C3AED);
      case '中文打字':
        return const Color(0xFF2563EB);
      case '英文打字':
        return const Color(0xFF16A34A);
      default:
        return AppTheme.textPrimary;
    }
  }

  Widget _buildLineChartCard({
    required String title,
    required List<ChartDataPoint> data,
    required Color color,
    required int touchIndex,
    required ValueChanged<int> onTouched,
    bool isCumulative = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD6DBE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: data.isEmpty
                ? _buildEmptyPlaceholder()
                : Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: _buildLineChart(data, color, touchIndex, onTouched),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.insert_chart_outlined,
            size: 36,
            color: AppTheme.textSecondary.withAlpha(100),
          ),
          const SizedBox(height: 6),
          const Text(
            '暂无数据',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(
    List<ChartDataPoint> data,
    Color color,
    int touchIndex,
    ValueChanged<int> onTouched,
  ) {
    final values = data.map((d) => d.value).toList();
    double minY = values.reduce((a, b) => a < b ? a : b);
    double maxY = values.reduce((a, b) => a > b ? a : b);

    if (minY == maxY) {
      if (minY == 0) {
        maxY = 10;
      } else {
        minY = minY * 0.8;
        maxY = maxY * 1.2;
      }
    } else {
      final padding = (maxY - minY) * 0.15;
      minY = (minY - padding).clamp(0, double.infinity);
      maxY = maxY + padding;
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFE2E8F0),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textSecondary,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: data.length > 6 ? (data.length / 4).ceilToDouble() : 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final d = data[index];
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${d.date.month}/${d.date.day}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
                borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: color.withAlpha(200),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.spotIndex;
                final d = data[index];
                return LineTooltipItem(
                  '${d.date.month}/${d.date.day}\n${d.value.toStringAsFixed(0)}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (!event.isInterestedForInteractions ||
                response == null ||
                response.lineBarSpots == null) {
              onTouched(-1);
              return;
            }
            onTouched(response.lineBarSpots!.first.spotIndex);
          },
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              data.length,
              (i) => FlSpot(i.toDouble(), data[i].value),
            ),
            isCurved: true,
            curveSmoothness: 0.3,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: touchIndex == index ? 5 : 3,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withAlpha(25),
            ),
          ),
        ],
      ),
    );
  }
}


