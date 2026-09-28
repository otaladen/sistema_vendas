import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entregas/cargas_entrega.dart';
import 'agenda_carreto_pdv_dialog.dart';

/// Resultado do modal: [cargas] vazio = voltar a uma carga so.
class DividirCargasResultado {
  const DividirCargasResultado(this.cargas);

  final List<CargaEntrega> cargas;
}

/// Modal do PDV: distribui o carreto em varias viagens (datas diferentes).
///
/// A carga 1 recebe sempre o saldo (total - demais cargas).
Future<DividirCargasResultado?> mostrarDividirCargasPdvDialog({
  required BuildContext context,
  required dynamic vendaRepository,
  required List<ProdutoCarretoTotal> produtos,
  List<CargaEntrega> cargasIniciais = const [],
  DateTime? dataPrimeiraCarga,
  String janelaPrimeiraCarga = 'nao_definida',
}) {
  return showDialog<DividirCargasResultado>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DividirCargasPdvDialog(
      vendaRepository: vendaRepository,
      produtos: produtos,
      cargasIniciais: cargasIniciais,
      dataPrimeiraCarga: dataPrimeiraCarga,
      janelaPrimeiraCarga: janelaPrimeiraCarga,
    ),
  );
}

class _CargaEdicao {
  _CargaEdicao({
    required this.data,
    required this.janela,
    required List<ProdutoCarretoTotal> produtos,
    CargaEntrega? origem,
  }) : controllers = {
          for (final p in produtos)
            p.produtoId: TextEditingController(
              text: _formatar(origem?.quantidadeDoProduto(p.produtoId) ?? 0),
            ),
        };

  DateTime? data;
  String janela;
  final Map<int, TextEditingController> controllers;

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  static String _formatar(double q) {
    if (q <= 0) return '';
    if (q == q.roundToDouble()) return '${q.toInt()}';
    return q
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceAll('.', ',');
  }
}

class _DividirCargasPdvDialog extends StatefulWidget {
  const _DividirCargasPdvDialog({
    required this.vendaRepository,
    required this.produtos,
    required this.cargasIniciais,
    required this.dataPrimeiraCarga,
    required this.janelaPrimeiraCarga,
  });

  final dynamic vendaRepository;
  final List<ProdutoCarretoTotal> produtos;
  final List<CargaEntrega> cargasIniciais;
  final DateTime? dataPrimeiraCarga;
  final String janelaPrimeiraCarga;

  @override
  State<_DividirCargasPdvDialog> createState() =>
      _DividirCargasPdvDialogState();
}

class _DividirCargasPdvDialogState extends State<_DividirCargasPdvDialog> {
  static const double _larguraProduto = 230;
  static const double _larguraTotal = 90;
  static const double _larguraCarga = 170;

  late DateTime? _dataPrimeira;
  late String _janelaPrimeira;

  /// Cargas 2..N (a 1 e calculada).
  final List<_CargaEdicao> _demais = [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    final iniciais = widget.cargasIniciais;
    if (iniciais.length >= 2) {
      _dataPrimeira = iniciais.first.data ?? widget.dataPrimeiraCarga;
      _janelaPrimeira = iniciais.first.janela;
      for (final c in iniciais.skip(1)) {
        _demais.add(
          _CargaEdicao(
            data: c.data,
            janela: c.janela,
            produtos: widget.produtos,
            origem: c,
          ),
        );
      }
    } else {
      _dataPrimeira = widget.dataPrimeiraCarga;
      _janelaPrimeira = widget.janelaPrimeiraCarga;
      _demais.add(
        _CargaEdicao(
          data: null,
          janela: 'nao_definida',
          produtos: widget.produtos,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _demais) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _parse(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return 0;
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  double _quantidadeDigitada(_CargaEdicao carga, int produtoId) {
    final v = _parse(carga.controllers[produtoId]?.text ?? '');
    return v ?? 0;
  }

  double _saldoPrimeira(ProdutoCarretoTotal p) {
    var outras = 0.0;
    for (final c in _demais) {
      outras += _quantidadeDigitada(c, p.produtoId);
    }
    return CargasEntregaHelper.arredondar(p.quantidade - outras);
  }

  String _texto(double q, {bool zeroComoTraco = false}) {
    if (zeroComoTraco && q.abs() < CargasEntregaHelper.tolerancia) return '—';
    return _CargaEdicao._formatar(q.abs()).isEmpty
        ? '0'
        : '${q < 0 ? '-' : ''}${_CargaEdicao._formatar(q.abs())}';
  }

  Future<void> _escolherData({required int indiceDemais}) async {
    final agora = DateTime.now();
    final atual = indiceDemais < 0
        ? _dataPrimeira
        : _demais[indiceDemais].data;
    final minimo = indiceDemais < 0
        ? DateTime(agora.year, agora.month, agora.day)
        : (indiceDemais == 0 ? _dataPrimeira : _demais[indiceDemais - 1].data) ??
            DateTime(agora.year, agora.month, agora.day);
    final escolhido = await mostrarAgendaCarretoPdvDialog(
      context: context,
      vendaRepository: widget.vendaRepository,
      dataInicial: atual ?? minimo,
      firstDate: minimo,
      lastDate: DateTime(agora.year + 3, 12, 31),
    );
    if (!mounted || escolhido == null) return;
    setState(() {
      _erro = null;
      if (indiceDemais < 0) {
        _dataPrimeira = escolhido;
      } else {
        _demais[indiceDemais].data = escolhido;
      }
    });
  }

  void _adicionarCarga() {
    if (_demais.length + 1 >= CargasEntregaHelper.maximoCargas) return;
    setState(() {
      _erro = null;
      _demais.add(
        _CargaEdicao(
          data: null,
          janela: 'nao_definida',
          produtos: widget.produtos,
        ),
      );
    });
  }

  void _removerCarga(int indice) {
    setState(() {
      _erro = null;
      _demais.removeAt(indice).dispose();
    });
  }

  /// Passa todo o saldo da carga 1 deste produto para a carga indicada.
  void _moverSaldo(int indice, ProdutoCarretoTotal p) {
    final saldo = _saldoPrimeira(p);
    if (saldo <= 0) return;
    final carga = _demais[indice];
    final atual = _quantidadeDigitada(carga, p.produtoId);
    setState(() {
      _erro = null;
      carga.controllers[p.produtoId]!.text = _CargaEdicao._formatar(
        CargasEntregaHelper.arredondar(atual + saldo),
      );
    });
  }

  List<CargaEntrega>? _montarCargas() {
    final demais = <CargaEntrega>[];
    for (var i = 0; i < _demais.length; i++) {
      final c = _demais[i];
      final linhas = <LinhaCargaEntrega>[];
      for (final p in widget.produtos) {
        final raw = c.controllers[p.produtoId]?.text ?? '';
        final q = _parse(raw);
        if (q == null || q < 0) {
          setState(
            () => _erro =
                'Quantidade invalida em "${p.nomeProduto}" (carga ${i + 2}).',
          );
          return null;
        }
        if (!p.fracionado && q != q.roundToDouble()) {
          setState(
            () => _erro =
                '"${p.nomeProduto}" so aceita quantidade inteira.',
          );
          return null;
        }
        if (q > 0) {
          linhas.add(
            LinhaCargaEntrega(
              produtoId: p.produtoId,
              nomeProduto: p.nomeProduto,
              quantidade: CargasEntregaHelper.arredondar(q),
            ),
          );
        }
      }
      demais.add(
        CargaEntrega(
          numero: i + 2,
          data: c.data,
          janela: c.janela,
          linhas: linhas,
        ),
      );
    }
    for (final p in widget.produtos) {
      if (_saldoPrimeira(p) < -CargasEntregaHelper.tolerancia) {
        setState(
          () => _erro =
              '"${p.nomeProduto}": as cargas somam mais que o vendido '
              '(${_texto(p.quantidade)}).',
        );
        return null;
      }
    }
    final primeira = CargaEntrega(
      numero: 1,
      data: _dataPrimeira,
      janela: _janelaPrimeira,
    );
    return CargasEntregaHelper.recalcularPrimeiraCarga(
      widget.produtos,
      [primeira, ...demais],
    );
  }

  void _confirmar() {
    final cargas = _montarCargas();
    if (cargas == null) return;
    final erro = CargasEntregaHelper.validarPlano(cargas, widget.produtos);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(context, DividirCargasResultado(cargas));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final podeAdicionar = _demais.length + 1 < CargasEntregaHelper.maximoCargas;
    final larguraTabela = _larguraProduto +
        _larguraTotal +
        _larguraCarga * (_demais.length + 1);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SizedBox(
        width: screen.width < 1000 ? screen.width : 1000,
        height: screen.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dividir entrega em cargas',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Use quando nao cabe tudo em um carreto. Informe o que vai nas '
                'cargas 2 em diante; a carga 1 leva o restante. O frete continua '
                'unico para a venda.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: larguraTabela,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCabecalho(theme),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            itemCount: widget.produtos.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) =>
                                _buildLinhaProduto(theme, widget.produtos[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  _erro!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  if (widget.cargasIniciais.length >= 2)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        const DividirCargasResultado([]),
                      ),
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Voltar para uma carga'),
                    ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: podeAdicionar ? _adicionarCarga : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar carga'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _confirmar,
                    icon: const Icon(Icons.check),
                    label: Text('Confirmar ${_demais.length + 1} cargas'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCabecalho(ThemeData theme) {
    final titulo = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: _larguraProduto,
            child: Text('Produto', style: titulo),
          ),
          SizedBox(
            width: _larguraTotal,
            child: Text('Vendido', style: titulo, textAlign: TextAlign.end),
          ),
          _buildCabecalhoCarga(
            theme,
            numero: 1,
            data: _dataPrimeira,
            janela: _janelaPrimeira,
            onData: () => unawaited(_escolherData(indiceDemais: -1)),
            onJanela: (v) => setState(() => _janelaPrimeira = v),
          ),
          for (var i = 0; i < _demais.length; i++)
            _buildCabecalhoCarga(
              theme,
              numero: i + 2,
              data: _demais[i].data,
              janela: _demais[i].janela,
              onData: () => unawaited(_escolherData(indiceDemais: i)),
              onJanela: (v) => setState(() => _demais[i].janela = v),
              onRemover: _demais.length > 1 ? () => _removerCarga(i) : null,
            ),
        ],
      ),
    );
  }

  Widget _buildCabecalhoCarga(
    ThemeData theme, {
    required int numero,
    required DateTime? data,
    required String janela,
    required VoidCallback onData,
    required ValueChanged<String> onJanela,
    VoidCallback? onRemover,
  }) {
    return SizedBox(
      width: _larguraCarga,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    numero == 1 ? 'Carga 1 (restante)' : 'Carga $numero',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onRemover != null)
                  IconButton(
                    tooltip: 'Remover carga $numero',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemover,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
              ],
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: data == null ? theme.colorScheme.error : null,
              ),
              onPressed: onData,
              icon: const Icon(Icons.calendar_month_outlined, size: 16),
              label: Text(
                data == null
                    ? 'Definir data'
                    : DateFormat('dd/MM/yyyy').format(data),
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: janela,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'nao_definida',
                  child: Text('Periodo livre'),
                ),
                DropdownMenuItem(value: 'manha', child: Text('Manha')),
                DropdownMenuItem(value: 'tarde', child: Text('Tarde')),
              ],
              onChanged: (v) {
                if (v != null) onJanela(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaProduto(ThemeData theme, ProdutoCarretoTotal p) {
    final saldo = _saldoPrimeira(p);
    final negativo = saldo < -CargasEntregaHelper.tolerancia;
    final unidade = p.unidade.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _larguraProduto,
            child: Text(
              p.nomeProduto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _larguraTotal,
            child: Text(
              '${_texto(p.quantidade)}${unidade.isEmpty ? '' : ' $unidade'}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: _larguraCarga,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                _texto(saldo, zeroComoTraco: true),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: negativo ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ),
          for (var i = 0; i < _demais.length; i++)
            SizedBox(
              width: _larguraCarga,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextField(
                  controller: _demais[i].controllers[p.produtoId],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() => _erro = null),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Trazer o restante da carga 1',
                      visualDensity: VisualDensity.compact,
                      onPressed: saldo > 0 ? () => _moverSaldo(i, p) : null,
                      icon: const Icon(Icons.keyboard_double_arrow_right,
                          size: 18),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
