import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/auditoria_repository.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/auditoria_retencao.dart';
import '../../model/auditoria_evento.dart';
import '../../services/auditoria_registrar.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioLogSistemaPage extends StatefulWidget {
  const RelatorioLogSistemaPage({
    super.key,
    required this.auditoriaRepository,
    required this.appConfigRepository,
    required this.usuarioAdmin,
    this.usuarioLogin = '',
  });

  final AuditoriaRepository auditoriaRepository;
  final AppConfigRepository appConfigRepository;
  final bool usuarioAdmin;
  final String usuarioLogin;

  @override
  State<RelatorioLogSistemaPage> createState() =>
      _RelatorioLogSistemaPageState();
}

class _RelatorioLogSistemaPageState extends State<RelatorioLogSistemaPage> {
  final _buscaController = TextEditingController();
  final _fmtData = DateFormat('dd/MM/yyyy HH:mm');
  late DateTime _inicio;
  late DateTime _fim;
  String? _moduloFiltro;
  String? _usuarioFiltro;
  List<AuditoriaEvento> _eventos = [];
  List<String> _usuariosDistintos = [];
  bool _carregando = true;
  int _retencaoDias = AuditoriaRetencaoOpcoes.dias90;
  int _totalEventosBanco = 0;
  bool _salvandoRetencao = false;

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _fim = DateTime(hoje.year, hoje.month, hoje.day);
    _inicio = _fim.subtract(const Duration(days: 30));
    _buscaController.addListener(_recarregar);
    _carregar(incluirConfig: true);
  }

  @override
  void dispose() {
    _buscaController.removeListener(_recarregar);
    _buscaController.dispose();
    super.dispose();
  }

  void _recarregar() => setState(() {});

  Future<void> _carregar({bool incluirConfig = false}) async {
    setState(() => _carregando = true);
    if (incluirConfig && widget.usuarioAdmin) {
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      _retencaoDias =
          AuditoriaRetencaoOpcoes.normalizar(config.auditoriaRetencaoDias);
    }
    _usuariosDistintos = widget.auditoriaRepository.listarUsuariosDistintos();
    _totalEventosBanco = widget.auditoriaRepository.contarTotal();
    _eventos = widget.auditoriaRepository.listar(
      filtro: AuditoriaFiltro(
        inicio: _inicio,
        fim: _fim,
        modulo: _moduloFiltro,
        usuarioLogin: _usuarioFiltro,
        termoBusca: _buscaController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _carregando = false);
  }

  Future<void> _salvarPoliticaRetencao(int dias) async {
    if (_salvandoRetencao) return;
    setState(() => _salvandoRetencao = true);
    try {
      final atual = await widget.appConfigRepository.carregarEmpresaConfig();
      final normalizado = AuditoriaRetencaoOpcoes.normalizar(dias);
      await widget.appConfigRepository.salvarEmpresaConfig(
        atual.copyWith(auditoriaRetencaoDias: normalizado),
      );
      if (!mounted) return;
      setState(() => _retencaoDias = normalizado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Retencao do log: ${AuditoriaRetencaoOpcoes.rotulo(normalizado)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvandoRetencao = false);
    }
  }

  Future<void> _aplicarRetencaoAgora() async {
    final dias = _retencaoDias;
    if (dias <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Retencao automatica desativada. Escolha 90 ou 180 dias ou use a limpeza manual.',
          ),
        ),
      );
      return;
    }
    final removidos = widget.auditoriaRepository
        .purgarAnterioresARetencaoDias(dias);
    if (removidos > 0) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.sistema,
        acao: AuditoriaAcao.retencaoAutomatica,
        usuarioLogin: widget.usuarioLogin,
        resumo:
            'Retencao manual: $removidos evento(s) removidos (politica $dias dias)',
        detalhes: {'diasRetencao': dias, 'removidos': removidos},
      );
    }
    await _carregar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removidos == 0
              ? 'Nenhum evento fora da politica de $dias dias.'
              : '$removidos evento(s) removidos pela retencao.',
        ),
      ),
    );
  }

  int _contarEventosAte(DateTime ate) =>
      widget.auditoriaRepository.contarAteFimDoDia(ate);

  Future<void> _abrirManutencaoLimpeza() async {
    var dataLimite = DateTime.now().subtract(const Duration(days: 365));
    final dataController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(dataLimite),
    );

    final confirmarData = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final qtd = _contarEventosAte(dataLimite);
          return AlertDialog(
            title: const Text('Manutencao do log'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Apagar eventos do log com data ate o dia selecionado '
                    '(inclusive). Esta acao nao pode ser desfeita.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dataController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Apagar ate a data',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: () async {
                      final escolhida = await showDatePicker(
                        context: ctx,
                        initialDate: dataLimite,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (escolhida == null) return;
                      setDialogState(() {
                        dataLimite = escolhida;
                        dataController.text =
                            DateFormat('dd/MM/yyyy').format(escolhida);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    qtd == 0
                        ? 'Nenhum evento ate esta data.'
                        : '$qtd evento(s) serao apagados.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: qtd == 0
                              ? Theme.of(ctx).colorScheme.onSurfaceVariant
                              : Theme.of(ctx).colorScheme.error,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: qtd == 0 ? null : () => Navigator.pop(ctx, true),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );
    dataController.dispose();
    if (confirmarData != true || !mounted) return;

    final qtd = _contarEventosAte(dataLimite);
    final dataFmt = DateFormat('dd/MM/yyyy').format(dataLimite);
    final confirmarApagar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar limpeza'),
        content: Text(
          'Apagar $qtd evento(s) do log ate $dataFmt?\n\n'
          'Esta acao nao pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmarApagar != true || !mounted) return;

    try {
      final apagados =
          widget.auditoriaRepository.excluirAteFimDoDia(dataLimite);
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.sistema,
        acao: AuditoriaAcao.limparManual,
        usuarioLogin: widget.usuarioLogin,
        resumo: '$apagados evento(s) do log apagados ate $dataFmt',
        detalhes: {'ateData': dataFmt, 'quantidade': apagados},
      );
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$apagados evento(s) apagado(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na manutencao: $e')),
      );
    }
  }

  Widget _buildPainelRetencaoAdmin() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Retencao e manutencao (administrador)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '$_totalEventosBanco evento(s) gravados no banco. '
              'A limpeza automatica roda ao abrir o app conforme a politica abaixo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Politica de retencao automatica',
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _retencaoDias,
                  items: AuditoriaRetencaoOpcoes.valoresPermitidos
                      .map(
                        (d) => DropdownMenuItem<int>(
                          value: d,
                          child: Text(AuditoriaRetencaoOpcoes.rotulo(d)),
                        ),
                      )
                      .toList(),
                  onChanged: _salvandoRetencao
                      ? null
                      : (v) {
                          if (v == null) return;
                          _salvarPoliticaRetencao(v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _salvandoRetencao ? null : _aplicarRetencaoAgora,
                  icon: const Icon(Icons.auto_delete_outlined, size: 18),
                  label: const Text('Aplicar retencao agora'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _abrirManutencaoLimpeza,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Apagar ate data...'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _escolherPeriodo() async {
    final inicio = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Data inicial',
    );
    if (inicio == null || !mounted) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: _fim.isBefore(inicio) ? inicio : _fim,
      firstDate: inicio,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Data final',
    );
    if (fim == null || !mounted) return;
    setState(() {
      _inicio = DateTime(inicio.year, inicio.month, inicio.day);
      _fim = DateTime(fim.year, fim.month, fim.day);
    });
    await _carregar();
  }

  List<List<String>> _linhasCsv() => [
        [
          'Data',
          'Usuario',
          'Modulo',
          'Acao',
          'Entidade',
          'ID',
          'Resumo',
        ],
        ..._eventos.map((e) {
          return [
            _fmtData.format(e.dataHora.toLocal()),
            e.usuarioLogin,
            auditoriaRotuloModulo(e.modulo),
            auditoriaRotuloAcao(e.acao),
            e.entidade,
            e.entidadeId,
            e.resumo,
          ];
        }),
      ];

  List<String> _paginasPdf() {
    final periodo =
        '${DateFormat('dd/MM/yyyy').format(_inicio)} a ${DateFormat('dd/MM/yyyy').format(_fim)}';
    return relatorioMontarPaginasTabela(
      titulo: 'LOG DO SISTEMA',
      subtitulo: '$periodo · ${_eventos.length} evento(s)',
      cabecalho: ['Data', 'Usuario', 'Modulo', 'Acao', 'Resumo'],
      linhas: _eventos
          .map(
            (e) => [
              _fmtData.format(e.dataHora.toLocal()),
              e.usuarioLogin.isEmpty ? '-' : e.usuarioLogin,
              auditoriaRotuloModulo(e.modulo),
              auditoriaRotuloAcao(e.acao),
              e.resumo,
            ],
          )
          .toList(),
    );
  }

  Future<void> _detalhe(AuditoriaEvento e) async {
    final det = widget.auditoriaRepository.detalhesMap(e);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(auditoriaRotuloAcao(e.acao)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Data: ${_fmtData.format(e.dataHora.toLocal())}'),
                Text('Usuario: ${e.usuarioLogin.isEmpty ? '(nao informado)' : e.usuarioLogin}'),
                Text('Modulo: ${auditoriaRotuloModulo(e.modulo)}'),
                if (e.entidade.isNotEmpty)
                  Text('Entidade: ${e.entidade}'),
                if (e.entidadeId.isNotEmpty)
                  Text('ID: ${e.entidadeId}'),
                const SizedBox(height: 8),
                Text(e.resumo),
                if (det != null && det.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Detalhes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...det.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${entry.key}: ${entry.value}'),
                    ),
                  ),
                ],
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final periodoFmt =
        '${DateFormat('dd/MM/yyyy').format(_inicio)} — ${DateFormat('dd/MM/yyyy').format(_fim)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log do sistema'),
        actions: [
          if (widget.usuarioAdmin)
            IconButton(
              tooltip: 'Manutencao do log',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _abrirManutencaoLimpeza,
            ),
          RelatorioExportacoesMenu(
            nomeArquivo: 'log_sistema',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
            mensagemSeVazio: 'Nenhum evento para exportar.',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Registro central de acoes criticas (login, orcamentos, backup, caixa).',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                if (widget.usuarioAdmin) ...[
                  _buildPainelRetencaoAdmin(),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _escolherPeriodo,
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(periodoFmt),
                    ),
                    DropdownButton<String?>(
                      value: _moduloFiltro,
                      hint: const Text('Modulo'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos os modulos'),
                        ),
                        ...AuditoriaModulo.todos.map(
                          (m) => DropdownMenuItem<String?>(
                            value: m,
                            child: Text(auditoriaRotuloModulo(m)),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _moduloFiltro = v);
                        _carregar();
                      },
                    ),
                    DropdownButton<String?>(
                      value: _usuarioFiltro,
                      hint: const Text('Usuario'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos os usuarios'),
                        ),
                        ..._usuariosDistintos.map(
                          (u) => DropdownMenuItem<String?>(
                            value: u,
                            child: Text(u),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _usuarioFiltro = v);
                        _carregar();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _buscaController,
                  decoration: InputDecoration(
                    labelText: 'Buscar no log',
                    hintText: 'Resumo, motivo, caminho...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscaController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _buscaController.clear(),
                          ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_eventos.length} evento(s) no periodo',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (_eventos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text('Nenhum evento encontrado com os filtros atuais.'),
                    ),
                  )
                else
                  ..._eventos.map((e) {
                    final det = widget.auditoriaRepository.detalhesMap(e);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(
                            _iconeModulo(e.modulo),
                            size: 20,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          e.resumo.isEmpty
                              ? auditoriaRotuloAcao(e.acao)
                              : e.resumo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_fmtData.format(e.dataHora.toLocal())}'
                          '${e.usuarioLogin.isEmpty ? '' : ' · ${e.usuarioLogin}'}'
                          '\n${auditoriaRotuloModulo(e.modulo)} · ${auditoriaRotuloAcao(e.acao)}',
                        ),
                        isThreeLine: true,
                        trailing: det != null && det.isNotEmpty
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: () => _detalhe(e),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  IconData _iconeModulo(String modulo) {
    switch (modulo) {
      case AuditoriaModulo.autenticacao:
        return Icons.login_outlined;
      case AuditoriaModulo.orcamento:
        return Icons.description_outlined;
      case AuditoriaModulo.venda:
        return Icons.receipt_long_outlined;
      case AuditoriaModulo.backup:
        return Icons.backup_outlined;
      case AuditoriaModulo.caixa:
        return Icons.point_of_sale_outlined;
      default:
        return Icons.history_outlined;
    }
  }
}
