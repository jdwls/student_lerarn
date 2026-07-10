import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class UserProvider extends ChangeNotifier {
  final ApiService _apiService;
  UserModel? _currentUser;
  int _points = 0;
  String? _classLabel;
  List<Map<String, dynamic>> _examResults = [];
  List<Map<String, dynamic>> _typingResults = [];
  bool _isLoading = false;
  String? _error;

  UserProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  UserModel? get currentUser => _currentUser;
  int get points => _points;
  String? get classLabel => _classLabel;
  List<Map<String, dynamic>> get examResults => _examResults;
  List<Map<String, dynamic>> get typingResults => _typingResults;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void setUser(UserModel user) {
    _currentUser = user;
    _classLabel = user.classId;
    notifyListeners();
  }

  /// 直接设置积分（班级切换后从教师端获取）
  void setPointsDirectly(int points) {
    _points = points;
    notifyListeners();
  }

  Future<void> loadUserData(String userId) async {
    // 延迟到下一个帧，避免在 build 阶段调用 notifyListeners
    await Future.delayed(const Duration(milliseconds: 1));

    _isLoading = true;
    notifyListeners();

    try {
      // 从教师端获取学生信息（包含积分）
      if (_currentUser != null &&
          (_currentUser!.computerName ?? '').isNotEmpty &&
          (_currentUser!.ip ?? '').isNotEmpty) {
        final response = await _apiService.post('/student/find', {
          'computer_name': _currentUser!.computerName,
          'ip': _currentUser!.ip,
        });
        if (response.containsKey('student') && response['student'] != null) {
          final student = response['student'] as Map<String, dynamic>;
          _points = student['points'] as int? ?? 0;
          _classLabel = student['class_id'] ?? _classLabel;
        }
      }
    } catch (e) {
      // API失败时保持当前积分
      print('从教师端获取积分失败: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 更新积分：以教师端为权威数据源
  /// 先本地乐观更新（保证UI即时响应），然后同步到教师端，
  /// 用教师端返回的权威值覆盖本地值（教师端可能有每日上限等规则）
  Future<void> updatePoints(int delta) async {
    if (delta <= 0 || _currentUser == null) return;

    // 先本地乐观更新，保证UI即时响应
    _points += delta;
    notifyListeners();

    // 同步到教师端，用教师端返回的权威值覆盖本地
    try {
      final response = await _apiService.post('/student/update-points', {
        'student_id': _currentUser!.id,
        'delta': delta,
      });
      if (response['success'] == true) {
        // 用教师端返回的权威积分值覆盖本地值
        final teacherPoints = response['points'] as int?;
        if (teacherPoints != null) {
          _points = teacherPoints;
          notifyListeners();
        }
      } else {
        // 教师端处理失败，回滚本地乐观更新
        _points -= delta;
        notifyListeners();
        print('教师端更新积分失败，已回滚本地积分');
      }
    } catch (e) {
      // 网络失败时保持本地乐观更新（下次刷新时会从教师端同步真实值）
      print('同步积分到教师端失败: $e（本地积分保持乐观更新）');
    }
  }

  void addExamResult(Map<String, dynamic> result) {
    _examResults.add(result);
    notifyListeners();
  }

  /// 添加打字结果记录
  /// 注意：积分由 _saveTypingScoreToServer 通过教师端 /score/typing API 同步，
  /// 教师端会调用 _syncStudentTotalPoints 重新计算总积分，
  /// 所以这里不需要再调用 updatePoints，否则会重复计算积分
  void addTypingResult(Map<String, dynamic> result) {
    _typingResults.add(result);
    notifyListeners();
  }

  /// 保存积分变动到教师端成绩目录（积分增加详细表）
  /// 此方法仅用于记录积分变动明细，不影响积分计算
  Future<void> savePointsRecordToServer(int delta) async {
    if (_currentUser == null) return;
    try {
      await _apiService.post('/score/points', {
        'student_id': _currentUser!.id,
        'student_name': _currentUser!.name,
        'points': delta,
        'class_id': _classLabel ?? '',
      });
    } catch (e) {
      print('保存积分变动记录失败: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _currentUser = null;
    _points = 0;
    _classLabel = null;
    _examResults = [];
    _typingResults = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
