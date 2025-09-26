// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart'; // gerado pelo flutterfire configure
import 'theme/app_theme.dart'; // se não tiver, troque por ThemeData(...)
import 'Homepage.dart'; // sua home
import 'features/auth/login_page.dart'; // tela de login
import 'features/auth/register_page.dart'; // tela de cadastro (se usar)
import 'features/tenant/tenant_join_create_page.dart'; // entrar/criar loja
import 'features/tenant/tenant_provider.dart'; // provider do tenantId

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SmartStockApp()));
}

class SmartStockApp extends StatelessWidget {
  const SmartStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartStock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light, // se não tiver AppTheme, use ThemeData.light()
      darkTheme: AppTheme.dark, // ou remova o darkTheme
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) {
          return const LoginPage();
        }

        final tenantId = ref.watch(tenantIdProvider);
        if (tenantId == null) {
          return const TenantJoinCreatePage();
        }

        return const HomePage();
      },
    );
  }
}
