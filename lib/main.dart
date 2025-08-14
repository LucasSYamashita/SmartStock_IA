import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartstock_flutter_only/Homepage.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/tenant/tenant_gate.dart';
import 'features/tenant/tenant_provider.dart';

void main() async {
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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routes: {
        '/login': (_) => const LoginPage(),
        // adicione outras rotas nomeadas se quiser
      },
      home: const Gate(),
    );
  }
}

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
        if (tenantId == null) return const TenantGate();

        // valida membership do tenant salvo
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .doc('tenants/$tenantId/usuarios/${user.uid}')
              .get(),
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (!s.hasData || !(s.data!.exists)) {
              // não é mais membro -> limpa tenant salvo e retorna ao fluxo de escolha/criação
              ref.read(tenantIdProvider.notifier).set(null);
              return const TenantGate();
            }
            return const HomePage();
          },
        );
      },
    );
  }
}
