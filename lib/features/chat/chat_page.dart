import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import '../tenant/role_providers.dart'
    show isStaffProvider; // <- usa o ProviderFamily correto
import 'chat_controller.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messages = ref.watch(chatControllerProvider);
    final tenantId = ref.watch(tenantIdProvider);

    // Se houver tenant selecionado, checa se o usuário é staff/admin
    final canWrite =
        tenantId != null ? ref.watch(isStaffProvider(tenantId)) : false;

    final userBubbleColor = isDark
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.primary.withOpacity(.12);
    final botBubbleColor = isDark
        ? theme.colorScheme.surfaceVariant
        : theme.colorScheme.surfaceVariant.withOpacity(.7);
    final userTextColor = isDark
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onPrimary;
    final botTextColor = theme.colorScheme.onSurface;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final m = messages[i];
              final isUser = m.role == 'user';
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 700),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser ? userBubbleColor : botBubbleColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    m.content,
                    style: TextStyle(
                      color: isUser ? userTextColor : botTextColor,
                      height: 1.25,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Escreva sua mensagem…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(canWrite),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _send(canWrite),
                  child: const Text('Enviar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _send(bool canWrite) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    // Se o usuário puder escrever (staff/admin), o controller tenta usar o /act quando fizer sentido
    ref.read(chatControllerProvider.notifier).send(
          text,
          tryActWhenPossible: canWrite,
        );
  }
}
