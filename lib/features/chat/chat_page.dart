import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartstock_flutter_only/features/chat/chat_controller.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // quando a lista de mensagens mudar, rola pro fim
    ref.listen<List<ChatMessage>>(chatControllerProvider, (_, __) {
      // dá um micro atraso para o ListView renderizar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });

    final messages = ref.watch(chatControllerProvider);
    final needsConfirm = messages.isNotEmpty &&
        messages.last.role == 'assistant' &&
        messages.last.text.toLowerCase().contains('confirma') &&
        (messages.last.text.toLowerCase().contains('confirmar') ||
            messages.last.text.toLowerCase().contains('cancelar'));

    return Scaffold(
      appBar: AppBar(title: const Text('SmartStock • Chatbot')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                final isMe = m.role == 'user';
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 560),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isMe ? 14 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(m.text),
                  ),
                );
              },
            ),
          ),

          // ações rápidas quando o bot pede confirmação
          if (needsConfirm)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _quick('confirmar'),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _quick('cancelar'),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  ),
                ],
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ex.: "entrada de 5 do Parafuso 10mm"',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
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

  void _quick(String text) {
    ref.read(chatControllerProvider.notifier).send(text);
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(t);
    _ctrl.clear();

    // foca de volta para digitar em sequência
    FocusScope.of(context).requestFocus(FocusNode());
    Future.delayed(const Duration(milliseconds: 50), () {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }
}
