import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';
import 'chat_controller.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(chatControllerProvider);
    final tenantId = ref.watch(tenantIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock • Chat'),
        actions: [
          if (tenantId == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('Selecione uma loja',
                    style: TextStyle(color: Colors.yellow)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: history.length,
              itemBuilder: (_, i) {
                final m = history[i];
                final isUser = m.role == 'user';
                final align =
                    isUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg = isUser
                    ? Theme.of(context).colorScheme.primary.withOpacity(.12)
                    : Theme.of(context).colorScheme.surfaceVariant;

                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(.4),
                      ),
                    ),
                    child: Text(
                      m.content,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Digite sua mensagem…',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Ações',
                    onSelected: (v) {
                      switch (v) {
                        case 'propor':
                          _propose();
                          break;
                        case 'confirmar':
                          _confirm();
                          break;
                        case 'cancelar':
                          _cancel();
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'propor', child: Text('Propor (dry-run)')),
                      PopupMenuItem(
                          value: 'confirmar',
                          child: Text('Confirmar pendente')),
                      PopupMenuItem(
                          value: 'cancelar', child: Text('Cancelar pendente')),
                    ],
                    child: ElevatedButton.icon(
                      onPressed: _propose,
                      icon: const Icon(Icons.playlist_add_check),
                      label: const Text('Propor'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _send,
                    child: const Text('Enviar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final txt = _input.text.trim();
    if (txt.isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(txt);
  }

  void _propose() {
    final txt = _input.text.trim();
    if (txt.isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).proposeAction(txt);
  }

  void _confirm() {
    ref
        .read(chatControllerProvider.notifier)
        .confirmPending(createIfMissing: true);
  }

  void _cancel() {
    ref.read(chatControllerProvider.notifier).cancelPending();
  }
}
