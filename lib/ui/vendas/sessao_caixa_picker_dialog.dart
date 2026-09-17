import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/objectbox.dart';
import '../../domain/sessao_caixa_catalogo_loader.dart';
import '../../domain/sessao_caixa_referencia.dart';

/// Dialogo para escolher uma sessao de caixa (busca + paginacao).
Future<SessaoCaixaReferencia?> showSessaoCaixaPickerDialog(
  BuildContext context, {
  ObjectBox? objectBox,
  LanApiClient? lanApiClient,
  SessaoCaixaReferencia? selecionadaAtual,
}) {
  return showDialog<SessaoCaixaReferencia>(
    context: context,
    builder: (ctx) => _SessaoCaixaPickerDialog(
      objectBox: objectBox,
      lanApiClient: lanApiClient,
      selecionadaAtual: selecionadaAtual,
    ),
  );
}

class _SessaoCaixaPickerDialog extends StatefulWidget {
  const _SessaoCaixaPickerDialog({
    this.objectBox,
    this.lanApiClient,
    this.selecionadaAtual,
  });

  final ObjectBox? objectBox;
  final LanApiClient? lanApiClient;
  final SessaoCaixaReferencia? selecionadaAtual;

  @override
  State<_SessaoCaixaPickerDialog> createState() =>
      _SessaoCaixaPickerDialogState();
}

class _SessaoCaixaPickerDialogState extends State<_SessaoCaixaPickerDialog> {
  static const _presets = <({String id, String label, int? dias})>[
    (id: '30', label: 'Ultimos 30 dias', dias: 30),
    (id: '90', label: 'Ultimos 90 dias', dias: 90),
    (id: '365', label: 'Ultimo ano', dias: 365),
    (id: 'tudo', label: 'Todo historico', dias: null),
  ];

  final _buscaController = TextEditingController();
  final _scrollController = ScrollController();
  final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');
  Timer? _debounce;

  String _preset = '30';
  List<SessaoCaixaReferencia> _itens = [];
  bool _carregando = false;
  bool _carregandoMais = false;
  bool _temMais = false;
  int _offset = 0;
  int _totalEstimado = 0;
  String? _erro;

  DateTime? get _desde {
    final p = _presets.firstWhere((e) => e.id == _preset);
    if (p.dias == null) return null;
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).subtract(Duration(days: p.dias!));
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_recarregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_temMais || _carregandoMais || _carregando) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 120) {
      return;
    }
    unawaited(_carregarMais());
  }

  List<SessaoCaixaReferencia> get _itensVisiveis {
    return SessaoCaixaCatalogo.filtrarBusca(_itens, _buscaController.text);
  }

  Future<void> _recarregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
      _offset = 0;
      _itens = [];
      _temMais = false;
    });
    try {
      final pagina = await SessaoCaixaCatalogoLoader.carregarPagina(
        objectBox: widget.objectBox,
        lanApiClient: widget.lanApiClient,
        offset: 0,
        desde: _desde,
      );
      if (!mounted) return;
      setState(() {
        _itens = pagina.sessoes;
        _offset = pagina.proximoOffsetFechamentos;
        _temMais = pagina.temMais;
        _totalEstimado = pagina.totalEstimado;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  Future<void> _carregarMais() async {
    if (!_temMais) return;
    setState(() => _carregandoMais = true);
    try {
      final pagina = await SessaoCaixaCatalogoLoader.carregarPagina(
        objectBox: widget.objectBox,
        lanApiClient: widget.lanApiClient,
        offset: _offset,
        desde: _desde,
        incluirAbertas: false,
      );
      if (!mounted) return;
      setState(() {
        final novos = pagina.sessoes;
        final chaves = _itens.map((s) => s.chave).toSet();
        for (final s in novos) {
          if (chaves.add(s.chave)) _itens.add(s);
        }
        _offset = pagina.proximoOffsetFechamentos;
        _temMais = pagina.temMais;
        _totalEstimado = pagina.totalEstimado;
        _carregandoMais = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoMais = false);
    }
  }

  void _agendarBuscaLocal() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  String _rotulo(SessaoCaixaReferencia s) {
    final ab = _fmtDataHora.format(s.aberturaEm.toLocal());
    final op = s.operador.isEmpty ? 'Sem operador' : s.operador;
    final st = s.aberta ? 'aberta' : 'fechada';
    return '$ab · $op ($st)';
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _itensVisiveis;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Sessao do caixa'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _buscaController,
              decoration: const InputDecoration(
                hintText: 'Buscar operador, data ou numero...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => _agendarBuscaLocal(),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(p.label),
                        selected: _preset == p.id,
                        onSelected: (_) {
                          if (_preset == p.id) return;
                          setState(() => _preset = p.id);
                          unawaited(_recarregar());
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _carregando
                  ? 'Carregando...'
                  : '${visiveis.length} exibida(s)'
                      '${_totalEstimado > 0 ? ' · ~$_totalEstimado no periodo' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro != null
                      ? Center(child: Text(_erro!, textAlign: TextAlign.center))
                      : visiveis.isEmpty
                          ? const Center(
                              child: Text('Nenhuma sessao neste periodo.'),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount:
                                  visiveis.length + (_carregandoMais ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= visiveis.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  );
                                }
                                final s = visiveis[i];
                                final sel =
                                    widget.selecionadaAtual?.chave == s.chave;
                                return ListTile(
                                  dense: true,
                                  selected: sel,
                                  title: Text(_rotulo(s)),
                                  subtitle: s.aberta
                                      ? null
                                      : s.fechamentoEm == null
                                          ? null
                                          : Text(
                                              'Fech. ${_fmtDataHora.format(s.fechamentoEm!.toLocal())}',
                                            ),
                                  trailing: s.aberta
                                      ? Chip(
                                          label: const Text('Aberta'),
                                          visualDensity: VisualDensity.compact,
                                        )
                                      : null,
                                  onTap: () => Navigator.pop(context, s),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Limpar filtro'),
        ),
      ],
    );
  }
}
