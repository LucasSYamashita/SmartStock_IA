import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';

// Páginas
import 'package:smartstock_flutter_only/Homepage.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/tenant/tenant_gate.dart';
import 'features/tenant/tenant_provider.dart';

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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
      },
      home: const Gate(),
    );
  }
}

class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1) Observa login/logout
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = authSnap.data;
        if (user == null) return const LoginPage();

        // 2) Se não há tenant selecionado ainda, abre o fluxo de criar/entrar
        final tenantId = ref.watch(tenantIdProvider);
        if (tenantId == null) return const TenantGate();

        // 3) Valida membership com STREAM (reage a mudanças de permissão)
        final docRef = FirebaseFirestore.instance
            .doc('tenants/$tenantId/usuarios/${user.uid}');

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, mSnap) {
            if (mSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            // Se não é mais membro, limpa tenant salvo e volta para TenantGate
            final exists = mSnap.data?.exists ?? false;
            if (!exists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // evita escrever estado durante o build
                ref.read(tenantIdProvider.notifier).set(null);
              });
              return const TenantGate();
            }

            // 4) Tudo certo → Home
            return const HomePage();
          },
        );
      },
    );
  }
}
