import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// usa o backend que te passei (local por padrão)
import 'chat_backend.dart';

class ChatPage extends StatefulWidget {
  final String tenantId;
  final String role; // 'admin' | 'staff' | 'viewer' (mantido p/ compat.)
  final String userId;

  const ChatPage({
    super.key,
    required this.tenantId,
    required this.role,
    required this.userId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _Msg {
  final bool mine; // true = usuário; false = assistente
  final String text;
  _Msg(this.mine, this.text);
}

class _ChatPageState extends State<ChatPage> {
  late final ChatBackend _backend;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // backend local (cai pro local mesmo que vc habilite cloud e falhe)
    _backend = makeChatBackend(FirebaseFirestore.instance);

    _msgs.add(_Msg(
        false,
        'Oi! Posso ajudar com **consultas**: baixo estoque, buscar itens, etc.\n'
        'Para **entrada**, abra o produto e toque em “Registrar entrada”.\n'
        'Para **saída/venda**, use o botão **Vender** na tela Início.'));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty || _sending) return;

    setState(() {
      _msgs.add(_Msg(true, raw));
      _input.clear();
      _sending = true;
    });
    _scrollToEnd();

    // Respostas diretas para confirmar/cancelar (não há pendência aqui)
    final t = raw.toLowerCase();
    if (t == 'confirmar' || t == 'cancelar') {
      setState(() {
        _msgs.add(_Msg(
            false,
            'Não há movimentação pendente. Para lançar **entrada**, use o produto; '
            'para **saída/venda**, use **Vender** na tela Início.'));
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    final res = await _backend.respond(
      tenantId: widget.tenantId,
      userId: widget.userId,
      text: raw,
    );

    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(false, res.message));
      _sending = false;
    });
    _scrollToEnd();
  }

  // Visual igual ao seu: bolhas verdes com letras brancas
  Color _bubbleBg(bool isUser) => isUser
      ? const Color(0xFF1B5E20).withOpacity(0.90)
      : const Color(0xFF43A047).withOpacity(0.22);
  Color _bubbleFg(bool isUser) => Colors.white;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat – SmartStock')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              itemCount: _msgs.length,
              itemBuilder: (context, i) {
                final m = _msgs[i];
                final isUser = m.mine;
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _bubbleBg(isUser),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 6),
                          bottomRight: Radius.circular(isUser ? 6 : 16),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: SelectableText(
                        m.text,
                        style: TextStyle(
                          color: _bubbleFg(isUser),
                          height: 1.25,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Rodapé de entrada
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                border: const Border(
                  top: BorderSide(color: Color(0x22000000)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText:
                            'Ex.: "baixo estoque", "paracetamol", "total vendido hoje"...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, size: 18),
                    label: const Text('Enviar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
