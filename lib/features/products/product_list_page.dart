// lib/features/products/product_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import 'products_providers.dart';
import '../../data/models/product.dart';
import 'product_detail_page.dart';

class ProductListPage extends ConsumerWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final async = ref.watch(productsStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // (sem topo de debug)
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Hint(
              icon: Icons.report_gmailerrorred_outlined,
              text: 'Erro ao carregar: $e',
            ),
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
                        p.nome.isNotEmpty ? p.nome[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(
                      p.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text([
                      if (p.categoria.isNotEmpty) p.categoria,
                      if ((p.sku ?? '').isNotEmpty) 'SKU ${p.sku!}',
                      'Min ${p.estoqueMinimo}',
                    ].join(' • ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Qtd ${p.quantidade}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: baixo ? Colors.red : null,
                          ),
                        ),
                        Text(
                          'R\$ ${p.preco.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
