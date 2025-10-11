// lib/features/moviments/movement_history_page.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tenant/tenant_provider.dart';

class MovementHistoryPage extends ConsumerWidget {
  const MovementHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(
        body: Center(child: Text('Selecione uma loja para ver o histórico.')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('movimentos')
        .orderBy('createdAt', descending: true)
        .limit(200);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de movimentações'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download),
            onPressed: () => _exportCsv(context, q),
          ),
          IconButton(
            tooltip: 'Compartilhar (WhatsApp/E-mail)',
            icon: const Icon(Icons.share),
            onPressed: () => _shareReport(context, q),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Sem movimentações ainda.'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final tipo = (d['tipo'] ?? '').toString(); // entrada/saida/ajuste
              final qtd = (d['quantidade'] ?? 0) as int;
              final prod = (d['produtoId'] ?? '').toString();
              final motivo = (d['motivo'] ?? '').toString();
              final createdAt = (d['createdAt']);
              final dt = createdAt is Timestamp
                  ? createdAt.toDate()
                  : DateTime.tryParse('$createdAt');

              final color = switch (tipo) {
                'entrada' => Colors.green,
                'saida' => Colors.red,
                _ => Colors.amber,
              };

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(.15),
                  child: Icon(
                    tipo == 'entrada'
                        ? Icons.call_received
                        : (tipo == 'saida'
                            ? Icons.call_made
                            : Icons.tune_outlined),
                    color: color,
                  ),
                ),
                title: Text(
                  '${tipo.toUpperCase()} · Qtd $qtd',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text([
                  if (prod.isNotEmpty) 'Produto: $prod',
                  if (motivo.isNotEmpty) 'Motivo: $motivo',
                  if (dt != null) 'Em: ${_fmt(dt)}',
                ].join(' • ')),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _exportCsv(
    BuildContext context,
    Query<Map<String, dynamic>> q,
  ) async {
    try {
      final snap = await q.get();
      final rows = <List<String>>[
        [
          'tipo',
          'quantidade',
          'produtoId',
          'usuarioId',
          'motivo',
          'origem',
          'createdAt'
        ],
      ];
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        final dt = ts is Timestamp ? ts.toDate().toIso8601String() : '$ts';
        rows.add([
          '${m['tipo'] ?? ''}',
          '${m['quantidade'] ?? ''}',
          '${m['produtoId'] ?? ''}',
          '${m['usuarioId'] ?? ''}',
          '${m['motivo'] ?? ''}',
          '${m['origem'] ?? ''}',
          dt,
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);

      // CORREÇÃO: usar dataFromString para poder especificar encoding
      final uri = Uri.dataFromString(
        csv,
        mimeType: 'text/csv',
        encoding: utf8,
      );

      await launchUrl(uri);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV gerado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao exportar: $e')),
        );
      }
    }
  }

  Future<void> _shareReport(
    BuildContext context,
    Query<Map<String, dynamic>> q,
  ) async {
    try {
      final snap = await q.limit(50).get();
      final lines = <String>['*Resumo de movimentações (últimas 50)*'];
      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString();
        final qtd = (m['quantidade'] ?? 0).toString();
        final prod = (m['produtoId'] ?? '').toString();
        final ts = m['createdAt'];
        final dt = ts is Timestamp ? _fmt(ts.toDate()) : '$ts';
        lines.add('• ${tipo.toUpperCase()} · $qtd · $prod · $dt');
      }
      final text = lines.join('\n');

      // WhatsApp (desktop abre web; mobile abre app)
      final wa = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
      await launchUrl(wa, mode: LaunchMode.externalApplication);

      // Opcional: E-mail
      // final email = Uri.parse(
      //   'mailto:?subject=Relatório SmartStock&body=${Uri.encodeComponent(text)}',
      // );
      // await launchUrl(email, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao compartilhar: $e')),
        );
      }
    }
  }
}

/// Conversor simples para CSV
class ListToCsvConverter {
  const ListToCsvConverter();

  String convert(List<List<String>> rows) {
    String esc(String v) {
      final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
      final s = v.replaceAll('"', '""');
      return needsQuote ? '"$s"' : s;
    }

    return rows.map((r) => r.map(esc).join(',')).join('\n');
  }
}
