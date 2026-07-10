import 'package:flutter/material.dart';

/// 登录/注册页面共用的输入行组件
class InputRow extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const InputRow({
    super.key,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(icon, size: 18, color: const Color(0xFF4338CA)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}