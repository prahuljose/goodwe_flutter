import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../repositories/auth_repository.dart';
import '../features/login/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';

class GoodWeApp extends StatelessWidget {
  const GoodWeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoodWe Monitor',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const _SplashRouter(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DashboardScreen(),
      },
    );
  }
}

/// Checks for a saved session on startup and routes accordingly
class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final auth = context.read<AuthRepository>();
    final hasSession = await auth.tryRestoreSession();

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      hasSession ? '/dashboard' : '/login',
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.solar_power, size: 56, color: AppColors.accent),
            SizedBox(height: 16),
            Text(
              'GoodWe Monitor',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
