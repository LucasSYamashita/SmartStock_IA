import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/dashboard_page.dart';
import 'features/products/product_list_page.dart';
import 'features/chat/chat_page.dart';
import 'features/auth/profile_page.dart';
import 'features/settings/theme_mode_provider.dart';
import 'features/tenant/tenant_provider.dart';
import 'features/products/product_list_page.dart' show isAdminProvider;
import 'features/sales/manual_sale_flow.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final tenantId = ref.watch(tenantIdProvider);
    final isAdmin = ref.watch(isAdminProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    final pages = [
      DashboardPage(onConsultarEstoque: () => setState(() => index = 1)),
      const ProductListPage(),
      const ChatPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('SmartStock${tenantId != null ? ' · $tenantId' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Alternar tema',
            icon: Icon(
                mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              final n = ref.read(themeModeProvider.notifier);
              n.state =
                  mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref
                  .read(tenantIdProvider.notifier)
                  .set(null); // limpa tenant salvo
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Estoque',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
      floatingActionButton: switch (index) {
        0 => FloatingActionButton.extended(
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Vender'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ManualSaleCatalogPage()),
              );
            },
          ),
        1 => isAdmin
            ? FloatingActionButton(
                tooltip: 'Novo produto',
                onPressed: () => _addProduct(context),
                child: const Icon(Icons.add),
              )
            : null,
        _ => null,
      },
    );
  }

  Future<void> _addProduct(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final qtdCtrl = TextEditingController(text: '0');
    final minCtrl = TextEditingController(text: '0');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo produto'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nome')),
              const SizedBox(height: 8),
              TextField(
                  controller: qtdCtrl,
                  decoration: const InputDecoration(labelText: 'Quantidade'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(
                  controller: minCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Estoque mínimo'),
                  keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final tenantId = ref.read(tenantIdProvider);
              if (tenantId == null) return;

              final nome = nameCtrl.text.trim();
              final quantidade = int.tryParse(qtdCtrl.text.trim()) ?? 0;
              final minimo = int.tryParse(minCtrl.text.trim()) ?? 0;
              if (nome.isEmpty) return;

              await FirebaseFirestore.instance
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('produtos')
                  .add({
                'nome': nome,
                'nomeLower': nome.toLowerCase(),
                'quantidade': quantidade,
                'estoqueMinimo': minimo,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
