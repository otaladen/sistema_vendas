import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Textos de ajuda e faixa contextual da tela Entregas.
class EntregasGuia {
  EntregasGuia._();

  static const _prefsDicasVisiveis = 'entregas_dicas_visiveis';
  static const _prefsUltimaAba = 'entregas_ultima_aba';
  static const _prefsModoDiaKanban = 'entregas_modo_dia_kanban';
  static const _prefsVisaoSimples = 'entregas_visao_simples';

  /// Visao operacional enxuta (padrao). False = Patio/Dia avancado.
  static Future<bool> visaoSimplesAtiva() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsVisaoSimples) ?? true;
  }

  static Future<void> setVisaoSimplesAtiva(bool ativa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsVisaoSimples, ativa);
  }

  /// Preferencias de abertura (0=Patio, 1=Dia; kanban = visualizacao na aba Dia).
  static Future<({int aba, bool kanban})> preferenciasAbertura() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_prefsUltimaAba) ?? 1;
    final kanbanSalvo = prefs.getBool(_prefsModoDiaKanban) ?? false;
    if (raw >= 2) {
      return (aba: 1, kanban: raw == 2 || kanbanSalvo);
    }
    return (aba: raw.clamp(0, 1), kanban: kanbanSalvo);
  }

  static Future<void> salvarPreferenciasAbertura({
    required int aba,
    required bool kanban,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsUltimaAba, aba.clamp(0, 1));
    await prefs.setBool(_prefsModoDiaKanban, kanban);
  }

  /// Indice da ultima aba (legado). Preferir [preferenciasAbertura].
  static Future<int> ultimaAba() async {
    final p = await preferenciasAbertura();
    return p.aba;
  }

  static Future<void> salvarUltimaAba(int indice) async {
    final p = await preferenciasAbertura();
    await salvarPreferenciasAbertura(aba: indice, kanban: p.kanban);
  }

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
                  'Escolha o dia na faixa "Dia da entrega" (topo da tela). A tela abre em Hoje.',
                  'Use os chips de Status ou Atr. / Pend. hoje para focar rapidamente.',
                  'Na lista, use o botao principal de cada pedido (Roteirizar, Saiu, Entregue).',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Dia operacional',
                icone: Icons.calendar_view_week_outlined,
                itens: const [
                  'Use a faixa da semana para saltar entre dias com entregas.',
                  'Alterne Lista e Kanban na mesma aba (topo da area do dia).',
                  'Pedidos agrupados por motorista por padrao.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Lista',
                icone: Icons.view_list_outlined,
                itens: const [
                  'Todos os pedidos do dia, agrupados por motorista (ou bairro).',
                  'Toque no pedido para ver detalhes, status, motorista e navegacao.',
                  'Opcional: "Agrupar mesmo carro" junta pedidos na mesma viagem '
                  '(podem ser clientes diferentes). Depois defina a ordem na rota.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Patio (carga do caminhao)',
                icone: Icons.inventory_2_outlined,
                itens: const [
                  '1. Selecione o motorista / caminhao.',
                  '2. Selecione a viagem (pedido avulso ou grupo no mesmo carro).',
                  '3. Marque os itens em Carga consolidada (patio).',
                  '4. Em grupos com 2+ paradas, use as setas na rota para a ordem.',
                  '5. Checklist: Separado → Carregado → Saiu.',
                  '6. Quando tudo estiver ok, toque em "Saiu p/ entrega".',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Kanban',
                icone: Icons.view_kanban_outlined,
                itens: const [
                  'Na aba Dia, alterne para Kanban no topo.',
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

  static String dicaCurtaAba(int indice, {bool kanban = false}) {
    switch (indice) {
      case 0:
        return 'Patio: motorista → viagem → aba Carga ou Rota. "Rota do dia" ordena todas as paradas.';
      case 1:
        return kanban
            ? 'Kanban: arraste o pedido entre colunas para atualizar o status rapidamente.'
            : 'Lista: por motorista, expanda "Rota do dia" para ordenar paradas sem agrupar.';
      default:
        return '';
    }
  }

  static String tituloAba(int indice, {bool kanban = false}) {
    switch (indice) {
      case 0:
        return 'Patio';
      case 1:
        return kanban ? 'Dia · Kanban' : 'Dia · Lista';
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
    this.kanban = false,
  });

  final int indiceAba;
  final VoidCallback onAbrirGuia;
  final VoidCallback onOcultar;
  final bool kanban;

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
                      EntregasGuia.tituloAba(indiceAba, kanban: kanban),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      EntregasGuia.dicaCurtaAba(indiceAba, kanban: kanban),
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
