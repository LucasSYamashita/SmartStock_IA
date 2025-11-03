import 'package:flutter/material.dart';
import 'chat_controller.dart';
import 'chat_message.dart';

class ChatPage extends StatefulWidget {
  final String tenantId;
  final String role; // 'admin' | 'staff' | 'viewer'
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

class _ChatPageState extends State<ChatPage> {
  late final ChatController controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    controller = ChatController(
      tenantId: widget.tenantId,
      role: widget.role,
      userId: widget.userId,
    );
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _onSend() {
    final text = _input.text;
    _input.clear();
    controller.send(text, onChange: () {
      setState(() {});
      _scrollToEnd();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = controller.messages;

    Color bubbleBg(bool isUser) => isUser
        ? const Color(0xFF1B5E20).withOpacity(0.90)
        : const Color(0xFF43A047).withOpacity(0.22);

    // >>> Apenas as letras em branco (para user e assistant)
    Color bubbleFg(bool isUser) => Colors.white;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat – SmartStock')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final m = items[i];
                final isUser = m.role == 'user';
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
                        color: bubbleBg(isUser),
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
                      child: Text(
                        m.text,
                        style: TextStyle(
                          color: bubbleFg(isUser), // letras brancas
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
          if (controller.hasPendingMove)
            Material(
              elevation: 2,
              color: const Color(0xFFE8F5E9),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Confirmar movimentação proposta?',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFF1B5E20)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => controller.cancelPending(onChange: () {
                        setState(() {});
                        _scrollToEnd();
                      }),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => controller.confirmPending(onChange: () {
                        setState(() {});
                        _scrollToEnd();
                      }),
                      child: const Text('Confirmar'),
                    ),
                  ],
                ),
              ),
            ),
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
                      onSubmitted: (_) => _onSend(),
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText:
                            'Digite: "entrada 5 do Produto X a 10,00", "saída 2 do Produto Y"... (ou "confirmar"/"cancelar")',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _onSend,
                    icon: const Icon(Icons.send, size: 18),
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
