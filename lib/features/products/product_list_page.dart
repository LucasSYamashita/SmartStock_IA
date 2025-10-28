// lib/features/products/product_list_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import 'products_providers.dart';
import '../../data/models/product.dart';
import 'product_detail_page.dart'; // <-- NOVO

class ProductListPage extends ConsumerWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final async = ref.watch(productsStreamProvider);

    Widget topBar = const SizedBox.shrink();
    if (tenantId != null && tenantId.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '?';
      topBar = Container(
        color: Colors.yellow.withOpacity(.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 6,
          spacing: 8,
          children: [
            Text('Tenant: $tenantId',
                style: Theme.of(context).textTheme.labelSmall),
            Text('UID: $uid', style: Theme.of(context).textTheme.labelSmall),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.visibility),
              label: const Text('Testar leitura'),
              onPressed: () async {
                final db = FirebaseFirestore.instance;
                String msg;
                try {
                  await db
                      .collection('tenants')
                      .doc(tenantId)
                      .collection('produtos')
                      .limit(1)
                      .get();
                  msg = 'OK: leitura permitida.';
                } catch (e) {
                  msg = 'Falhou: $e';
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.handyman),
              label: const Text('Reparar acesso'),
              onPressed: () async {
                try {
                  final db = FirebaseFirestore.instance;
                  final me = FirebaseAuth.instance.currentUser!;
                  await db
                      .collection('tenants')
                      .doc(tenantId)
                      .collection('usuarios')
                      .doc(me.uid)
                      .set({
                    'role': 'staff',
                    'active': true,
                    'displayName': me.displayName ?? '',
                    'email': me.email ?? '',
                    'joinedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  ref.invalidate(productsStreamProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Acesso reparado.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Falhou: $e')));
                  }
                }
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar,
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              final msg = '$e';
              final perm = msg.contains('permission-denied');
              return _Hint(
                icon: Icons.report_gmailerrorred_outlined,
                text: perm
                    ? 'Sem permissão para ler o estoque desta loja.\n\nUse “Testar leitura/Reparar acesso” acima.'
                    : 'Erro ao carregar: $msg',
              );
            },
            data: (items) {
              if (tenantId == null || tenantId.isEmpty) {
                return const _Hint(
                  icon: Icons.info_outline,
                  text: 'Selecione/Crie uma loja (Perfil › Loja).',
                );
              }
              if (items.isEmpty) {
                return const _Hint(
                  icon: Icons.inventory_2_outlined,
                  text: 'Nenhum produto ainda.\nUse o botão “+” para criar.',
                );
              }
              return ListView.separated(
                itemCount: items.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (_, i) {
                  final p = items[i];
                  final baixo = p.quantidade <= p.estoqueMinimo;
                  return ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailPage(productId: p.id),
                        ),
                      );
                    },
                    leading: CircleAvatar(
                      child: Text(
                          p.nome.isNotEmpty ? p.nome[0].toUpperCase() : '?'),
                    ),
                    title: Text(p.nome,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (p.categoria.isNotEmpty) p.categoria,
                      if ((p.sku ?? '').isNotEmpty) 'SKU ${p.sku!}',
                      'Min ${p.estoqueMinimo}',
                    ].join(' • ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Qtd ${p.quantidade}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: baixo ? Colors.red : null)),
                        Text('R\$ ${p.preco.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
