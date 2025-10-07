/// NLU simples (pt-BR) para 3 intenções:
/// - entrada/adicionar/somar 5 do Produto X
/// - vendi/saida/retirei/baixar 2 (do) Produto Y
/// - quanto tem / qtd / quantidade / estoque (do) Produto Z

abstract class Intent {
  final String originalText;
  Intent(this.originalText);
}

class MoveIntent extends Intent {
  final String tipo; // 'entrada' | 'saida'
  final int quantidade;
  final String produtoNome;
  final String? motivo;
  MoveIntent({
    required super.originalText,
    required this.tipo,
    required this.quantidade,
    required this.produtoNome,
    this.motivo,
  });
}

class QueryIntent extends Intent {
  final String produtoNome;
  QueryIntent({required super.originalText, required this.produtoNome});
}

Intent? _tryMove(String text) {
  final t = text.trim().toLowerCase();

  // ENTRADA: "entrada 5 do X", "entrada de 5 X", "adicionar 3 da Y", "somar 2 Z"
  final reIn = RegExp(
    r'^(?:\s*)(?:entrada|adicionar|somar|soma(?:r)?)\s+(?:de\s+)?(\d+)\s+(?:(?:do|da|de|dos|das)\s+)?(.+)$',
    caseSensitive: false,
  );
  final mIn = reIn.firstMatch(t);
  if (mIn != null) {
    final qtd = int.tryParse(mIn.group(1)!) ?? 0;
    final nome = mIn.group(2)!.trim();
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'entrada',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
      );
    }
  }

  // SAÍDA: "vendi 2 do X", "saida 1 X", "retirei 3 da Y", "baixar 4 Z"
  final reOut = RegExp(
    r'^(?:\s*)(?:vendi|venda|sa[ií]da|retirei|retirar|baixar?)\s+(\d+)\s+(?:(?:do|da|de|dos|das)\s+)?(.+)$',
    caseSensitive: false,
  );
  final mOut = reOut.firstMatch(t);
  if (mOut != null) {
    final qtd = int.tryParse(mOut.group(1)!) ?? 0;
    final nome = mOut.group(2)!.trim();
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'saida',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
      );
    }
  }

  return null;
}

Intent? _tryQuery(String text) {
  final t = text.trim().toLowerCase();

  // CONSULTA: "quanto tem do X", "qtd do Y", "quantidade Z", "estoque de W"
  final re = RegExp(
    r'^(?:\s*)(?:quanto\s+tem|qtd|quantidade|estoque(?:\s+(?:do|da|de|dos|das))?)\s+(?:(?:do|da|de|dos|das)\s+)?(.+)$',
    caseSensitive: false,
  );
  final m = re.firstMatch(t);
  if (m != null) {
    final nome = m.group(1)!.trim();
    if (nome.isNotEmpty) {
      return QueryIntent(originalText: text, produtoNome: nome);
    }
  }
  return null;
}

Intent? parseCommand(String text) => _tryMove(text) ?? _tryQuery(text);
