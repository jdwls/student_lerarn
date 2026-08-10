import 'dart:io';

/// 单实例服务，确保一台电脑只能启动一个学生端
/// 使用 RawServerSocket 绑定本地端口实现
class SingleInstanceService {
  static const int _port = 20023; // 固定端口，用于检测是否已有实例运行
  static ServerSocket? _serverSocket;

  /// 尝试获取单实例锁
  /// 返回 true 表示成功获取（没有其他实例运行）
  /// 返回 false 表示已有其他实例在运行
  static Future<bool> tryAcquire() async {
    try {
      _serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
      // 保持 socket 监听，防止端口被释放
      _serverSocket!.listen((_) {});
      return true;
    } on SocketException catch (e) {
      // 只有明确的地址占用才表示已有学生端实例；其他错误不能误判为重复启动。
      if (e.osError?.errorCode == 10048) return false;
      rethrow;
    }
  }

  /// 释放单实例锁（应用退出时调用）
  static Future<void> release() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }
}
