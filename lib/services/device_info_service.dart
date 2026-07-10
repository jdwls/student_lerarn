import 'dart:io';
import 'package:flutter/foundation.dart';

class DeviceInfoService {
  static Future<String> getComputerName() async {
    try {
      // Windows 系统
      if (Platform.isWindows) {
        final name = Platform.localHostname;
        print('获取电脑名称: $name');
        return name;
      }
      // 其他系统
      return Platform.localHostname;
    } catch (e) {
      return 'Unknown';
    }
  }

  static Future<String> getIpAddress() async {
    try {
      // 获取本机 IP 地址
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      print('检测到的网络接口:');
      for (final interface in interfaces) {
        print('  接口: ${interface.name}');
        for (final addr in interface.addresses) {
          print('    地址: ${addr.address}');
        }
      }

      // 收集所有非回环的私有IP地址
      final privateIps = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && isPrivateIp(addr.address)) {
            privateIps.add(addr.address);
          }
        }
      }

      if (privateIps.isNotEmpty) {
        // 优先选择 192.168.x.x（常见家庭/小型局域网）
        // 其次 10.x.x.x（常见学校/企业网络）
        // 最后 172.16-31.x.x
        final ip = privateIps.firstWhere(
          (ip) => ip.startsWith('192.168'),
          orElse: () => privateIps.firstWhere(
            (ip) => ip.startsWith('10.'),
            orElse: () => privateIps.first,
          ),
        );
        print('选择 IP (私有地址): $ip，候选: $privateIps');
        return ip;
      }

      // 如果没有找到私有IP，返回第一个非回环地址
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            final ip = addr.address;
            print('选择 IP (第一个非回环): $ip');
            return ip;
          }
        }
      }

      const ip = '127.0.0.1';
      print('使用默认 IP: $ip');
      return ip;
    } catch (e) {
      return '127.0.0.1';
    }
  }

  /// 判断是否为 RFC 1918 私有IP地址
  /// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
  @visibleForTesting
  static bool isPrivateIp(String ip) {
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }
}
