import 'package:flutter/material.dart';

import '../../domain/venda_documento_rotulo_helper.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../model/venda.dart';
import 'entrega_insucesso_faixa.dart';
import 'logistica_entregas.dart';

/// Visao operacional enxuta para loja pequena (ex.: 2 motoristas / 2 caminhoes).
///
/// Foco do dia: sem motorista + raias por motorista + acao principal do pedido.
class EntregasVisaoSimples extends StatelessWidget {
  const EntregasVisaoSimples({
    super.key,
    required this.entregas,
    required this.nomesMotoristas,
    required this.atrasadas,
    required this.diaEhHoje,
    required this.diaEhAmanha,
    required this.rotuloDiaSelecionado,
    required this.rotuloStatus,
    required this.corStatus,
    required this.labelAcaoPrincipal,
    required this.onHoje,
    required this.onAmanha,
    required this.onEscolherDia,
    required this.onAtribuirMotorista,
    required this.onAcaoPrincipal,
    required this.onAbrirDetalhes,
    required this.onVisaoAvancada,
    this.podeGerenciar = true,
  });

  final List<Venda> entregas;
  final List<String> nomesMotoristas;
  final int atrasadas;
  final bool diaEhHoje;
  final bool diaEhAmanha;
  final String rotuloDiaSelecionado;
  final String Function(String status) rotuloStatus;
  final Color Function(ColorScheme scheme, String status) corStatus;
  final String? Function(Venda venda) labelAcaoPrincipal;
  final VoidCallback onHoje;
  final VoidCallback onAmanha;
  final VoidCallback onEscolherDia;
  final ValueChanged<Venda> onAtribuirMotorista;
  final Future<void> Function(Venda venda) onAcaoPrincipal;
  final ValueChanged<Venda> onAbrirDetalhes;
  final VoidCallback onVisaoAvancada;
  final bool podeGerenciar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final semMotorista = entregas
        .where((v) => !motoristaLogisticaDefinido(nomeMotoristaEntrega(v)))
        .toList();

    final porMotorista = <String, List<Venda>>{
      for (final nome in nomesMotoristas) nome: <Venda>[],
    };
    final outros = <Venda>[];
    for (final v in entregas) {
      final nome = nomeMotoristaEntrega(v).trim();
      if (!motoristaLogisticaDefinido(nome)) continue;
      if (porMotorista.containsKey(nome)) {
        porMotorista[nome]!.add(v);
      } else {
        outros.add(v);
      }
    }

    final largura = MediaQuery.sizeOf(context).width;
    final colunasLaterais = largura >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CabecalhoSimples(
          atrasadas: atrasadas,
          semMotorista: semMotorista.length,
          diaEhHoje: diaEhHoje,
          diaEhAmanha: diaEhAmanha,
          rotuloDiaSelecionado: rotuloDiaSelecionado,
          onHoje: onHoje,
          onAmanha: onAmanha,
          onEscolherDia: onEscolherDia,
          onVisaoAvancada: onVisaoAvancada,
        ),
        const SizedBox(height: 10),
        if (semMotorista.isNotEmpty) ...[
          _FaixaSemMotorista(
            vendas: semMotorista,
            rotuloStatus: rotuloStatus,
            onAtribuir: onAtribuirMotorista,
            onDetalhes: onAbrirDetalhes,
            podeGerenciar: podeGerenciar,
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: colunasLaterais
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < nomesMotoristas.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _ColunaMotorista(
                          titulo: nomesMotoristas[i],
                          vendas: porMotorista[nomesMotoristas[i]] ?? const [],
                          rotuloStatus: rotuloStatus,
                          corStatus: corStatus,
                          labelAcaoPrincipal: labelAcaoPrincipal,
                          onAtribuirMotorista: onAtribuirMotorista,
                          onAcaoPrincipal: onAcaoPrincipal,
                          onAbrirDetalhes: onAbrirDetalhes,
                          podeGerenciar: podeGerenciar,
                        ),
                      ),
                    ],
                    if (outros.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ColunaMotorista(
                          titulo: 'Outros motoristas',
                          vendas: outros,
                          rotuloStatus: rotuloStatus,
                          corStatus: corStatus,
                          labelAcaoPrincipal: labelAcaoPrincipal,
                          onAtribuirMotorista: onAtribuirMotorista,
                          onAcaoPrincipal: onAcaoPrincipal,
                          onAbrirDetalhes: onAbrirDetalhes,
                          podeGerenciar: podeGerenciar,
                        ),
                      ),
                    ],
                  ],
                )
              : ListView(
                  children: [
                    for (final nome in nomesMotoristas) ...[
                      _ColunaMotorista(
                        titulo: nome,
                        vendas: porMotorista[nome] ?? const [],
                        rotuloStatus: rotuloStatus,
                        corStatus: corStatus,
                        labelAcaoPrincipal: labelAcaoPrincipal,
                        onAtribuirMotorista: onAtribuirMotorista,
                        onAcaoPrincipal: onAcaoPrincipal,
                        onAbrirDetalhes: onAbrirDetalhes,
                        podeGerenciar: podeGerenciar,
                        alturaFixa: 280,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (outros.isNotEmpty)
                      _ColunaMotorista(
                        titulo: 'Outros motoristas',
                        vendas: outros,
                        rotuloStatus: rotuloStatus,
                        corStatus: corStatus,
                        labelAcaoPrincipal: labelAcaoPrincipal,
                        onAtribuirMotorista: onAtribuirMotorista,
                        onAcaoPrincipal: onAcaoPrincipal,
                        onAbrirDetalhes: onAbrirDetalhes,
                        podeGerenciar: podeGerenciar,
                        alturaFixa: 280,
                      ),
                    if (nomesMotoristas.isEmpty &&
                        semMotorista.isEmpty &&
                        entregas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nenhuma entrega para este dia.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (nomesMotoristas.isEmpty && entregas.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Cadastre motoristas em Cadastros → Motoristas '
                          'para organizar por caminhao.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CabecalhoSimples extends StatelessWidget {
  const _CabecalhoSimples({
    required this.atrasadas,
    required this.semMotorista,
    required this.diaEhHoje,
    required this.diaEhAmanha,
    required this.rotuloDiaSelecionado,
    required this.onHoje,
    required this.onAmanha,
    required this.onEscolherDia,
    required this.onVisaoAvancada,
  });

  final int atrasadas;
  final int semMotorista;
  final bool diaEhHoje;
  final bool diaEhAmanha;
  final String rotuloDiaSelecionado;
  final VoidCallback onHoje;
  final VoidCallback onAmanha;
  final VoidCallback onEscolherDia;
  final VoidCallback onVisaoAvancada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Entregas do dia',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onVisaoAvancada,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Visão avançada'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Hoje'),
                  selected: diaEhHoje,
                  onSelected: (_) => onHoje(),
                ),
                ChoiceChip(
                  label: const Text('Amanhã'),
                  selected: diaEhAmanha,
                  onSelected: (_) => onAmanha(),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(rotuloDiaSelecionado),
                  onPressed: onEscolherDia,
                ),
                if (atrasadas > 0)
                  Chip(
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.red.shade700,
                    ),
                    label: Text('Atrasadas $atrasadas'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (semMotorista > 0)
                  Chip(
                    avatar: const Icon(Icons.person_off_outlined, size: 18),
                    label: Text('Sem motorista $semMotorista'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FaixaSemMotorista extends StatelessWidget {
  const _FaixaSemMotorista({
    required this.vendas,
    required this.rotuloStatus,
    required this.onAtribuir,
    required this.onDetalhes,
    required this.podeGerenciar,
  });

  final List<Venda> vendas;
  final String Function(String status) rotuloStatus;
  final ValueChanged<Venda> onAtribuir;
  final ValueChanged<Venda> onDetalhes;
  final bool podeGerenciar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Precisam de motorista (${vendas.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...vendas.take(8).map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  title: Text(
                    '${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(v)} · ${VendaRelacaoSafe.nomeCliente(v)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rotuloStatus(v.statusEntrega)),
                      EntregaInsucessoFaixa(
                        venda: v,
                        padding: const EdgeInsets.only(top: 2),
                      ),
                    ],
                  ),
                  trailing: podeGerenciar
                      ? FilledButton.tonal(
                          onPressed: () => onAtribuir(v),
                          child: const Text('Atribuir'),
                        )
                      : null,
                  onTap: () => onDetalhes(v),
                ),
              ),
            ),
            if (vendas.length > 8)
              Text(
                '+ ${vendas.length - 8} pedido(s)',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _ColunaMotorista extends StatelessWidget {
  const _ColunaMotorista({
    required this.titulo,
    required this.vendas,
    required this.rotuloStatus,
    required this.corStatus,
    required this.labelAcaoPrincipal,
    required this.onAtribuirMotorista,
    required this.onAcaoPrincipal,
    required this.onAbrirDetalhes,
    required this.podeGerenciar,
    this.alturaFixa,
  });

  final String titulo;
  final List<Venda> vendas;
  final String Function(String status) rotuloStatus;
  final Color Function(ColorScheme scheme, String status) corStatus;
  final String? Function(Venda venda) labelAcaoPrincipal;
  final ValueChanged<Venda> onAtribuirMotorista;
  final Future<void> Function(Venda venda) onAcaoPrincipal;
  final ValueChanged<Venda> onAbrirDetalhes;
  final bool podeGerenciar;
  final double? alturaFixa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final abertas = vendas
        .where((v) =>
            v.statusEntrega != 'entregue' && v.statusEntrega != 'cancelada')
        .length;

    final painel = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$abertas aberta(s)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: vendas.isEmpty
                ? Center(
                    child: Text(
                      'Sem entregas neste dia',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    itemCount: vendas.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final v = vendas[i];
                      final label = labelAcaoPrincipal(v);
                      final cor = corStatus(scheme, v.statusEntrega);
                      return Material(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onAbrirDetalhes(v),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        VendaDocumentoRotuloHelper.hashIdentificadorEntrega(v),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        rotuloStatus(v.statusEntrega),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: cor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  VendaRelacaoSafe.nomeCliente(v),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if ((v.enderecoEntrega).trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    v.enderecoEntrega.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                EntregaInsucessoFaixa(venda: v),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => onAtribuirMotorista(v),
                                      child: const Text('Motorista'),
                                    ),
                                    const Spacer(),
                                    if (label != null && podeGerenciar)
                                      FilledButton(
                                        onPressed: () => onAcaoPrincipal(v),
                                        child: Text(label),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    if (alturaFixa != null) {
      return SizedBox(height: alturaFixa, child: painel);
    }
    return painel;
  }
}
