import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/store.dart';
import '../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final u = _user.text.trim();
    final p = _pwd.text;
    if (u.isEmpty || p.isEmpty) return;
    setState(() => _busy = true);
    try {
      await LKApi.login(u, p);
      await LKStore.save();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showLkError(context, _loginError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _loginError(Object error) {
    if (error is LKException) {
      return switch (error.code) {
        2 => '密码错误，请检查后重试',
        1001 => '账号不存在，请确认登录邮箱是否正确',
        _ => error.message.isEmpty ? '登录失败，请稍后重试' : error.message,
      };
    }
    return '登录失败，请检查网络后重试';
  }

  @override
  Widget build(BuildContext context) {
    final s = LKClient.shared.session;
    return Scaffold(
      appBar: AppBar(title: const Text('登录轻之国度')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E2025)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade300,
                            Colors.indigo.shade600
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color:
                                  Colors.indigo.shade200.withValues(alpha: 0.6),
                              blurRadius: 12,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.menu_book_rounded,
                          size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _user,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pwd,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.isLoggedIn ? '重新登录' : '登 录'),
                    ),
                    if (s.isLoggedIn) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () async {
                          await LKApi.logout();
                          await LKStore.clear();
                          if (!context.mounted) return;
                          setState(() {});
                          showLkError(context, '已退出登录');
                        },
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent),
                        child: Text('退出登录(当前: ${s.nickname})'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
