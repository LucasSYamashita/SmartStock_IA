/// NLU simples (pt-BR)
/// Intenções suportadas:
/// - ENTRADA: "entrada 10 coca", "entrada de 10 coca a 5,50",
///            "entrada coca 10", "entrada coca a 10", "adicionar 3 do produto x", "repor 2 maçã  @ 4"
/// - SAÍDA:   "saida 2 coca", "saída de 2 coca", "vendi coca 2", "baixar 1 do produto y"
/// - QUERY:   "quanto tem coca", "qtd de coca", "estoque coca"
///
/// Observação: quando a quantidade não for informada, assume 1.

abstract class Intent {
  final String originalText;
  Intent(this.originalText);
}

class MoveIntent extends Intent {
  final String tipo; // 'entrada' | 'saida'
  final int quantidade;
  final String produtoNome;
  final String? motivo;
  final double? preco; // opcional (só faz sentido p/ entrada)

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
  QueryIntent({
    required String originalText,
    required this.produtoNome,
  }) : super(originalText);
}

/* ================== Helpers ================== */

String _normalize(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _cleanProduto(String s) =>
    s.trim().replaceAll(RegExp(r'^[\'"]+|[\'"]+$'), '');

/// aceita: "10", "10x", "10 un", "10 unid", "10 pcs", "10 peças"
int? _parseQtdToken(String raw) {
  final t = raw.trim().toLowerCase();
  final m = RegExp(
    r'^(\d+)\s*(?:x|u|un|unid(?:ade)?s?|pc|pcs|peç(?:a|as))?$',
  ).firstMatch(t);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return n;
}

/// aceita: "10", "10,00", "10.00", com ou sem "R$"
double? _parsePrecoToken(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase().replaceAll('r\$', '').trim();
  final norm = t.replaceAll('.', '').replaceAll(',', '.'); // 1.234,56 -> 1234.56
  final n = double.tryParse(norm);
  return n;
}

/* ============== ENTRADA / SAÍDA ============== */

final _verbsEntrada =
    r'(?:entrada|adicionar|somar|soma(?:r)?|criar|cadastrar|repor|comprar|chegou|estoque\+)';

final _verbsSaida =
    r'(?:vendi|venda|sa[ií]da|retirei|retirar|baixar?|baixei|consumi|usei|uso|estoque-)';

final _prepDe = r'(?:do|da|de|dos|das)';

final _priceClause =
    r'(?:\s*(?:a|por|@)\s*(?:r\$\s*)?(\d+[.,]?\d*))?'; // grupo 1 = preço

/// Tenta reconhecer um comando de ENTRADA
MoveIntent? _tryEntrada(String input) {
  final t = _normalize(input);

  // Padrão 1: verbo + (de) + QTD + (de) + PROD + (a|por|@ PRECO)?
  var re = RegExp('^$_verbsEntrada\\s+(?:de\\s+)?(\\d+\\s*\\w*)\\s+(?:$_prepDe\\s+)?(.+?)$_priceClause\$');
  var m = re.firstMatch(t);
  if (m != null) {
    final qtd = _parseQtdToken(m.group(1)!);
    final nome = _cleanProduto(m.group(2)!);
    final preco = _parsePrecoToken(m.group(3));
    if (qtd != null && qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: input,
        tipo: 'entrada',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  // Padrão 2: verbo + PROD + QTD? + (a|por|@ PRECO)?
  re = RegExp('^$_verbsEntrada\\s+(?:$_prepDe\\s+)?(.+?)(?:\\s+(\\d+\\s*\\w*))?$_priceClause\$');
  m = re.firstMatch(t);
  if (m != null) {
    final nome = _cleanProduto(m.group(1)!);
    final qtd = (m.group(2) != null) ? _parseQtdToken(m.group(2)!) : 1;
    final preco = _parsePrecoToken(m.group(3));
    if ((qtd ?? 1) > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: input,
        tipo: 'entrada',
        quantidade: qtd ?? 1,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: preco,
      );
    }
  }

  return null;
}

/// Tenta reconhecer um comando de SAÍDA
MoveIntent? _trySaida(String input) {
  final t = _normalize(input);

  // Padrão 1: verbo + QTD + (de) + PROD + (a|por|@ PRECO)?  (preço é ignorado no estoque)
  var re = RegExp('^$_verbsSaida\\s+(\\d+\\s*\\w*)\\s+(?:$_prepDe\\s+)?(.+?)$_priceClause\$');
  var m = re.firstMatch(t);
  if (m != null) {
    final qtd = _parseQtdToken(m.group(1)!);
    final nome = _cleanProduto(m.group(2)!);
    if (qtd != null && qtd > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: input,
        tipo: 'saida',
        quantidade: qtd,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: null,
      );
    }
  }

  // Padrão 2: verbo + PROD + QTD?
  re = RegExp('^$_verbsSaida\\s+(?:$_prepDe\\s+)?(.+?)(?:\\s+(\\d+\\s*\\w*))?$_priceClause\$');
  m = re.firstMatch(t);
  if (m != null) {
    final nome = _cleanProduto(m.group(1)!);
    final qtd = (m.group(2) != null) ? _parseQtdToken(m.group(2)!) : 1;
    if ((qtd ?? 1) > 0 && nome.isNotEmpty) {
      return MoveIntent(
        originalText: input,
        tipo: 'saida',
        quantidade: qtd ?? 1,
        produtoNome: nome,
        motivo: 'chatbot',
        preco: null,
      );
    }
  }

  return null;
}

/* ================== QUERY ================== */

QueryIntent? _tryQuery(String input) {
  final t = _normalize(input);
  final re = RegExp(
    r'^(?:quanto\s+tem|qtd|quantidade|estoque|saldo|tem)(?:\s+' + _prepDe + r')?\s+(.+)$',
  );
  final m = re.firstMatch(t);
  if (m != null) {
    final nome = _cleanProduto(m.group(1)!);
    if (nome.isNotEmpty) {
      return QueryIntent(originalText: input, produtoNome: nome);
    }
  }
  return null;
}

/* ================== DISPATCH ================== */

Intent? parseCommand(String text) {
  return _tryEntrada(text) ?? _trySaida(text) ?? _tryQuery(text);
}
