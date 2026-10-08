import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/input_row.dart';
import 'register_page.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    // 等待一帧让页面先渲染
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    // 按设备信息自动登录（电脑名+IP匹配）
    await authProvider.attemptAutoLogin();
    if (mounted && authProvider.isLoggedIn) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainHomePage()),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('login_username') ?? '';
      final savedRemember = prefs.getBool('login_remember') ?? false;
      if (savedName.isNotEmpty && savedRemember) {
        _nameController.text = savedName;
        _rememberMe = true;
      }
    } catch (_) {}
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final apiService = ApiService();

      final teacherActive = await apiService.checkTeacherActive();

      if (!teacherActive) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请等待教师端开启后登录'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      final success = await authProvider.login(
        _nameController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('login_username', _nameController.text.trim());
        } else {
          await prefs.remove('login_username');
        }
        await prefs.setBool('login_remember', _rememberMe);

        // ignore: use_build_context_synchronously
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainHomePage()),
        );
      } else if (mounted && authProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error!),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(title: 'Student - 登录'),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFEEF5FF),
                    Color(0xFFFAFBFF),
                    Color(0xFFEAF2FF)
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // 背景装饰光晕
                  const Positioned(
                    top: -110,
                    right: -60,
                    child: _GlowCircle(size: 320, color: Color(0x2E60A5FA)),
                  ),
                  const Positioned(
                    bottom: -130,
                    left: -70,
                    child: _GlowCircle(size: 360, color: Color(0x2EA78BFA)),
                  ),
                  const Positioned(
                    top: 200,
                    left: 60,
                    child: _GlowCircle(size: 170, color: Color(0x1A2563EB)),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            border: Border.all(color: const Color(0xFFE8EDF7)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F2563EB),
                                blurRadius: 50,
                                offset: Offset(0, 22),
                                spreadRadius: -10,
                              ),
                              BoxShadow(
                                color: Color(0x0D0F172A),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF60A5FA),
                                        Color(0xFFA78BFA)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x5960A5FA),
                                        blurRadius: 24,
                                        offset: Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.lock_rounded,
                                        size: 34, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  '欢迎回来',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '请登录你的学生账号，开始今天的学习',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 16),
                                InputRow(
                                  icon: Icons.badge_rounded,
                                  child: TextFormField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      hintText: '用户名',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return '请输入用户名';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                InputRow(
                                  icon: Icons.key_rounded,
                                  child: TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      hintText: '密码',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return '请输入密码';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      activeColor: AppTheme.primaryColor,
                                      onChanged: (value) {
                                        setState(() {
                                          _rememberMe = value ?? false;
                                        });
                                      },
                                    ),
                                    Text(
                                      '记住我',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Consumer<AuthProvider>(
                                  builder: (context, auth, _) {
                                    return MouseRegion(
                                      cursor: auth.isLoading
                                          ? SystemMouseCursors.wait
                                          : SystemMouseCursors.click,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        width: double.infinity,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          gradient: auth.isLoading
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF93B8F5),
                                                    Color(0xFFB4C6F0)
                                                  ],
                                                )
                                              : const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Color(0xFF2563EB),
                                                    Color(0xFF4F8DF7)
                                                  ],
                                                ),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          boxShadow: auth.isLoading
                                              ? null
                                              : const [
                                                  BoxShadow(
                                                    color: Color(0x592563EB),
                                                    blurRadius: 18,
                                                    offset: Offset(0, 8),
                                                  ),
                                                ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: auth.isLoading
                                                ? null
                                                : _handleLogin,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            child: Center(
                                              child: auth.isLoading
                                                  ? const SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2.4,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Text(
                                                      '登  录',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors.white,
                                                        letterSpacing: 4,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '还没有账号？',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const RegisterPage(),
                                            ),
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              AppTheme.primaryColor,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          textStyle: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        child: const Text('注册新账号'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景装饰光晕圆
class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withAlpha(0),
          ],
        ),
      ),
    );
  }
}
