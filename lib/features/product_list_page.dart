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
  final _listCtrl = ScrollController();
  final _focus = FocusNode();
  bool _sending = false;

  bool get _canSend {
    final t = _ctrl.text.trim();
    return t.isNotEmpty && !_sending;
  }

  @override
  void initState() {
    super.initState();
    // Sempre rola ao final quando chegarem mensagens novas
    ref.listen<List<ChatMessage>>(chatControllerProvider, (prev, next) {
      _jumpToEndSoon();
    });
    // Atualiza o estado do botão conforme digita
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _listCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _jumpToEndSoon() {
    // espera a lista renderizar antes de rolar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      _listCtrl.animateTo(
        _listCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatControllerProvider.notifier).send(t);
      _ctrl.clear();
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _sending = false);
      _jumpToEndSoon();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatControllerProvider);

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _EmptyState(onTapExamples: (sample) {
                  _ctrl.text = sample;
                  _focus.requestFocus();
                })
              : ListView.builder(
                  controller: _listCtrl,
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
                            bottomLeft: Radius.circular(isMe ? 14 : 2),
                            bottomRight: Radius.circular(isMe ? 2 : 14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _focus,
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4, // permite digitar mensagens maiores
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Ex.: "entrada de 5 do Shampoo Clear"',
                      prefixIcon: const Icon(Icons.chat_bubble_outline),
                    ),
                    // Enter envia; Shift/Ctrl+Enter quebra linha
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  icon: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending ? 'Enviando...' : 'Enviar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final void Function(String sample) onTapExamples;
  const _EmptyState({required this.onTapExamples});

  @override
  Widget build(BuildContext context) {
    final examples = const [
      'entrada de 10 do Shampoo Clear',
      'vendi 2 do Sabonete Dove',
      'quanto tem do Condicionador Seda',
      'confirmar',
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.support_agent,
                  size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Converse com o SmartStock',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Registre entradas/saídas e consulte o saldo de produtos. '
                'Você pode confirmar operações respondendo "confirmar".',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: examples
                    .map(
                      (e) => ActionChip(
                        label: Text(e),
                        onPressed: () => onTapExamples(e),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
