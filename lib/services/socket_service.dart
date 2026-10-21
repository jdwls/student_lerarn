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
  Uint8List _byteBuffer = Uint8List(0); // 字节级缓冲（防止粘包/半包、跨块截断多字节UTF-8）

  static String _serverIp = 'localhost';
  static const int _socketPort = 20021;

  /// 学生端当前上报状态（online/typing/exam 等），供第三方服务判定所处场景
  String get currentStatus => _currentStatus;

  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 60;
  static const int _baseReconnectDelay = 1;

  final int _heartbeatInterval = 5;
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
    // 先累积字节缓冲，找到消息结束(\n)后按字节切分，再逐条 UTF-8 解码。
    // 直接对每个 TCP 块单独 utf8.decode 会把跨块的多字节中文截断报错。
    _byteBuffer = _byteBuffer.isEmpty
        ? data
        : Uint8List.fromList([..._byteBuffer, ...data]);
    while (true) {
      final nl = _byteBuffer.indexOf(0x0A);
      if (nl < 0) break;
      final lineBytes = Uint8List.sublistView(_byteBuffer, 0, nl);
      _byteBuffer = Uint8List.sublistView(_byteBuffer, nl + 1);
      if (lineBytes.isEmpty) continue;
      try {
        _processMessage(utf8.decode(lineBytes));
      } catch (_) {}
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
    // 不设重连次数上限：指数退避到 _maxReconnectDelay 后保持固定间隔轮询，
    // 保证教师端稍后恢复在线时学生端仍能自动重连。
    if (_disposed || _intentionalDisconnect) return;
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
    _byteBuffer = Uint8List(0); // 清空残余半包数据
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
