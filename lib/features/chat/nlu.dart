/// NLU simples (pt-BR)
/// Intenções:
/// - entrada/adicionar/somar/criar/cadastrar 5 (do) Produto X [a 10,00]
/// - vendi/saida/retirei/baixar 2 (do) Produto Y [a 5]
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
  final double? preco; // opcional

  MoveIntent({
    required String originalText,
    required this.tipo,
    required this.quantidade,
    required this.produtoNome,
    this.motivo,
    this.preco,
  }) : super(originalText);
}

class QueryIntent extends Intent {
  final String produtoNome;
  QueryIntent({required String originalText, required this.produtoNome})
      : super(originalText);
}

double? _parsePreco(String? raw) {
  if (raw == null) return null;
  final norm = raw.trim().replaceAll(',', '.');
  final n = double.tryParse(norm);
  return n;
}

Intent? _tryMove(String text) {
  final t = text.trim().toLowerCase();

  // Padrão A: "entrada 10 cocacola a 10,00" | "adicionar 3 do produto x"
  final reA = RegExp(
    r'^(?:\s*)(?:entrada|adicionar|somar|soma(?:r)?|criar|cadastrar)\s+(?:de\s+)?(\d+)\s+(?:(?:do|da|de|dos|das)\s+)?(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$',
    caseSensitive: false,
  );
  final mA = reA.firstMatch(t);
  if (mA != null) {
    final qtd = int.tryParse(mA.group(1)!) ?? 0;
    final nome = mA.group(2)!.trim();
    final preco = _parsePreco(mA.group(3));
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'entrada',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  // Padrão B: "entrada cocacola 10 a 10,00"
  final reB = RegExp(
    r'^(?:\s*)(?:entrada|adicionar|somar|soma(?:r)?|criar|cadastrar)\s+(?:(?:do|da|de|dos|das)\s+)?(.+?)\s+(\d+)(?:\s+a\s+(\d+[.,]?\d*))?$',
    caseSensitive: false,
  );
  final mB = reB.firstMatch(t);
  if (mB != null) {
    final nome = mB.group(1)!.trim();
    final qtd = int.tryParse(mB.group(2)!) ?? 0;
    final preco = _parsePreco(mB.group(3));
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'entrada',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  // Saída (mesmas variações)
  final reOutA = RegExp(
    r'^(?:\s*)(?:vendi|venda|sa[ií]da|retirei|retirar|baixar?)\s+(\d+)\s+(?:(?:do|da|de|dos|das)\s+)?(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$',
    caseSensitive: false,
  );
  final mOutA = reOutA.firstMatch(t);
  if (mOutA != null) {
    final qtd = int.tryParse(mOutA.group(1)!) ?? 0;
    final nome = mOutA.group(2)!.trim();
    final preco = _parsePreco(mOutA.group(3));
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'saida',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  final reOutB = RegExp(
    r'^(?:\s*)(?:vendi|venda|sa[ií]da|retirei|retirar|baixar?)\s+(?:(?:do|da|de|dos|das)\s+)?(.+?)\s+(\d+)(?:\s+a\s+(\d+[.,]?\d*))?$',
    caseSensitive: false,
  );
  final mOutB = reOutB.firstMatch(t);
  if (mOutB != null) {
    final nome = mOutB.group(1)!.trim();
    final qtd = int.tryParse(mOutB.group(2)!) ?? 0;
    final preco = _parsePreco(mOutB.group(3));
    if (qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: text,
        tipo: 'saida',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  return null;
}

Intent? _tryQuery(String text) {
  final t = text.trim().toLowerCase();
  final re = RegExp(
    r'^(?:\s*)(?:quanto\s+tem|qtd|quantidade|estoque)(?:\s+(?:do|da|de|dos|das))?\s+(.+)$',
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
