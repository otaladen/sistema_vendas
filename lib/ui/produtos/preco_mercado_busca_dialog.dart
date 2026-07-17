import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/preco_mercado_resultado.dart';
import '../../services/gemini_service.dart';
import '../../services/preco_mercado_service.dart';

/// Resultado da escolha do usuario no dialog de preco de mercado.
class PrecoMercadoEscolha {
  const PrecoMercadoEscolha({
    required this.preco,
    required this.precoIndice,
  });

  final double preco;
  /// 1, 2 ou 3.
  final int precoIndice;
}

Future<PrecoMercadoEscolha?> mostrarBuscaPrecoMercadoDialog({
  required BuildContext context,
  required PrecoMercadoService service,
  required String nomeProduto,
  String codigoBarras = '',
  String unidade = '',
  int? produtoId,
  double? custoAtual,
  bool podeEditarPreco = true,
}) {
  return showDialog<PrecoMercadoEscolha>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PrecoMercadoBuscaDialog(
      service: service,
      nomeProduto: nomeProduto,
      codigoBarras: codigoBarras,
      unidade: unidade,
      produtoId: produtoId,
      custoAtual: custoAtual,
      podeEditarPreco: podeEditarPreco,
    ),
  );
}

class _PrecoMercadoBuscaDialog extends StatefulWidget {
  const _PrecoMercadoBuscaDialog({
    required this.service,
    required this.nomeProduto,
    required this.codigoBarras,
    required this.unidade,
    required this.produtoId,
    required this.custoAtual,
    required this.podeEditarPreco,
  });

  final PrecoMercadoService service;
  final String nomeProduto;
  final String codigoBarras;
  final String unidade;
  final int? produtoId;
  final double? custoAtual;
  final bool podeEditarPreco;

  @override
  State<_PrecoMercadoBuscaDialog> createState() =>
      _PrecoMercadoBuscaDialogState();
}

class _PrecoMercadoBuscaDialogState extends State<_PrecoMercadoBuscaDialog> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _carregando = true;
  String? _erro;
  PrecoMercadoResumo? _resumo;
  bool _usouGemini = false;

  final _fcController = TextEditingController();
  final _leroyController = TextEditingController();
  final _mlController = TextEditingController();
  final _outroController = TextEditingController();

  double? _medianaManual;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _fcController,
      _leroyController,
      _mlController,
      _outroController,
    ]) {
      c.addListener(_recalcularManual);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_buscar(avancada: false));
    });
  }

  @override
  void dispose() {
    for (final c in [
      _fcController,
      _leroyController,
      _mlController,
      _outroController,
    ]) {
      c.removeListener(_recalcularManual);
      c.dispose();
    }
    super.dispose();
  }

  double? _parseCampo(TextEditingController c) {
    final raw = c.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _recalcularManual() {
    final mapa = <String, double>{};
    final fc = _parseCampo(_fcController);
    final leroy = _parseCampo(_leroyController);
    final ml = _parseCampo(_mlController);
    final outro = _parseCampo(_outroController);
    if (fc != null) mapa['Ferreira Costa'] = fc;
    if (leroy != null) mapa['Leroy Merlin'] = leroy;
    if (ml != null) mapa['Mercado Livre'] = ml;
    if (outro != null) mapa['Outra loja'] = outro;

    if (mapa.isEmpty) {
      setState(() => _medianaManual = null);
      return;
    }
    final calculado = widget.service.resumirPrecosManuais(
      queryUsada: _resumo?.queryUsada ?? widget.nomeProduto,
      precosPorLoja: mapa,
      base: _resumo,
    );
    setState(() => _medianaManual = calculado.precoSugerido);
  }

  Future<void> _buscar({required bool avancada}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resumo = await widget.service.buscar(
        nome: widget.nomeProduto,
        codigoBarras: widget.codigoBarras,
        unidade: widget.unidade,
        produtoId: widget.produtoId,
        avancadaComGemini: avancada,
      );
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _usouGemini = avancada;
        _carregando = false;
      });
      _recalcularManual();
    } on GeminiConfigException catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.message;
      });
    } on GeminiServiceException catch (e) {
      if (!mounted) return;
      final extra = (e.instrucoesCorrecao != null &&
              e.instrucoesCorrecao!.isNotEmpty)
          ? '\n${e.instrucoesCorrecao!.first}'
          : '';
      setState(() {
        _carregando = false;
        _erro = '${e.message}$extra';
      });
    } on PrecoMercadoException catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Falha na busca: $e';
      });
    }
  }

  Future<void> _abrirUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _abrirTodos() async {
    final links = _resumo?.linksExternos ?? const <PrecoMercadoLinkExterno>[];
    for (final link in links.take(4)) {
      await _abrirUrl(link.url);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  Future<void> _copiarNome() async {
    final termo = (_resumo?.queryUsada.split('·').first ?? widget.nomeProduto)
        .trim();
    await Clipboard.setData(ClipboardData(text: termo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado: $termo')),
    );
  }

  Future<void> _colarEExtrairPrecos() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = data?.text?.trim() ?? '';
    if (texto.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Area de transferencia vazia. Copie o texto com R\$ e tente de novo.'),
        ),
      );
      return;
    }

    final porLoja = PrecoMercadoParser.extrairPrecosPorLoja(texto);
    final todos = PrecoMercadoParser.extrairTodosPrecos(texto);

    void preencher(TextEditingController c, double? v) {
      if (v == null) return;
      c.text = v.toStringAsFixed(2).replaceAll('.', ',');
    }

    if (porLoja.isNotEmpty) {
      preencher(_fcController, porLoja['Ferreira Costa']);
      preencher(_leroyController, porLoja['Leroy Merlin']);
      preencher(_mlController, porLoja['Mercado Livre']);
    } else if (todos.isNotEmpty) {
      // Preenche na ordem: FC, Leroy, ML, Outra.
      final campos = [_fcController, _leroyController, _mlController, _outroController];
      for (var i = 0; i < todos.length && i < campos.length; i++) {
        if (campos[i].text.trim().isEmpty) {
          preencher(campos[i], todos[i]);
        }
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao achei R\$ no texto colado.'),
        ),
      );
      return;
    }
    _recalcularManual();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Precos extraidos do texto colado.')),
    );
  }

  void _aplicar(double preco, int indice) {
    Navigator.pop(
      context,
      PrecoMercadoEscolha(preco: preco, precoIndice: indice),
    );
  }

  Widget _campoLoja(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: '0,00',
        prefixText: 'R\$ ',
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final resumo = _resumo;
    final sugerido = _medianaManual ?? resumo?.precoSugerido;
    final custo = widget.custoAtual;

    return AlertDialog(
      title: const Text('Preco de mercado · Salvador'),
      content: SizedBox(
        width: 540,
        child: _carregando
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparando busca regional…'),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Produto: ${widget.nomeProduto.trim().isEmpty ? '(sem nome)' : widget.nomeProduto.trim()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (resumo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        resumo.queryUsada,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Scraping automatico e bloqueado. Abrir Google/lojas '
                        'no navegador funciona. Depois digite os precos ou '
                        'cole um texto com R\$.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 10),
                      Text(_erro!, style: TextStyle(color: cs.error)),
                    ],
                    if (resumo?.aviso.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        resumo!.aviso,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary,
                        ),
                      ),
                    ],
                    if (resumo?.linksExternos.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Abrir no navegador',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => unawaited(_abrirTodos()),
                            icon: const Icon(Icons.library_books_outlined, size: 16),
                            label: const Text('Abrir todos'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(_copiarNome()),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copiar nome'),
                          ),
                          for (final link in resumo!.linksExternos)
                            OutlinedButton.icon(
                              onPressed: () => unawaited(_abrirUrl(link.url)),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: Text(link.rotulo),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Precos encontrados',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => unawaited(_colarEExtrairPrecos()),
                          icon: const Icon(Icons.content_paste, size: 16),
                          label: const Text('Colar R\$'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _campoLoja('Ferreira Costa', _fcController),
                    const SizedBox(height: 8),
                    _campoLoja('Leroy Merlin', _leroyController),
                    const SizedBox(height: 8),
                    _campoLoja('Mercado Livre', _mlController),
                    const SizedBox(height: 8),
                    _campoLoja('Outra loja (opcional)', _outroController),
                    if (sugerido != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _medianaManual != null
                                  ? 'Media Salvador (precos informados)'
                                  : 'Sugestao automatica',
                              style: theme.textTheme.labelMedium,
                            ),
                            Text(
                              _moeda.format(sugerido),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (custo != null && custo > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Com custo ${_moeda.format(custo)}: margem '
                                '${(((sugerido - custo) / sugerido) * 100).toStringAsFixed(1)}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (resumo?.historicoLojaMediana != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Na sua loja (180 dias): '
                        '${_moeda.format(resumo!.historicoLojaMediana)} '
                        '(${resumo.historicoLojaAmostras} vendas)',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (resumo?.dicaGemini.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Gemini: ${resumo!.dicaGemini}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (_usouGemini) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Busca avancada usou 1 consulta Gemini.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _carregando ? null : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        if (!_carregando)
          TextButton.icon(
            onPressed: () => unawaited(_buscar(avancada: false)),
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar'),
          ),
        if (!_carregando)
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Busca avancada (Gemini)'),
                  content: const Text(
                    'Usa 1 consulta Gemini so para melhorar o nome da busca '
                    '(ex.: "Cimento Poty 50kg"). Nao inventa preco.\n\n'
                    'Depois abra os links e informe os valores.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Usar Gemini'),
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) {
                await _buscar(avancada: true);
              }
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Avancada'),
          ),
        if (!_carregando &&
            widget.podeEditarPreco &&
            sugerido != null &&
            sugerido > 0)
          PopupMenuButton<int>(
            tooltip: 'Aplicar media no preco de venda',
            onSelected: (indice) => _aplicar(sugerido, indice),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 1, child: Text('Aplicar no Preco 1')),
              PopupMenuItem(value: 2, child: Text('Aplicar no Preco 2')),
              PopupMenuItem(value: 3, child: Text('Aplicar no Preco 3')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 18),
                  SizedBox(width: 6),
                  Text('Aplicar media'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
