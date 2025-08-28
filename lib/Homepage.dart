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

    // use IndexedStack para manter o estado das telas
    final List<Widget> pages = [
      DashboardPage(onConsultarEstoque: () => setState(() => index = 1)),
      const ProductListPage(),
      const ChatPage(),
      const ProfilePage(),
    ];

    // FAB por aba
    Widget? fab;
    if (index == 0) {
      fab = FloatingActionButton.extended(
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Vender'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ManualSaleCatalogPage()),
          );
        },
      );
    } else if (index == 1 && isAdmin) {
      fab = FloatingActionButton(
        tooltip: 'Novo produto',
        onPressed: () => _addProduct(context),
        child: const Icon(Icons.add),
      );
    }

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
      body: IndexedStack(index: index, children: pages),
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
      floatingActionButton: fab,
    );
  }

  Future<void> _addProduct(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final qtdCtrl = TextEditingController(text: '0');
    final minCtrl = TextEditingController(text: '0');
    final priceCtrl = TextEditingController(text: '0');
    final brandCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo produto'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: brandCtrl,
                decoration:
                    const InputDecoration(labelText: 'Marca (opcional)'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtdCtrl,
                decoration: const InputDecoration(labelText: 'Quantidade'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: minCtrl,
                decoration: const InputDecoration(labelText: 'Estoque mínimo'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                decoration:
                    const InputDecoration(labelText: 'Preço de venda (R\$)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final tenantId = ref.read(tenantIdProvider);
              if (tenantId == null) return;

              final nome = nameCtrl.text.trim();
              final marca = brandCtrl.text.trim();
              final quantidade = int.tryParse(qtdCtrl.text.trim()) ?? 0;
              final minimo = int.tryParse(minCtrl.text.trim()) ?? 0;
              final preco = double.tryParse(
                    priceCtrl.text.trim().replaceAll(',', '.'),
                  ) ??
                  0.0;

              if (nome.isEmpty) return;

              final data = <String, dynamic>{
                'nome': nome,
                'nomeLower': nome.toLowerCase(),
                'quantidade': quantidade,
                'estoqueMinimo': minimo,
                'precoVenda': preco, // campo padrão de preço
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': FieldValue.serverTimestamp(),
              };
              if (marca.isNotEmpty) data['marca'] = marca;

              await FirebaseFirestore.instance
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('produtos')
                  .add(data);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Produto criado.')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
