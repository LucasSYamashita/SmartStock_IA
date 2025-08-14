sealed class Intent {
  const Intent();
}

class MoveIntent extends Intent {
  final String tipo; // 'entrada' | 'saida'
  final int quantidade;
  final String produtoNome;
  final String? motivo;
  final String originalText;
  const MoveIntent({
    required this.tipo,
    required this.quantidade,
    required this.produtoNome,
    this.motivo,
    required this.originalText,
  });
}

class QueryIntent extends Intent {
  final String produtoNome;
  const QueryIntent({required this.produtoNome});
}

Intent parseCommand(String text) {
  final original = text.trim();
  final lower = original.toLowerCase();

  // entrada
  final entrada = RegExp(
    r'(entrada|adicionar|recebi|compra) de (\d+) (un\.|unidades|itens)? (do|de) (.+)',
    caseSensitive: false,
  );
  final m1 = entrada.firstMatch(original);
  if (m1 != null) {
    final qtd = int.tryParse(m1.group(2) ?? '0') ?? 0;
    final nome = (m1.group(5) ?? '').trim();
    return MoveIntent(
      tipo: 'entrada',
      quantidade: qtd,
      produtoNome: nome,
      motivo: 'compra',
      originalText: original,
    );
  }

  // saída
  final saida = RegExp(
    r'(saida|vendi|venda|baixa|retirei) (de )?(\d+) (un\.|unidades|itens)? (do|de) (.+)',
    caseSensitive: false,
  );
  final m2 = saida.firstMatch(original);
  if (m2 != null) {
    final qtd = int.tryParse(m2.group(3) ?? '0') ?? 0;
    final nome = (m2.group(6) ?? '').trim();
    return MoveIntent(
      tipo: 'saida',
      quantidade: qtd,
      produtoNome: nome,
      motivo: 'venda',
      originalText: original,
    );
  }

  // consulta
  final consulta = RegExp(
    r'(quanto|qtd|quantidade).*(tem|estoque).*(do|de) (.+)',
    caseSensitive: false,
  );
  final m3 = consulta.firstMatch(original);
  if (m3 != null) {
    final nome = (m3.group(4) ?? '').trim();
    return QueryIntent(produtoNome: nome);
  }

  if (lower.startsWith('quanto tem do ')) {
    final nome = original.substring('quanto tem do '.length).trim();
    return QueryIntent(produtoNome: nome);
  }

  return QueryIntent(produtoNome: original);
}
