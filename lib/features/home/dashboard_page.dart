import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smartstock_flutter_only/features/auth/profile_page.dart';
import 'package:smartstock_flutter_only/features/inbound/manual_entry_page.dart';
// Ajuste o import conforme seu caminho real:
import '../sales/manual_sale_page.dart' show ManualSaleCatalogPage;

import '../tenant/tenant_provider.dart';

/// Helpers
num _toNum(dynamic any, {num def = 0}) {
  if (any is num) return any;
  return num.tryParse('$any') ?? def;
}

String _fmtCurrency(num v) =>
    'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Produtos do tenant atual
final _productsSnapProvider =
    StreamProvider.autoDispose<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .snapshots();
});

/// Vendas do mês corrente (filtra por createdAt >= 1º dia do mês)
final _vendasMesSnapProvider =
    StreamProvider.autoDispose<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  final now = DateTime.now();
  final firstOfMonth = DateTime(now.year, now.month, 1);
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('vendas')
      .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(firstOfMonth))
      .snapshots();
});

class DashboardPage extends ConsumerWidget {
  final VoidCallback onConsultarEstoque;
  const DashboardPage({super.key, required this.onConsultarEstoque});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Center(
        child: Text('Nenhuma loja selecionada. Crie/entre em uma loja.'),
      );
    }

    final productsAsync = ref.watch(_productsSnapProvider);
    final vendasAsync = ref.watch(_vendasMesSnapProvider);

    // Métricas derivadas de produtos
    num saldoEstoque = 0;
    int totalProdutos = 0;
    int semEstoque = 0;
    int baixo = 0;

    final prodDocs = productsAsync.valueOrNull?.docs ?? const [];
    totalProdutos = prodDocs.length;
    for (final d in prodDocs) {
      final m = d.data();
      final q =
          _toNum(m['quantidade'] ?? m['Quantidade']).toInt().clamp(0, 1 << 31);
      final v = _toNum(m['valor'] ?? m['preco'] ?? m['precoVenda'])
          .toDouble()
          .clamp(0, double.infinity);
      final min = _toNum(m['estoqueMinimo'] ?? m['EstoqueMinimo'])
          .toInt()
          .clamp(0, 1 << 31);

      saldoEstoque += q * v;
      if (q <= 0) {
        semEstoque++;
      } else if (q <= min) {
        baixo++;
      }
    }

    // Métrica de vendas do mês (soma do campo "total")
    num vendasDoMes = 0;
    final venDocs = vendasAsync.valueOrNull?.docs ?? const [];
    for (final d in venDocs) {
      vendasDoMes += _toNum(d.data()['total']).toDouble();
    }

    // Estado de carregamento/erro (mostra aviso, mas mantém UI com valores parciais)
    final isLoading = productsAsync.isLoading || vendasAsync.isLoading;
    final hasError = productsAsync.hasError || vendasAsync.hasError;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Alguns dados não puderam ser carregados agora.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),

        // KPIs
        Row(
          children: [
            Expanded(
              child: _BigStatCard(
                title: 'Vendas do mês',
                value: _fmtCurrency(vendasDoMes),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigStatCard(
                title: 'Produtos',
                value: '$totalProdutos',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TagCard(
                title: 'Sem estoque',
                value: '$semEstoque',
                color: Theme.of(context).colorScheme.errorContainer,
                onColor: Theme.of(context).colorScheme.onErrorContainer,
                icon: Icons.block,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TagCard(
                title: 'Estoque baixo',
                value: '$baixo',
                color: Theme.of(context).colorScheme.secondaryContainer,
                onColor: Theme.of(context).colorScheme.onSecondaryContainer,
                icon: Icons.warning_amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Grade de botões (menus)
        GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.6,
          children: [
            _MenuPill(
              icon: Icons.point_of_sale,
              label: 'Vender',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ManualSaleCatalogPage()),
                );
              },
            ),
            _MenuPill(
              icon: Icons.receipt_long,
              label: 'Relatórios',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Relatórios em breve 😊')),
                );
              },
            ),
            _MenuPill(
              icon: Icons.inventory_rounded,
              label: 'Entrada manual',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManualEntryPage()),
                );
              },
            ),
            _MenuPill(
              icon: Icons.settings_outlined,
              label: 'Configurações',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Card — Saldo em estoque + botão verde
        _StockCard(
          totalText: _fmtCurrency(saldoEstoque),
          onConsultar: onConsultarEstoque,
        ),
      ],
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String title;
  final String value;
  const _BigStatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color onColor;
  final IconData icon;
  const _TagCard({
    required this.title,
    required this.value,
    required this.color,
    required this.onColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: onColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: onColor)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: onColor, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _MenuPill({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final String totalText;
  final VoidCallback onConsultar;
  const _StockCard({required this.totalText, required this.onConsultar});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saldo em estoque'),
            const SizedBox(height: 4),
            Text(totalText, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade400,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onConsultar,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_rounded),
                    SizedBox(width: 8),
                    Text('Consultar estoque'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
