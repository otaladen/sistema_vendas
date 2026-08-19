import 'package:flutter/material.dart';

import '../../model/motorista.dart';

/// Conta filtros diferentes do padrao (para badge no botao Filtros).
int contarFiltrosEntregaAtivos({
  required String status,
  required String motorista,
  required String vendedor,
  required String agrupamento,
  required String dataMarcada,
  required String bairro,
  required String numeroNota,
  required DateTime? inicio,
  required DateTime? fim,
}) {
  var n = 0;
  if (status != 'todos') n++;
  if (motorista != 'todos') n++;
  if (vendedor != 'todos') n++;
  if (agrupamento != 'motorista') n++;
  if (dataMarcada != 'todos') n++;
  if (bairro.trim().isNotEmpty) n++;
  if (numeroNota.trim().isNotEmpty) n++;
  if (inicio != null || fim != null) n++;
  return n;
}

List<String> resumosFiltrosEntregaAtivos({
  required String status,
  required String Function(String) rotuloStatus,
  required String motorista,
  required String nomeMotoristaExibicao,
  required String vendedor,
  required String nomeVendedorExibicao,
  required String agrupamento,
  required String dataMarcada,
  required String bairro,
  required String numeroNota,
  required String rotuloPeriodo,
}) {
  final chips = <String>[];
  if (status != 'todos') chips.add('Status: ${rotuloStatus(status)}');
  if (motorista != 'todos') {
    chips.add('Motorista: $nomeMotoristaExibicao');
  }
  if (vendedor != 'todos') chips.add('Vendedor: $nomeVendedorExibicao');
  if (agrupamento != 'motorista') {
    chips.add('Agrupar: ${agrupamento == 'motorista' ? 'Motorista' : 'Bairro'}');
  }
  if (dataMarcada != 'todos') {
    final rotulo = switch (dataMarcada) {
      'hoje' => 'Hoje',
      'amanha' => 'Amanha',
      'sem_data' => 'Sem data',
      _ => dataMarcada,
    };
    chips.add('Data marcada: $rotulo');
  }
  if (bairro.trim().isNotEmpty) {
    chips.add('Bairro: ${bairro.trim()}');
  }
  if (numeroNota.trim().isNotEmpty) {
    chips.add('Nota: ${numeroNota.trim()}');
  }
  if (rotuloPeriodo != 'Periodo: todos' &&
      rotuloPeriodo != 'Marcadas para hoje') {
    chips.add(rotuloPeriodo);
  }
  return chips;
}

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

String _valorDropdownPresente(String atual, Iterable<String> opcoes) {
  for (final o in opcoes) {
    if (o == atual) return atual;
  }
  return opcoes.isEmpty ? atual : opcoes.first;
}

/// Painel inferior com todos os filtros da aba Entregas.
Future<void> showFiltrosEntregaSheet({
  required BuildContext context,
  required int filtrosDropdownNonce,
  required List<String> statuses,
  required String Function(String) rotuloStatus,
  required String statusSelecionado,
  required ValueChanged<String> onStatus,
  required String filtroMotorista,
  required List<Motorista> motoristasAtivos,
  required ValueChanged<String> onMotorista,
  required String filtroVendedor,
  required List<String> vendedoresDisponiveis,
  required ValueChanged<String> onVendedor,
  required String agrupamento,
  required ValueChanged<String> onAgrupamento,
  required String filtroDataMarcada,
  required ValueChanged<String> onDataMarcada,
  required TextEditingController numeroNotaController,
  required TextEditingController bairroController,
  required VoidCallback onAplicarTexto,
  required VoidCallback onLimparTudo,
  required VoidCallback onPeriodoHoje,
  required VoidCallback onPeriodoPersonalizado,
  required String rotuloPeriodo,
  required List<String> resumosAtivos,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
      return SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Text(
                    'Filtros e periodo',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (resumosAtivos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: resumosAtivos
                      .map(
                        (t) => Chip(
                          label: Text(t),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('sheet_status_$filtrosDropdownNonce'),
                    initialValue: _valorDropdownPresente(
                      statusSelecionado,
                      statuses,
                    ),
                    isExpanded: true,
                    decoration: _dec('Status'),
                    items: statuses
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(rotuloStatus(s)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      onStatus(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('sheet_mot_$filtrosDropdownNonce'),
                    initialValue: _valorDropdownPresente(
                      filtroMotorista,
                      [
                        'todos',
                        ...{
                          for (final m in motoristasAtivos)
                            m.nome.trim().toLowerCase(),
                        }.where((n) => n.isNotEmpty),
                      ],
                    ),
                    isExpanded: true,
                    decoration: _dec('Motorista'),
                    items: [
                      const DropdownMenuItem(
                        value: 'todos',
                        child: Text('Todos'),
                      ),
                      ...{
                        for (final m in motoristasAtivos)
                          m.nome.trim().toLowerCase(): m.nome.trim(),
                      }.entries
                          .where((e) => e.key.isNotEmpty)
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      onMotorista(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('sheet_vend_$filtrosDropdownNonce'),
                    initialValue: _valorDropdownPresente(
                      filtroVendedor,
                      [
                        'todos',
                        ...vendedoresDisponiveis.map((n) => n.toLowerCase()),
                      ],
                    ),
                    isExpanded: true,
                    decoration: _dec('Vendedor'),
                    items: [
                      const DropdownMenuItem(
                        value: 'todos',
                        child: Text('Todos'),
                      ),
                      ...vendedoresDisponiveis.map(
                        (nome) => DropdownMenuItem(
                          value: nome.toLowerCase(),
                          child: Text(nome),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      onVendedor(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('sheet_agr_$filtrosDropdownNonce'),
                    initialValue: _valorDropdownPresente(
                      agrupamento,
                      const ['bairro', 'motorista'],
                    ),
                    decoration: _dec('Agrupar lista por'),
                    items: const [
                      DropdownMenuItem(value: 'bairro', child: Text('Bairro')),
                      DropdownMenuItem(
                        value: 'motorista',
                        child: Text('Motorista'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      onAgrupamento(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('sheet_dm_$filtrosDropdownNonce'),
                    initialValue: _valorDropdownPresente(
                      filtroDataMarcada,
                      const ['todos', 'hoje', 'amanha', 'sem_data'],
                    ),
                    decoration: _dec('Data marcada na entrega'),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todas')),
                      DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
                      DropdownMenuItem(value: 'amanha', child: Text('Amanha')),
                      DropdownMenuItem(
                        value: 'sem_data',
                        child: Text('Sem data marcada'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      onDataMarcada(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: numeroNotaController,
                    decoration: _dec('N. da nota'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bairroController,
                    decoration: _dec('Bairro / endereco'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      onAplicarTexto();
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Periodo da venda (repositorio)',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Chip(label: Text(rotuloPeriodo)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          onPeriodoHoje();
                        },
                        child: const Text('Marcadas hoje'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onPeriodoPersonalizado,
                        icon: const Icon(Icons.date_range_outlined, size: 18),
                        label: const Text('Periodo personalizado'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        onLimparTudo();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Limpar tudo'),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () {
                        onAplicarTexto();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Aplicar busca'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
