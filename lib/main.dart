// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart'; // <-- novo
import 'Homepage.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/tenant/tenant_join_create_page.dart';
import 'features/tenant/tenant_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SmartStockApp()));
}

class SmartStockApp extends ConsumerWidget {
  const SmartStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider); // <-- observa modo

    return MaterialApp(
      title: 'SmartStock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode, // <-- aplica modo
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
      },
      home: const Gate(),
    );
  }
}

/// Gate decide: sem login -> Login; logado sem loja -> Join/Create; logado c/ loja -> Home
class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final user = snap.data;
        if (user == null) return const LoginPage();

        final tenantId = ref.watch(tenantIdProvider);
        if (tenantId == null) return const TenantJoinCreatePage();

        return const HomePage();
      },
    );
  }
}
