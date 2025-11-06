// lib/Homepage.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/dashboard_page.dart';
import 'features/products/product_list_page.dart' show ProductListPage;
import 'features/chat/chat_page.dart';
import 'features/auth/profile_page.dart';
import 'features/settings/theme_mode_provider.dart';
import 'features/tenant/tenant_provider.dart';
import 'features/tenant/role_providers.dart';
import 'features/tenant/membership_guard.dart';
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
    final tenantId = ref.watch(tenantIdProvider); // pode ser null/empty

    // role: admin > staff > viewer
    final isAdmin = (tenantId != null && tenantId.isNotEmpty)
        ? ref.watch(isAdminProvider(tenantId))
        : false;
    final isStaff = (tenantId != null && tenantId.isNotEmpty)
        ? ref.watch(isStaffProvider(tenantId))
        : false;
    final role = isAdmin ? 'admin' : (isStaff ? 'staff' : 'viewer');

    // >>>>> NOVO: userId para o ChatPage
    final currentUser = FirebaseAuth.instance.currentUser;
    final userId = currentUser?.uid ?? 'anonymous';

    // Aba do Chat: se não houver tenant, mostra aviso simples
    final Widget chatTab = (tenantId == null || tenantId.isEmpty)
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nenhuma loja ativa.\nAbra/entre em uma loja para usar o Chat.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          )
        : ChatPage(
            tenantId: tenantId,
            role: role,
            userId: userId, // <<<<< passando userId
          );

    final pages = <Widget>[
      DashboardPage(onConsultarEstoque: () => setState(() => index = 1)),
      const RequireMember(child: ProductListPage()),
      // ⚠️ Sem const aqui; passamos tenantId/role/userId dinamicamente
      RequireMember(child: chatTab),
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

    final title = (tenantId == null || tenantId.isEmpty)
        ? 'SmartStock'
        : 'SmartStock · $tenantId';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
              await ref.read(tenantIdProvider.notifier).clear();
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

  double _parsePreco(String raw) {
    final s = raw
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }

  /// Diálogo: criar produto (+ LOG de entrada inicial, se quantidade > 0).
  Future<void> _addProduct(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController(); // apenas visual
    final qtdCtrl = TextEditingController(text: '0');
    final minCtrl = TextEditingController(text: '1'); // padrão 1
    final priceCtrl = TextEditingController(text: '0');

    String? err;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> save() async {
            final tenantId = ref.read(tenantIdProvider);
            if (tenantId == null || tenantId.isEmpty) return;

            setLocal(() => err = null);

            final nome = nameCtrl.text.trim();
            final quantidade = int.tryParse(qtdCtrl.text.trim()) ?? 0;
            final minimo = int.tryParse(minCtrl.text.trim()) ?? 1;
            final preco = _parsePreco(priceCtrl.text);

            if (nome.isEmpty) {
              setLocal(() => err = 'Informe o nome.');
              return;
            }
            if (quantidade < 0 || minimo < 0 || preco < 0) {
              setLocal(() => err = 'Valores não podem ser negativos.');
              return;
            }

            try {
              // >>>>> mais seguro: evitar crash se não logado
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                setLocal(() => err = 'Faça login para criar produtos.');
                return;
              }
              final uid = user.uid;

              // Campos compatíveis com as regras
              final data = <String, dynamic>{
                'nome': nome,
                'nomeLower': nome.toLowerCase(),
                'categoria': '',
                'sku': '',
                'preco': preco,
                'quantidade': quantidade,
                'estoqueMinimo': minimo,
                'ativo': true,
                'createdAt': FieldValue.serverTimestamp(),
                'createdBy': uid,
                'updatedAt': FieldValue.serverTimestamp(),
                'updatedBy': uid,
              };

              // 1) cria o produto
              final doc = await FirebaseFirestore.instance
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('produtos')
                  .add(data);

              // 2) Fecha modal e dá sucesso imediatamente
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Produto criado.')),
              );

              // 3) Tenta registrar histórico de entrada sem afetar a UI
              if (quantidade > 0) {
                try {
                  await FirebaseFirestore.instance
                      .collection('tenants')
                      .doc(tenantId)
                      .collection('movimentos')
                      .add({
                    'tipo': 'entrada',
                    'quantidade': quantidade,
                    'produtoId': doc.id,
                    'produtoNome': nome,
                    'usuarioId': uid,
                    'origem': 'create_product',
                    'motivo': 'cadastro inicial',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Produto salvo; não foi possível registrar histórico: $e',
                        ),
                      ),
                    );
                  }
                }
              }
            } on FirebaseException catch (e) {
              setLocal(() => err = '${e.code}: ${e.message}');
            } catch (e) {
              setLocal(() => err = e.toString());
            }
          }

          return AlertDialog(
            title: const Text('Novo produto'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: brandCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Marca (apenas visual — não é salva)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtdCtrl,
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: minCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Estoque mínimo'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Preço de venda (R\$)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child:
                          Text(err!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: save, child: const Text('Salvar')),
            ],
          );
        },
      ),
    );
  }
}
