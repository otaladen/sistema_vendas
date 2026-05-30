import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Textos de ajuda e faixa contextual da tela Entregas.
class EntregasGuia {
  EntregasGuia._();

  static const _prefsDicasVisiveis = 'entregas_dicas_visiveis';

  static Future<bool> dicasVisiveis() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsDicasVisiveis) ?? true;
  }

  static Future<void> setDicasVisiveis(bool visivel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDicasVisiveis, visivel);
  }

  static void mostrarDialogoCompleto(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.local_shipping_outlined),
            SizedBox(width: 10),
            Expanded(child: Text('Como usar Entregas')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _secao(
                ctx,
                titulo: 'Por onde comecar',
                icone: Icons.play_arrow_outlined,
                itens: const [
                  'Escolha o dia na faixa "Dia da entrega" (topo da tela).',
                  'Use Atr. ou Pend. hoje para focar em atrasadas ou no dia.',
                  'A aba Lista e a mais simples para ver e editar pedidos.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Lista',
                icone: Icons.view_list_outlined,
                itens: const [
                  'Todos os pedidos do dia, agrupados por bairro ou motorista.',
                  'Toque no pedido para ver detalhes, status, motorista e navegacao.',
                  'Opcional: "Agrupar mesmo carro" junta pedidos na mesma viagem.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Patio (carga do caminhao)',
                icone: Icons.inventory_2_outlined,
                itens: const [
                  '1. Selecione o motorista / caminhao.',
                  '2. Selecione a viagem (pedido avulso ou grupo "mesmo carro").',
                  '3. Marque os itens em Carga consolidada (patio).',
                  '4. Checklist: Separado → Carregado → Saiu.',
                  '5. Quando tudo estiver ok, toque em "Saiu p/ entrega".',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Kanban',
                icone: Icons.view_kanban_outlined,
                itens: const [
                  'Arraste o card do pedido entre colunas para mudar o status.',
                  'Fluxo tipico: Pendente → Roteirizada → Saiu → Entregue.',
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  static Widget _secao(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required List<String> itens,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in itens)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(item, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String dicaCurtaAba(int indice) {
    switch (indice) {
      case 0:
        return 'Patio: motorista → viagem → marcar carga → Separado / Carregado / Saiu → "Saiu p/ entrega".';
      case 1:
        return 'Lista: visao geral dos pedidos do dia. Toque no card para status, motorista e acoes.';
      case 2:
        return 'Kanban: arraste o pedido entre colunas para atualizar o status rapidamente.';
      default:
        return '';
    }
  }

  static String tituloAba(int indice) {
    switch (indice) {
      case 0:
        return 'Patio';
      case 1:
        return 'Lista';
      case 2:
        return 'Kanban';
      default:
        return '';
    }
  }
}

/// Faixa fina abaixo dos filtros, muda conforme a aba ativa.
class EntregasFaixaDicaAba extends StatelessWidget {
  const EntregasFaixaDicaAba({
    super.key,
    required this.indiceAba,
    required this.onAbrirGuia,
    required this.onOcultar,
  });

  final int indiceAba;
  final VoidCallback onAbrirGuia;
  final VoidCallback onOcultar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      EntregasGuia.tituloAba(indiceAba),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      EntregasGuia.dicaCurtaAba(indiceAba),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onAbrirGuia,
                      child: const Text('Ver guia completo'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ocultar dicas',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onOcultar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
