import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/device_info_service.dart';
import '../services/socket_service.dart';

/// 默认班级常量（可从配置文件动态读取）
const String _defaultClassId = '初一01班';

class AuthProvider extends ChangeNotifier {
  ApiService _apiService = ApiService(); // 默认实例
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  /// 设置 API 服务（由 Provider 注入）
  void setApiService(ApiService apiService) {
    _apiService = apiService;
  }

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 获取默认班级（从配置读取或使用fallback）
  String _getDefaultClass() {
    return _defaultClassId;
  }

  Future<void> attemptAutoLogin() async {
    // 延迟到下一个帧，避免在 build 阶段调用 notifyListeners
    await Future.delayed(const Duration(milliseconds: 1));

    _isLoading = true;
    notifyListeners();

    try {
      // 获取当前设备信息
      final currentComputerName = await DeviceInfoService.getComputerName();
      final currentIpAddress = await DeviceInfoService.getIpAddress();

      print('=== 学生端自动登录 ===');
      print('电脑名称: $currentComputerName');
      print('IP地址: $currentIpAddress');

      // 从教师端获取学生注册信息
      final studentInfo =
          await _getStudentFromTeacher(currentComputerName, currentIpAddress);

      if (studentInfo != null) {
        // 找到匹配的学生，自动登录
        _currentUser = UserModel(
          id: studentInfo['id'] ?? '',
          name: studentInfo['name'] ?? '',
          role: 'student',
          classId: studentInfo['class_id'] ?? '',
          computerName: currentComputerName,
          ip: currentIpAddress,
        );

        // 保存登录信息
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auto_login_user_id', _currentUser!.id);
        await prefs.setString('computer_name', currentComputerName);
        await prefs.setString('ip_address', currentIpAddress);
        await prefs.setString('saved_name', studentInfo['name'] ?? '');
        final pw = studentInfo['password']?.toString() ?? '';
        if (pw.isNotEmpty) {
          await prefs.setString('saved_password', pw);
        }

        // 连接教师端Socket
        _connectToTeacher();

        _isLoading = false;
        notifyListeners();
        return;
      }

      // 如果没有找到匹配的学生，不进行本地回退登录
      // 必须连接教师端才能使用学生端
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 从教师端获取学生信息
  Future<Map<String, dynamic>?> _getStudentFromTeacher(
      String computerName, String ipAddress) async {
    try {
      print('正在从教师端查找学生...');
      print('请求数据: computer_name=$computerName, ip=$ipAddress');

      // 调用教师端API获取学生列表
      final response = await _apiService.post('/student/find', {
        'computer_name': computerName,
        'ip': ipAddress,
      });

      print('教师端响应: $response');

      if (response.containsKey('student')) {
        final student = response['student'];
        if (student != null && (student is Map) && student.isNotEmpty) {
          print('找到学生: ${student['name']}');
          return student.cast<String, dynamic>();
        }
      }
      print('未找到匹配的学生');
    } catch (e) {
      print('查找学生失败: $e');
    }
    return null;
  }

  Future<bool> login(String name, String password) async {
    // 延迟到下一个帧，避免在 build 阶段调用 notifyListeners
    await Future.delayed(const Duration(milliseconds: 1));

    _isLoading = true;
    _error = null;
    notifyListeners();

    // 获取当前设备信息
    final currentComputerName = await DeviceInfoService.getComputerName();
    final currentIpAddress = await DeviceInfoService.getIpAddress();

    // 从 SharedPreferences 读取注册时的设备信息
    final prefs = await SharedPreferences.getInstance();
    final registeredComputerName = prefs.getString('computer_name') ?? '';
    final registeredIpAddress = prefs.getString('ip_address') ?? '';

    // 检查设备是否匹配（只在有注册记录时检查）
    if (registeredComputerName.isNotEmpty && registeredIpAddress.isNotEmpty) {
      // 如果当前设备与注册设备不一致，拒绝登录
      if (currentComputerName != registeredComputerName ||
          currentIpAddress != registeredIpAddress) {
        _error = '请在注册的电脑上登录';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }

    try {
      // 调用API进行登录验证
      final response = await _apiService.post('/auth/login', {
        'name': name,
        'password': password,
        'computer_name': currentComputerName,
        'ip': currentIpAddress,
      });

      if (response.containsKey('success') && response['success'] == true) {
        final data = response['data'] ?? response;
        _currentUser = UserModel.fromJson(data['user'] ?? data);

        // 保存登录状态（用于自动登录）
        await prefs.setString('auto_login_user_id', _currentUser!.id);
        await prefs.setString('saved_name', name);
        await prefs.setString('saved_password', password);
        if (data['token'] != null) {
          await prefs.setString('auth_token', data['token']);
        }

        // 连接教师端Socket
        _connectToTeacher();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? '登录失败';
      }
    } catch (e) {
      // API调用失败，不允许本地回退登录
      // 必须连接教师端才能登录
      _error = '无法连接教师端，请确认教师端已启动';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register(String name, String password, String classId) async {
    // 延迟到下一个帧，避免在 build 阶段调用 notifyListeners
    await Future.delayed(const Duration(milliseconds: 1));

    _isLoading = true;
    _error = null;
    notifyListeners();

    // 获取设备信息
    final computerName = await DeviceInfoService.getComputerName();
    final ipAddress = await DeviceInfoService.getIpAddress();

    try {
      // 调用API进行注册
      final response = await _apiService.post('/auth/register', {
        'name': name,
        'password': password,
        'class_id': classId,
        'role': 'student',
        'computer_name': computerName,
        'ip': ipAddress,
      });

      if (response.containsKey('success') && response['success'] == true) {
        final data = response['data'] ?? response;
        _currentUser = UserModel.fromJson(data['user'] ?? data);

        // 保存登录状态和设备信息
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auto_login_user_id', _currentUser!.id);
        if (data['token'] != null) {
          await prefs.setString('auth_token', data['token']);
        }
        await prefs.setString('computer_name', computerName);
        await prefs.setString('ip_address', ipAddress);

        // 同步学生信息到教师端
        await _syncStudentToTeacher(name, classId, computerName, ipAddress,
            password: password);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? '注册失败';
      }
    } catch (e) {
      // API调用失败，不允许本地回退注册
      // 必须连接教师端才能注册
      _error = '无法连接教师端，请确认教师端已启动';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auto_login_user_id');
    await prefs.remove('auth_token');

    // 断开 Socket 连接
    try {
      final socketService = SocketService.instance;
      socketService.disconnect();
    } catch (e) {
      // 忽略错误
    }

    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 更新当前用户信息（如班级切换后更新姓名等）
  void updateCurrentUser(UserModel updatedUser) {
    _currentUser = updatedUser;
    notifyListeners();
  }

  // 同步学生信息到教师端
  Future<void> _syncStudentToTeacher(
    String name,
    String classId,
    String computerName,
    String ipAddress, {
    String? password,
  }) async {
    try {
      // 通过 HTTP 请求将学生信息发送到教师端
      final studentId =
          _currentUser?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

      final response = await _apiService.post('/student/register', {
        'id': studentId,
        'name': name,
        'password': password,
        'class_id': classId,
        'computer_name': computerName,
        'ip': ipAddress,
      });

      print('学生信息已同步到教师端: $response');
    } catch (e) {
      print('同步学生信息到教师端失败: $e');
      // 忽略同步错误，不影响注册流程
    }
  }

  // 连接到教师端Socket
  void _connectToTeacher() {
    if (_currentUser != null) {
      try {
        final socketService = SocketService.instance;
        socketService.connect(_currentUser!.id);
      } catch (e) {
        print('连接教师端失败: $e');
      }
    }
  }
}
