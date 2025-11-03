// lib/features/chat/local_intent.dart
class ParsedEntrada {
  final String nome;
  final int? quantidade;
  final double? preco;
  ParsedEntrada({required this.nome, this.quantidade, this.preco});
}

double? _parsePreco(String raw) {
  if (raw.isEmpty) return null;
  final s = raw
      .toLowerCase()
      .replaceAll('reais', '')
      .replaceAll('real', '')
      .replaceAll('r\$', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  return double.tryParse(s);
}

int? _parseInt(String raw) {
  final m = RegExp(r'\d+').firstMatch(raw)?.group(0);
  return m == null ? null : int.tryParse(m);
}

ParsedEntrada? parseEntrada(String text) {
  final t = text.trim().toLowerCase();
  if (!t.startsWith('entrada ')) return null;

  final rFull = RegExp(r'^entrada\s+(.+?)\s+(\d+)\s+a\s+([\d.,]+)(?:\s*\w+)?$');
  final m1 = rFull.firstMatch(t);
  if (m1 != null) {
    return ParsedEntrada(
      nome: m1.group(1)!.trim(),
      quantidade: _parseInt(m1.group(2)!),
      preco: _parsePreco(m1.group(3)!),
    );
  }

  final rQty = RegExp(r'^entrada\s+(.+?)\s+(\d+)$');
  final m2 = rQty.firstMatch(t);
  if (m2 != null) {
    return ParsedEntrada(
      nome: m2.group(1)!.trim(),
      quantidade: _parseInt(m2.group(2)!),
      preco: null,
    );
  }

  final rName = RegExp(r'^entrada\s+(.+)$');
  final m3 = rName.firstMatch(t);
  if (m3 != null) {
    return ParsedEntrada(nome: m3.group(1)!.trim());
  }

  return null;
}
