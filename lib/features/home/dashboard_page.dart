import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../inbound/manual_entry_page.dart';
import '../sales/manual_sale_flow.dart' show ManualSaleCatalogPage;
import '../moviments/movement_history_page.dart';
import '../auth/profile_page.dart';
import '../tenant/tenant_provider.dart';

class DashboardPage extends ConsumerWidget {
  final VoidCallback onConsultarEstoque;
  const DashboardPage({super.key, required this.onConsultarEstoque});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Nenhuma loja selecionada. Crie/entre em uma loja no Perfil.')));
    }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    final vendasMesStream = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('movimentos')
        .where('tipo', isEqualTo: 'saida')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstOfMonth))
        .snapshots();

    final produtosStream = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: produtosStream,
      builder: (context, prodSnap) {
        num saldoEstoque = 0;
        int totalProdutos = 0;
        int semEstoque = 0;
        int baixo = 0;

        if (prodSnap.hasData) {
          totalProdutos = prodSnap.data!.docs.length;
          for (final d in prodSnap.data!.docs) {
            final m = d.data();
            final q = (m['quantidade'] ?? 0) as num;
            final v = (m['preco'] ?? 0) as num;
            final min = (m['estoqueMinimo'] ?? 0) as num;
            saldoEstoque += q * v;
            if (q <= 0)
              semEstoque++;
            else if (q <= min) baixo++;
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: vendasMesStream,
          builder: (context, venSnap) {
            num vendasDoMes = 0;
            if (venSnap.hasData) {
              for (final d in venSnap.data!.docs) {
                final any = d.data()['valorTotal'] ?? 0;
                final v = any is num
                    ? any.toDouble()
                    : double.tryParse('$any') ?? 0.0;
                vendasDoMes += v;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _BigStatCard(
                            title: 'Vendas do mês',
                            value: _fmtCurrency(vendasDoMes))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _BigStatCard(
                            title: 'Produtos', value: '$totalProdutos')),
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
                            onColor:
                                Theme.of(context).colorScheme.onErrorContainer,
                            icon: Icons.block)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _TagCard(
                            title: 'Estoque baixo',
                            value: '$baixo',
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            onColor: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            icon: Icons.warning_amber)),
                  ],
                ),
                const SizedBox(height: 16),
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
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ManualSaleCatalogPage()))),
                    _MenuPill(
                      icon: Icons.receipt_long,
                      label: 'Relatórios',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const MovementHistoryPage(), // usa o novo arquivo
                        ),
                      ),
                    ),
                    _MenuPill(
                        icon: Icons.inventory_rounded,
                        label: 'Entrada manual',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ManualEntryPage()))),
                    _MenuPill(
                        icon: Icons.settings_outlined,
                        label: 'Configurações',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ProfilePage()))),
                  ],
                ),
                const SizedBox(height: 16),
                _StockCard(
                    totalText: _fmtCurrency(saldoEstoque),
                    onConsultar: onConsultarEstoque),
              ],
            );
          },
        );
      },
    );
  }

  static String _fmtCurrency(num v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ])));
  }
}

class _TagCard extends StatelessWidget {
  final String title, value;
  final Color color, onColor;
  final IconData icon;
  const _TagCard(
      {required this.title,
      required this.value,
      required this.color,
      required this.onColor,
      required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: onColor),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: TextStyle(color: onColor)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                color: onColor, fontWeight: FontWeight.w700)),
                  ]))
            ])));
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
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ]))));
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                              borderRadius: BorderRadius.circular(28)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: onConsultar,
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_rounded),
                            SizedBox(width: 8),
                            Text('Consultar estoque')
                          ])))
            ])));
  }
}
