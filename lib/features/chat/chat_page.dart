import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_controller.dart';
import 'chat_models.dart';

class ChatPage extends ConsumerStatefulWidget {
  final String tenantId;
  final String role;
  const ChatPage({super.key, required this.tenantId, required this.role});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _ctrl = TextEditingController();

  Future<void> _send() async {
    final text = _ctrl.text;
    _ctrl.clear();
    final args = ChatArgs(tenantId: widget.tenantId, role: widget.role);
    await ref.read(chatControllerProvider(args).notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final args = ChatArgs(tenantId: widget.tenantId, role: widget.role);
    final msgs = ref.watch(chatControllerProvider(args));

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final ChatMessage m = msgs[i];
              final isUser = m.from == 'user';
              final bg = m.from == 'system'
                  ? Colors.red.shade700
                  : (isUser ? Colors.green.shade800 : Colors.grey.shade800);
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Text(m.text, style: const TextStyle(color: Colors.white)),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    hintText: 'ex.: entrada coca-cola 10 a 5,50',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _send,
                child: const Text('Enviar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
