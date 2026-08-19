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
                titulo: 'Fluxo do dia (resumo)',
                icone: Icons.play_arrow_outlined,
                itens: const [
                  '1) Escolha o dia no topo (abre em Hoje).',
                  '2) Defina o motorista no pedido.',
                  '3) O motorista carrega na outra loja e toca em Sair para entrega no celular.',
                  '4) Nesta tela acompanhe: Aguardando motorista → Em rota → Entregue.',
                  '5) Quando o cliente receber, o motorista marca Entregue no celular '
                      '(ou use Marcar entregue aqui se precisar).',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Quando o estoque e baixado',
                icone: Icons.inventory_2_outlined,
                itens: const [
                  'Na venda (PDV), itens de carreto/entrega ficam RESERVADOS (ainda nao saem do fisico).',
                  'Quando o motorista toca em Sair para entrega, a reserva e liberada. '
                      'O fisico desta loja so baixa se ele pediu para buscar material aqui '
                      'e o patio confirmou Separar aqui.',
                  'Se a loja permite venda sem estoque, a saida nao trava com '
                      'fisico zerado — o saldo pode ficar negativo ate a NF-e de entrada.',
                  'Itens "Retira logo" / leva agora ja baixam no caixa; '
                      'nao entram nessa regra do carreto.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Acompanhar a viagem',
                icone: Icons.warehouse_outlined,
                itens: const [
                  'Selecione o motorista e a viagem (pedido ou grupo no mesmo carro).',
                  'Aba Carga: veja o que vai no carro. Se o motorista pedir material '
                      'desta loja, aparece Separar aqui.',
                  'Aba Rota: acompanhe as paradas (setas para ordenar se houver 2+ pedidos).',
                  'A saida e do motorista no celular. Liberar saida nesta tela fica '
                      'no menu, so se o celular nao tiver sido usado.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Se o produto NAO for entregue',
                icone: Icons.report_problem_outlined,
                itens: const [
                  'Faltou item na ida (cliente recebeu so parte): com status '
                      '"Saiu para entrega", use o menu → Faltou item (complemento). '
                      'Registra o que faltou e deixa complemento pendente para uma 2a viagem.',
                  'Depois da 2a viagem: Concluir complemento → vira Entregue '
                      '(estoque do complemento e tratado nessa etapa).',
                  'Cliente nao estava / remarcar dia: Status → Reagendada '
                      '(informe o motivo) e marque a nova data de entrega.',
                  'Mercadoria voltou pro estoque apos ter saido no carro: menu → '
                      'Devolucao / troca (mercadoria voltou). Isso devolve o fisico.',
                  'Entrega cancelada de vez: Status → Cancelada (com motivo). '
                      'Use com cuidado — veja o historico do pedido.',
                  'Ainda aguardando o motorista sair: so troque motorista, '
                      'data ou remova do dia — o estoque ainda esta so reservado.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Lista e Kanban (aba Dia)',
                icone: Icons.view_list_outlined,
                itens: const [
                  'Lista: defina o motorista e acompanhe. Botao principal = '
                      'Marcar entregue (depois que o motorista saiu).',
                  'Kanban: Aguardando motorista → Em rota → Entregue. '
                      'O motorista passa para Em rota pelo celular.',
                  'Opcional: Agrupar mesmo carro junta varios pedidos numa viagem.',
                ],
              ),
              _secao(
                ctx,
                titulo: 'Dicas de operacao',
                icone: Icons.tips_and_updates_outlined,
                itens: const [
                  'O motorista libera a saida no celular (Sair para entrega).',
                  'Se faltar material na outra loja, ele pede buscar nesta loja; '
                      'o patio confirma Separar aqui. Se chegar de ultima hora la, '
                      'o motorista pode desistir mesmo depois do aceite — o estoque desta loja volta.',
                  'Use o Historico do pedido para ver quem mudou status e quando.',
                  'Filtros Atr. / Pend. hoje e Sem motorista ajudam a limpar a fila do dia.',
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
        return 'Acompanhe a viagem. O motorista libera a saida no celular. '
            'Se ele pedir material desta loja, use Separar aqui.';
      case 1:
        return kanban
            ? 'Kanban: Aguardando motorista → Em rota → Entregue.'
            : 'Lista: defina o motorista e acompanhe. Entregue depois que ele sair.';
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
