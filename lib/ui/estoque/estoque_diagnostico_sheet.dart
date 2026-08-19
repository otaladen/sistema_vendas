import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/estoque/estoque_diagnostico_models.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../services/estoque_diagnostico_service.dart';

final DateFormat _dataHoraDiagnostico = DateFormat('dd/MM/yyyy HH:mm');

Future<void> mostrarEstoqueDiagnosticoSheet({
  required BuildContext context,
  EstoqueDiagnosticoService? diagnosticoService,
  dynamic vendaRepository,
  required UsuarioSistema usuarioLogado,
  required bool permitirVendaSemEstoque,
  EstoqueDiagnosticoResultado? resultadoInicial,
  VoidCallback? aoAtualizarExterno,
  Future<EstoqueDiagnosticoResultado?> Function()? buscarRemoto,
  Future<void> Function(int vendaId)? reprocessarBaixaRemoto,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _EstoqueDiagnosticoSheetBody(
        diagnosticoService: diagnosticoService,
        vendaRepository: vendaRepository,
        usuarioLogado: usuarioLogado,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
        resultadoInicial: resultadoInicial,
        aoAtualizarExterno: aoAtualizarExterno,
        buscarRemoto: buscarRemoto,
        reprocessarBaixaRemoto: reprocessarBaixaRemoto,
      );
    },
  );
}

class _EstoqueDiagnosticoSheetBody extends StatefulWidget {
  const _EstoqueDiagnosticoSheetBody({
    this.diagnosticoService,
    this.vendaRepository,
    required this.usuarioLogado,
    required this.permitirVendaSemEstoque,
    this.resultadoInicial,
    this.aoAtualizarExterno,
    this.buscarRemoto,
    this.reprocessarBaixaRemoto,
  });

  final EstoqueDiagnosticoService? diagnosticoService;
  final dynamic vendaRepository;
  final UsuarioSistema usuarioLogado;
  final bool permitirVendaSemEstoque;
  final EstoqueDiagnosticoResultado? resultadoInicial;
  final VoidCallback? aoAtualizarExterno;
  final Future<EstoqueDiagnosticoResultado?> Function()? buscarRemoto;
  final Future<void> Function(int vendaId)? reprocessarBaixaRemoto;

  @override
  State<_EstoqueDiagnosticoSheetBody> createState() =>
      _EstoqueDiagnosticoSheetBodyState();
}

class _EstoqueDiagnosticoSheetBodyState
    extends State<_EstoqueDiagnosticoSheetBody> {
  late EstoqueDiagnosticoResultado _resultado;
  int? _reprocessandoVendaId;
  bool _atualizando = false;

  bool get _podeReprocessar =>
      UsuarioPermissaoHelper.tem(
        widget.usuarioLogado,
        PermissaoUsuario.manutencaoAuditoriaCaixa,
      );

  @override
  void initState() {
    super.initState();
    _resultado = widget.resultadoInicial ??
        widget.diagnosticoService?.executar() ??
        EstoqueDiagnosticoResultado(achados: const [], geradoEm: DateTime.now());
  }

  Future<void> _atualizar() async {
    setState(() => _atualizando = true);
    await Future<void>.delayed(Duration.zero);
    EstoqueDiagnosticoResultado? novo;
    if (widget.buscarRemoto != null) {
      try {
        novo = await widget.buscarRemoto!();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Diagnostico: $e')),
          );
        }
      }
    } else {
      novo = widget.diagnosticoService?.executar();
    }
    if (!mounted) return;
    setState(() {
      if (novo != null) _resultado = novo;
      _atualizando = false;
    });
    widget.aoAtualizarExterno?.call();
  }

  Future<void> _reprocessarBaixa(int vendaId) async {
    final temLocal = widget.vendaRepository != null;
    final temRemoto = widget.reprocessarBaixaRemoto != null;
    if (!temLocal && !temRemoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reprocessar baixa indisponivel sem conexao com o PC servidor.'),
        ),
      );
      return;
    }
    if (!_podeReprocessar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem permissao para reprocessar baixa de estoque.',
          ),
        ),
      );
      return;
    }
    setState(() => _reprocessandoVendaId = vendaId);
    try {
      if (temRemoto) {
        await widget.reprocessarBaixaRemoto!(vendaId);
      } else {
        widget.vendaRepository.reprocessarBaixaEstoqueDocumentoVenda(
          vendaId,
          permitirVendaSemEstoque: widget.permitirVendaSemEstoque,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Baixa reprocessada para venda #$vendaId.')),
      );
      await _atualizar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao reprocessar baixa: $e')),
      );
    } finally {
      if (mounted) setState(() => _reprocessandoVendaId = null);
    }
  }

  Color _corSeveridade(
    BuildContext context,
    EstoqueDiagnosticoSeveridade severidade,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (severidade) {
      case EstoqueDiagnosticoSeveridade.critico:
        return scheme.error;
      case EstoqueDiagnosticoSeveridade.alerta:
        return Colors.orange.shade800;
      case EstoqueDiagnosticoSeveridade.info:
        return scheme.primary;
    }
  }

  IconData _iconeSeveridade(EstoqueDiagnosticoSeveridade severidade) {
    switch (severidade) {
      case EstoqueDiagnosticoSeveridade.critico:
        return Icons.error_outline;
      case EstoqueDiagnosticoSeveridade.alerta:
        return Icons.warning_amber_outlined;
      case EstoqueDiagnosticoSeveridade.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    final gerado = _resultado.geradoEm.toLocal();
    final achados = _resultado.achados;

    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Diagnostico de estoque',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _atualizando ? null : _atualizar,
                    icon: _atualizando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Gerado em ${_dataHoraDiagnostico.format(gerado)} · '
                '${_resultado.quantidadeCriticos} critico(s) · '
                '${_resultado.quantidadeAlertas} alerta(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: achados.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma inconsistencia detectada. '
                          'Estoque operacional OK.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: achados.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final a = achados[index];
                        final cor = _corSeveridade(context, a.severidade);
                        final reprocessando =
                            a.vendaId != null &&
                            _reprocessandoVendaId == a.vendaId;
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: cor.withValues(alpha: 0.35)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _iconeSeveridade(a.severidade),
                                      color: cor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        a.titulo,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  a.detalhe,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (a.podeReprocessarBaixa &&
                                    a.vendaId != null &&
                                    _podeReprocessar) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: reprocessando
                                          ? null
                                          : () => _reprocessarBaixa(a.vendaId!),
                                      icon: reprocessando
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.replay_outlined),
                                      label: const Text('Reprocessar baixa'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
