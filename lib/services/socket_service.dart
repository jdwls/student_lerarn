import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../utils/app_path.dart';

typedef SocketMessageCallback = void Function(Map<String, dynamic> message);

class SocketService {
  static SocketService? _instance;
  static SocketService get instance => _instance ??= SocketService._();

  Socket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  String? _studentId;
  bool _isConnected = false;
  bool _disposed = false;
  String _currentStatus = 'online';
  final _connectionController = StreamController<bool>.broadcast();
  bool _intentionalDisconnect = false;
  String _messageBuffer = ''; // TCP消息缓冲区（防止粘包/半包）

  static String _serverIp = 'localhost';
  static const int _socketPort = 20021;

  /// 学生端当前上报状态（online/typing/exam 等），供第三方服务判定所处场景
  String get currentStatus => _currentStatus;

  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 60;
  static const int _baseReconnectDelay = 1;
  static const int _maxReconnectAttempts = 10;

  int _heartbeatInterval = 5;
  final List<SocketMessageCallback> _messageCallbacks = [];

  SocketService._();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;

  void addMessageCallback(SocketMessageCallback cb) =>
      _messageCallbacks.add(cb);
  void removeMessageCallback(SocketMessageCallback cb) =>
      _messageCallbacks.remove(cb);

  int _getReconnectDelay() {
    final d = _baseReconnectDelay * (1 << _reconnectAttempts);
    return d > _maxReconnectDelay ? _maxReconnectDelay : d;
  }

  static Future<void> init() async {
    try {
      final f = File(AppPath.configFilePath);
      if (await f.exists()) {
        final data =
            json.decode(await f.readAsString()) as Map<String, dynamic>;
        _serverIp = data['server_ip'] ?? 'localhost';
      }
    } catch (_) {}
  }

  Future<void> connect(String studentId) async {
    if (_disposed) return;
    _intentionalDisconnect = false;
    if (_isConnected) return;
    _studentId = studentId;
    try {
      _socket = await Socket.connect(_serverIp, _socketPort)
          .timeout(const Duration(seconds: 10));
      _isConnected = true;
      _connectionController.add(true);
      _reconnectAttempts = 0;
      _socket!.listen(
        _onData,
        onError: (_) {
          _isConnected = false;
          _connectionController.add(false);
          if (!_intentionalDisconnect) _reconnect();
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
          if (!_intentionalDisconnect) _reconnect();
        },
      );
      _startHeartbeat();
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      if (!_intentionalDisconnect) _reconnect();
    }
  }

  void _onData(Uint8List data) {
    _messageBuffer += utf8.decode(data);
    // 按换行符分割消息（协议：每条JSON消息以\n结尾），防止粘包/半包
    while (_messageBuffer.contains('\n')) {
      final splitIndex = _messageBuffer.indexOf('\n');
      final message = _messageBuffer.substring(0, splitIndex);
      _messageBuffer = _messageBuffer.substring(splitIndex + 1);
      if (message.isEmpty) continue;
      _processMessage(message);
    }
  }

  void _processMessage(String msg) {
    try {
      final data = json.decode(msg) as Map<String, dynamic>;
      switch (data['type'] as String? ?? '') {
        case 'kickout':
          _intentionalDisconnect = true;
          disconnect();
          break;
        case 'status_query':
          _sendHeartbeat();
          break;
        default:
          break;
      }
      for (final cb in _messageCallbacks) {
        try {
          cb(data);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
        Duration(seconds: _heartbeatInterval), (_) => _sendHeartbeat());
  }

  void _sendHeartbeat() {
    if (_socket != null && _isConnected && _studentId != null) {
      try {
        _socket!.write('${json.encode({
              "type": "heartbeat",
              "student_id": _studentId,
              "status": _currentStatus
            })}\n');
      } catch (_) {}
    }
  }

  void updateStatus(String status) {
    _currentStatus = status;
    if (_socket != null && _isConnected && _studentId != null) {
      try {
        _socket!.write('${json.encode({
              "type": "status_update",
              "student_id": _studentId,
              "status": status
            })}\n');
      } catch (_) {}
    }
  }

  void _reconnect() {
    if (_disposed ||
        _intentionalDisconnect ||
        _reconnectAttempts >= _maxReconnectAttempts) return;
    final d = _getReconnectDelay();
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: d), () {
      if (!_disposed &&
          !_isConnected &&
          _studentId != null &&
          !_intentionalDisconnect) {
        connect(_studentId!);
      }
    });
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.close();
    _socket = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    _disposed = true;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.close();
    _socket = null;
    _isConnected = false;
    if (!_connectionController.isClosed) _connectionController.close();
  }
}
