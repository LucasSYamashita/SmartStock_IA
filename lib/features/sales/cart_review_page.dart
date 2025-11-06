import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cart_state.dart';
import 'manual_sale_page.dart' show _fmt;
import 'manual_sale_checkout_page.dart';

class ManualSaleCartPage extends ConsumerWidget {
  const ManualSaleCartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final totalQty = ref.watch(cartTotalQtyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Carrinho')),
      body: items.isEmpty
          ? const Center(child: Text('Seu carrinho está vazio.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                return ListTile(
                  leading: CircleAvatar(
                      child: Text(
                          it.nome.isNotEmpty ? it.nome[0].toUpperCase() : '?')),
                  title: Text(it.nome),
                  subtitle: Text('${it.quantity} × ${_fmt(it.unitPrice)}'),
                  trailing: Text(_fmt(it.total)),
                  onTap: () async {
                    // editar quantidade rapidamente
                    final c = TextEditingController(text: '${it.quantity}');
                    final v = await showDialog<int>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text('Quantidade · ${it.nome}'),
                        content: TextField(
                          controller: c,
                          keyboardType: const TextInputType.numberWithOptions(),
                          decoration: const InputDecoration(hintText: 'Ex.: 3'),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context,
                                  int.tryParse(c.text.trim()) ?? it.quantity),
                              child: const Text('OK')),
                        ],
                      ),
                    );
                    if (v != null) {
                      ref
                          .read(cartProvider.notifier)
                          .setQuantity(it.productId, v);
                    }
                  },
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: items.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ManualSaleCheckoutPage(
                                      focusDiscount: true),
                                ),
                              );
                            },
                      child: Text(
                        'Dar desconto',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('TOTAL: ${_fmt(subtotal)}   •   Itens: $totalQty'),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ManualSaleCheckoutPage(),
                          ),
                        );
                      },
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                    '${items.length} item${items.length == 1 ? '' : 's'} = ${(subtotal)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
