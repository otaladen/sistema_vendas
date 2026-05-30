import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/venda_repository.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/plano_fiado.dart';
import '../../model/venda.dart';
import '../widgets/plano_fiado_pdv_panel.dart';

/// Dialogo para trocar forma de pagamento do orcamento no caixa (apos autorizacao).
class AlterarPagamentoCaixaDialog extends StatefulWidget {
  const AlterarPagamentoCaixaDialog({
    super.key,
    required this.venda,
    required this.totalExibidoCaixa,
    required this.totalGravacaoOrcamento,
    required this.clienteVinculado,
    required this.formatarMoeda,
  });

  final Venda venda;
  final double totalExibidoCaixa;
  final double totalGravacaoOrcamento;
  final bool clienteVinculado;
  final String Function(double) formatarMoeda;

  @override
  State<AlterarPagamentoCaixaDialog> createState() =>
      _AlterarPagamentoCaixaDialogState();
}

class _LinhaMistoEditavel {
  _LinhaMistoEditavel({
    required this.meio,
    required this.valorController,
    this.parcelas = 1,
  });

  String meio;
  final TextEditingController valorController;
  int parcelas;

  void dispose() => valorController.dispose();
}

class _AlterarPagamentoCaixaDialogState
    extends State<AlterarPagamentoCaixaDialog> {
  static const _meiosSimples = [
    ('dinheiro', 'Dinheiro'),
    ('pix', 'PIX'),
    ('cartao_debito', 'Debito'),
    ('cartao_credito', 'Credito'),
    ('transferencia', 'Transferencia'),
    ('fiado', 'Fiado'),
  ];

  static const _meiosMisto = _meiosSimples;

  late bool _modoMisto;
  late String _formaSimples;
  late int _parcelasSimples;
  final List<_LinhaMistoEditavel> _linhasMisto = [];
  List<PlanoFiadoParcela> _planoFiado = [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    final v = widget.venda;
    _modoMisto = v.formaPagamento == 'misto' &&
        v.pagamentosJson.trim().isNotEmpty;
    if (_modoMisto) {
      final linhas = _linhasEscaladasParaExibicao();
      for (final l in linhas) {
        _linhasMisto.add(
          _LinhaMistoEditavel(
            meio: l.meio,
            valorController: TextEditingController(
              text: _formatarValorCampo(l.valor),
            ),
            parcelas: l.parcelas,
          ),
        );
      }
      if (_linhasMisto.length < 2) {
        _adicionarLinhaMisto();
      }
    } else {
      _formaSimples = v.formaPagamento;
      _parcelasSimples = v.quantidadeParcelas.clamp(1, 24);
    }
    _planoFiado = PlanoFiadoCodec.decode(v.planoFiadoJson);
  }

  @override
  void dispose() {
    for (final l in _linhasMisto) {
      l.dispose();
    }
    super.dispose();
  }

  List<PagamentoOrcamentoLinha> _linhasEscaladasParaExibicao() {
    final linhas = PagamentoOrcamentoCodec.decode(widget.venda.pagamentosJson);
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return const [];
    final fator = widget.totalExibidoCaixa / soma;
    return linhas
        .map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: l.valor * fator,
            parcelas: l.parcelas,
          ),
        )
        .toList();
  }

  String _formatarValorCampo(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  double? _parseValor(String raw) {
    final t = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double _valorFiadoAtual() {
    if (_modoMisto) {
      final exibido = _linhasMisto
          .where((l) => l.meio == 'fiado')
          .fold<double>(0, (s, l) => s + (_parseValor(l.valorController.text) ?? 0));
      if (widget.totalExibidoCaixa <= 0.001) return exibido;
      return exibido *
          (widget.totalGravacaoOrcamento / widget.totalExibidoCaixa);
    }
    if (_formaSimples == 'fiado') return widget.totalGravacaoOrcamento;
    return 0;
  }

  bool _podeSelecionarFiadoMisto(String meioAtual) {
    if (meioAtual == 'fiado') return true;
    return !_linhasMisto.any((l) => l.meio == 'fiado');
  }

  void _adicionarLinhaMisto() {
    final restante = widget.totalExibidoCaixa -
        _linhasMisto.fold<double>(
          0,
          (s, l) => s + (_parseValor(l.valorController.text) ?? 0),
        );
    _linhasMisto.add(
      _LinhaMistoEditavel(
        meio: 'dinheiro',
        valorController: TextEditingController(
          text: _formatarValorCampo(restante.clamp(0, double.infinity)),
        ),
      ),
    );
  }

  void _removerLinhaMisto(int index) {
    if (_linhasMisto.length <= 2) return;
    _linhasMisto.removeAt(index).dispose();
    setState(() {});
  }

  List<PagamentoOrcamentoLinha> _linhasMistoParaGravacao() {
    if (widget.totalExibidoCaixa <= 0.001) {
      return _linhasMisto
          .map(
            (l) => PagamentoOrcamentoLinha(
              meio: l.meio,
              valor: _parseValor(l.valorController.text) ?? 0,
              parcelas: l.meio == 'cartao_credito' ? l.parcelas : 1,
            ),
          )
          .where((l) => l.valor > 0.001)
          .toList();
    }
    final fator = widget.totalGravacaoOrcamento / widget.totalExibidoCaixa;
    return _linhasMisto
        .map((l) {
          final valorExibido = _parseValor(l.valorController.text) ?? 0;
          return PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: valorExibido * fator,
            parcelas: l.meio == 'cartao_credito' ? l.parcelas : 1,
          );
        })
        .where((l) => l.valor > 0.001)
        .toList();
  }

  void _confirmar() {
    setState(() => _erro = null);

    if (_modoMisto) {
      final linhas = _linhasMistoParaGravacao();
      if (linhas.length < 2) {
        setState(() => _erro = 'Pagamento misto exige pelo menos 2 linhas.');
        return;
      }
      final soma = PagamentoOrcamentoCodec.soma(linhas);
      if ((soma - widget.totalGravacaoOrcamento).abs() > 0.05) {
        setState(
          () => _erro =
              'A soma dos meios (${widget.formatarMoeda(soma)}) deve igualar '
              'o total (${widget.formatarMoeda(widget.totalGravacaoOrcamento)}).',
        );
        return;
      }
      for (final l in linhas) {
        if (l.meio == 'cartao_debito' && l.parcelas != 1) {
          setState(
            () => _erro = 'Cartao de debito deve ser a vista em cada linha.',
          );
          return;
        }
      }
      final valorFiado = PagamentoOrcamentoCodec.somaPorMeio(linhas, 'fiado');
      if (valorFiado > 0.001 && !widget.clienteVinculado) {
        setState(
          () => _erro = 'Vincule um cliente antes de usar fiado.',
        );
        return;
      }
      if (valorFiado > 0.001 &&
          !PlanoFiadoCodec.validarContraValor(_planoFiado, valorFiado)) {
        setState(
          () => _erro = 'Defina o plano de parcelas do fiado abaixo.',
        );
        return;
      }
      Navigator.of(context).pop(
        DadosPagamentoOrcamento(
          formaPagamento: 'misto',
          quantidadeParcelas: 1,
          linhasMisto: linhas,
          planoFiado: valorFiado > 0.001 ? List.from(_planoFiado) : null,
        ),
      );
      return;
    }

    if (_formaSimples == 'fiado' && !widget.clienteVinculado) {
      setState(() => _erro = 'Vincule um cliente antes de usar fiado.');
      return;
    }
    final valorFiado =
        _formaSimples == 'fiado' ? widget.totalGravacaoOrcamento : 0.0;
    if (valorFiado > 0.001 &&
        !PlanoFiadoCodec.validarContraValor(_planoFiado, valorFiado)) {
      setState(() => _erro = 'Defina o plano de parcelas do fiado abaixo.');
      return;
    }
    if (_formaSimples == 'cartao_debito' && _parcelasSimples != 1) {
      setState(() => _erro = 'Cartao de debito deve ser a vista (1x).');
      return;
    }

    Navigator.of(context).pop(
      DadosPagamentoOrcamento(
        formaPagamento: _formaSimples,
        quantidadeParcelas:
            _formaSimples == 'cartao_credito' ? _parcelasSimples : 1,
        planoFiado: valorFiado > 0.001 ? List.from(_planoFiado) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valorFiado = _valorFiadoAtual();

    return AlertDialog(
      title: const Text('Alterar forma de pagamento'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total: ${widget.formatarMoeda(widget.totalExibidoCaixa)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Forma unica')),
                  ButtonSegment(value: true, label: Text('Misto')),
                ],
                selected: {_modoMisto},
                onSelectionChanged: (values) {
                  setState(() {
                    _modoMisto = values.first;
                    if (_modoMisto && _linhasMisto.isEmpty) {
                      final metade = widget.totalExibidoCaixa / 2;
                      _linhasMisto.addAll([
                        _LinhaMistoEditavel(
                          meio: 'dinheiro',
                          valorController: TextEditingController(
                            text: _formatarValorCampo(metade),
                          ),
                        ),
                        _LinhaMistoEditavel(
                          meio: 'pix',
                          valorController: TextEditingController(
                            text: _formatarValorCampo(metade),
                          ),
                        ),
                      ]);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              if (!_modoMisto) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final op in _meiosSimples)
                      ChoiceChip(
                        label: Text(op.$2),
                        selected: _formaSimples == op.$1,
                        onSelected: (op.$1 == 'fiado' && !widget.clienteVinculado)
                            ? null
                            : (_) {
                                setState(() {
                                  _formaSimples = op.$1;
                                  if (_formaSimples != 'cartao_credito') {
                                    _parcelasSimples = 1;
                                  }
                                });
                              },
                      ),
                  ],
                ),
                if (_formaSimples == 'cartao_credito') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Parcelas:'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _parcelasSimples,
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(value: i, child: Text('${i}x')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _parcelasSimples = v);
                        },
                      ),
                    ],
                  ),
                ],
              ] else ...[
                for (var i = 0; i < _linhasMisto.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _linhasMisto[i].meio,
                            decoration: const InputDecoration(
                              labelText: 'Meio',
                              isDense: true,
                            ),
                            items: [
                              for (final op in _meiosMisto)
                                DropdownMenuItem(
                                  value: op.$1,
                                  enabled: op.$1 != 'fiado' ||
                                      widget.clienteVinculado,
                                  child: Text(op.$2),
                                ),
                            ],
                            onChanged: (meio) {
                              if (meio == null) return;
                              if (meio == 'fiado' &&
                                  !_podeSelecionarFiadoMisto(
                                    _linhasMisto[i].meio,
                                  )) {
                                return;
                              }
                              setState(() {
                                _linhasMisto[i].meio = meio;
                                if (meio != 'cartao_credito') {
                                  _linhasMisto[i].parcelas = 1;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _linhasMisto[i].valorController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Valor',
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_linhasMisto[i].meio == 'cartao_credito') ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: DropdownButtonFormField<int>(
                              value: _linhasMisto[i].parcelas,
                              decoration: const InputDecoration(
                                labelText: 'Parc.',
                                isDense: true,
                              ),
                              items: [
                                for (var p = 1; p <= 12; p++)
                                  DropdownMenuItem(
                                    value: p,
                                    child: Text('${p}x'),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _linhasMisto[i].parcelas = v);
                              },
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Remover linha',
                          onPressed: _linhasMisto.length <= 2
                              ? null
                              : () => _removerLinhaMisto(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _adicionarLinhaMisto,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar meio'),
                  ),
                ),
              ],
              if (valorFiado > 0.001) ...[
                const SizedBox(height: 8),
                PlanoFiadoPdvPanel(
                  valorFiado: valorFiado,
                  parcelasIniciais: _planoFiado.isEmpty ? null : _planoFiado,
                  onChanged: (parcelas) {
                    _planoFiado = parcelas;
                  },
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erro!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
