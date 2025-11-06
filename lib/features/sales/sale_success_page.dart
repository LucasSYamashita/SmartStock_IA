// lib/features/sales/sale_success_page.dart
import 'package:flutter/material.dart';

class SaleSuccessPage extends StatelessWidget {
  final String vendaId;
  final double total;
  final String method; // PIX, Crédito, etc.
  final VoidCallback onShare; // ação para compartilhar o recibo

  const SaleSuccessPage({
    super.key,
    required this.vendaId,
    required this.total,
    required this.method,
    required this.onShare,
  });

  String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check, size: 96, color: Colors.teal),
              const SizedBox(height: 16),
              Text('Venda Concluída',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(_fmt(total),
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text('Pagamento: $method',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('ID: $vendaId',
                  style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Recibo'),
                  onPressed: onShare,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Iniciar outra venda'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
