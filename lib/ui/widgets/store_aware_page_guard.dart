import 'package:flutter/material.dart';

import '../../data/objectbox_lifecycle_hub.dart';

/// Evita montar telas locais (PDV, caixa, etc.) com o ObjectBox fechado
/// para backup — senao o `initState` estoura e o Flutter troca a aba por
/// "Algo deu errado nesta tela" ate fechar a aba.
class StoreAwarePageGuard extends StatefulWidget {
  const StoreAwarePageGuard({super.key, required this.child});

  final Widget child;

  @override
  State<StoreAwarePageGuard> createState() => _StoreAwarePageGuardState();
}

class _StoreAwarePageGuardState extends State<StoreAwarePageGuard>
    implements ObjectBoxStoreLifecycleListener {
  late bool _suspenso;
  late int _geracao;

  @override
  void initState() {
    super.initState();
    _suspenso = ObjectBoxLifecycleHub.acessoLocalSuspenso;
    _geracao = ObjectBoxLifecycleHub.geracaoStore;
    ObjectBoxLifecycleHub.registrar(this);
  }

  @override
  void dispose() {
    ObjectBoxLifecycleHub.remover(this);
    super.dispose();
  }

  @override
  Future<void> onObjectBoxClosingForCopy() async {
    if (!mounted) return;
    setState(() => _suspenso = true);
  }

  @override
  void onObjectBoxReopenedAfterCopy() {
    if (!mounted) return;
    setState(() {
      _suspenso = false;
      _geracao = ObjectBoxLifecycleHub.geracaoStore;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_suspenso) {
      return const StoreLocalIndisponivelPlaceholder();
    }
    return KeyedSubtree(
      key: ValueKey<int>(_geracao),
      child: widget.child,
    );
  }
}

/// Placeholder (backup em andamento) ou recado para reabrir a aba ja quebrada.
class StoreLocalIndisponivelPlaceholder extends StatelessWidget {
  const StoreLocalIndisponivelPlaceholder({
    super.key,
    this.pedirReabrirAba = false,
  });

  final bool pedirReabrirAba;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!pedirReabrirAba) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                ],
                Text(
                  pedirReabrirAba
                      ? 'O sistema estava em backup.\nFeche esta aba e abra Nova venda de novo.'
                      : 'Aguarde, o servidor esta salvando o backup…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
