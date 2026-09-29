import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/app_config_repository.dart';
import '../../services/configuracoes_service.dart';
import '../../data/backup_agendado_headless_service.dart';
import '../../data/auto_backup_service.dart';
import '../../data/backup_historico_service.dart';
import '../../data/backup_pos_execucao_service.dart';
import '../../data/backup_tarefa_windows_service.dart';
import '../../data/backup_zip_service.dart';
import '../../data/local_app_data_paths.dart';
import '../../data/local_backup_copy.dart';
import '../../data/local_backup_restore.dart';
import '../../data/local_backup_service.dart';
import '../../data/local_backup_validation.dart';
import '../../data/objectbox.dart';
import '../../data/produto_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../services/windows_backup_ao_fechar_window_service.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/backup_historico_item.dart';
import '../../domain/backup_pasta_risco.dart';
import '../../services/windows_shell_paths.dart';
import '../../domain/backup_retencao.dart';
import '../../domain/backup_status_helper.dart';
import '../../services/auditoria_registrar.dart';
import '../produtos/importar_chacal_backup_flow.dart';
import '../produtos/zerar_cadastro_produtos_flow.dart';

class BackupConfiguracaoSection extends StatefulWidget {
  const BackupConfiguracaoSection({
    super.key,
    required this.configuracoesService,
    required this.objectBox,
    required this.produtoRepository,
    this.lanSyncScheduler,
    required this.nomeLoja,
  });

  final ConfiguracoesService configuracoesService;
  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final LanSyncScheduler? lanSyncScheduler;
  final String nomeLoja;

  @override
  State<BackupConfiguracaoSection> createState() =>
      _BackupConfiguracaoSectionState();
}

class _ProgressoBackupUi {
  const _ProgressoBackupUi({this.valor = 0, this.etapa = ''});

  final double valor;
  final String etapa;

  int get percentual => (valor * 100).round().clamp(0, 100);
}

class _BackupConfiguracaoSectionState extends State<BackupConfiguracaoSection> {
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _backupEmAndamento = false;
  bool _restauracaoEmAndamento = false;
  double _progresso = 0;
  String _etapaProgresso = '';
  final ValueNotifier<_ProgressoBackupUi> _progressoUi =
      ValueNotifier(const _ProgressoBackupUi());
  bool _dialogoProgressoAberto = false;
  BuildContext? _ctxDialogoProgresso;

  BackupRegistroManual _manual = const BackupRegistroManual();
  BackupStatusResumo? _status;
  BackupFalhaRegistro _falha = const BackupFalhaRegistro();
  List<BackupHistoricoItem> _historico = [];
  bool _carregandoHistorico = false;
  String _tamanhoBancoLocal = '—';
  String _pastaDadosLocal = '';

  bool _backupAutomaticoAtivo = false;
  bool _backupAoFecharAtivo = false;
  String _backupAutomaticoPasta = '';
  int _backupAutomaticoIntervaloMinutos = 1440;
  int _backupRetencaoMaxCopias = 15;
  int _backupRetencaoCompletos = BackupRetencaoCompletosOpcoes.copias4;
  int _ultimoBackupAutomaticoMs = 0;
  LocalBackupEscopo _backupAutomaticoEscopo = LocalBackupEscopo.somenteBanco;
  LocalBackupEscopo _escopoBackupParcial = LocalBackupEscopo.somenteBanco;

  bool _backupSegundoDestinoAtivo = false;
  String _backupSegundoDestinoPasta = '';
  bool _redeModoServidor = false;
  String _tarefaWindowsHorario = '22:00';
  bool _tarefaWindowsInstalada = false;

  @override
  void initState() {
    super.initState();
    unawaited(_recarregar());
  }

  @override
  void dispose() {
    _progressoUi.dispose();
    super.dispose();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    try {
      final config = await widget.configuracoesService.carregarEfetiva();
      final manual =
          await widget.configuracoesService.repository.carregarRegistroBackupManual();
      var falha =
          await widget.configuracoesService.repository.carregarFalhaBackupAutomatico();
      final aoFechar =
          await widget.configuracoesService.repository.carregarBackupAoFecharAtivo();
      final escopoAuto =
          await widget.configuracoesService.repository.carregarBackupAutomaticoEscopo();
      final horarioTarefa =
          await widget.configuracoesService.repository.carregarHorarioTarefaBackupWindows();
      var tarefaInstalada = false;
      if (Platform.isWindows) {
        tarefaInstalada = await BackupTarefaWindowsService.tarefaInstalada();
      }
      final baseDir = await obterDiretorioBaseDadosApp();
      final resumoDados = await medirTamanhoDadosLocais(baseDir);
      final tamanho = _formatarResumoDadosLocais(resumoDados);
      // Estado inconsistente: automatico ligado sem pasta → desliga e persiste.
      var configEfetiva = config;
      final pastaAuto = config.backupAutomaticoPasta.trim();
      if (config.backupAutomaticoAtivo && pastaAuto.isEmpty) {
        configEfetiva = config.copyWith(backupAutomaticoAtivo: false);
        await widget.configuracoesService.salvarEfetiva(configEfetiva);
        await widget.configuracoesService.repository.registrarFalhaBackupAutomatico(
          'Backup automático desativado: pasta de destino não configurada.',
        );
        falha =
            await widget.configuracoesService.repository.carregarFalhaBackupAutomatico();
      }

      if (!mounted) return;
      setState(() {
        _manual = manual;
        _falha = falha;
        _backupAoFecharAtivo = aoFechar;
        _backupAutomaticoEscopo = escopoAuto;
        _backupAutomaticoAtivo = configEfetiva.backupAutomaticoAtivo;
        _backupAutomaticoPasta = configEfetiva.backupAutomaticoPasta;
        _backupRetencaoMaxCopias = configEfetiva.backupRetencaoMaxCopias;
        _backupRetencaoCompletos = configEfetiva.backupRetencaoCompletos;
        _backupSegundoDestinoAtivo = configEfetiva.backupSegundoDestinoAtivo;
        _backupSegundoDestinoPasta = configEfetiva.backupSegundoDestinoPasta;
        _redeModoServidor = configEfetiva.redeModoServidor;
        _tarefaWindowsHorario =
            BackupTarefaWindowsService.normalizarHorario(horarioTarefa);
        _tarefaWindowsInstalada = tarefaInstalada;
        _backupAutomaticoIntervaloMinutos = () {
          const opcoes = [60, 360, 720, 1440];
          final raw =
              configEfetiva.backupAutomaticoIntervaloMinutos.clamp(15, 10080);
          return opcoes.contains(raw) ? raw : 1440;
        }();
        _ultimoBackupAutomaticoMs = configEfetiva.ultimoBackupAutomaticoMs;
        _tamanhoBancoLocal = tamanho;
        _pastaDadosLocal = baseDir.path;
        _status = BackupStatusHelper.avaliar(
          config: configEfetiva,
          manual: manual,
        );
        _carregando = false;
      });
      await _carregarHistorico();
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _persistirPreferenciasBackupAutomatico() async {
    final atual = await widget.configuracoesService.carregarEfetiva();
    await widget.configuracoesService.salvarEfetiva(
      atual.copyWith(
        backupAutomaticoAtivo: _backupAutomaticoAtivo,
        backupAutomaticoPasta: _backupAutomaticoPasta,
        backupAutomaticoIntervaloMinutos: _backupAutomaticoIntervaloMinutos
            .clamp(15, 10080),
        backupRetencaoMaxCopias: _backupRetencaoMaxCopias,
        backupRetencaoCompletos: _backupRetencaoCompletos,
        backupSegundoDestinoAtivo: _backupSegundoDestinoAtivo,
        backupSegundoDestinoPasta: _backupSegundoDestinoPasta,
      ),
    );
  }

  Set<String> _pastasParaHistorico() {
    final pastas = <String>{};
    final auto = _backupAutomaticoPasta.trim();
    if (auto.isNotEmpty) pastas.add(auto);
    final manualPadrao = _manual.pastaPadrao.trim();
    if (manualPadrao.isNotEmpty) pastas.add(manualPadrao);
    final segundo = _backupSegundoDestinoPasta.trim();
    if (segundo.isNotEmpty) pastas.add(segundo);
    final ultimo = _manual.ultimoPath.trim();
    if (ultimo.isNotEmpty) {
      pastas.add(p.dirname(ultimo));
    }
    return pastas;
  }

  Future<void> _carregarHistorico() async {
    if (!mounted) return;
    setState(() => _carregandoHistorico = true);
    try {
      final itens = await BackupHistoricoService.listar(
        pastasRaiz: _pastasParaHistorico(),
        limite: 40,
      );
      if (!mounted) return;
      setState(() {
        _historico = itens;
        _carregandoHistorico = false;
      });
      await _reconciliarUltimoBackupComHistorico();
    } catch (_) {
      if (mounted) setState(() => _carregandoHistorico = false);
    }
  }

  /// Se o historico em disco tem backup automatico mais recente que as prefs
  /// (ex.: timestamp gravado so numa chave antiga), alinha o status do painel.
  Future<void> _reconciliarUltimoBackupComHistorico() async {
    BackupHistoricoItem? melhorAuto;
    for (final item in _historico) {
      if (!item.valido) continue;
      if (item.tipo == LocalBackupTipo.manual) continue;
      melhorAuto = item;
      break;
    }
    if (melhorAuto == null) return;
    final ms = melhorAuto.criadoEm.millisecondsSinceEpoch;
    if (ms <= _ultimoBackupAutomaticoMs) return;

    await widget.configuracoesService.repository.atualizarUltimoBackupAutomaticoMs(ms);
    if (!mounted) return;
    final config = await widget.configuracoesService.carregarEfetiva();
    if (!mounted) return;
    setState(() {
      _ultimoBackupAutomaticoMs = config.ultimoBackupAutomaticoMs;
      _status = BackupStatusHelper.avaliar(
        config: config,
        manual: _manual,
      );
    });
  }

  Future<void> _posProcessarBackup({
    required Directory pastaRaiz,
    required Directory pastaBackup,
  }) async {
    await BackupPosExecucaoService.aposBackupSucesso(
      repository: widget.configuracoesService.repository,
      pastaRaizPrimaria: pastaRaiz,
      pastaBackup: pastaBackup,
    );
  }

  Future<void> _alternarSegundoDestino(bool value) async {
    if (value) {
      var pasta = _backupSegundoDestinoPasta.trim();
      if (pasta.isEmpty) {
        final escolhida = await _escolherPastaComAvisoRisco(
          dialogTitle:
              'Segundo destino (rede, nuvem ou pasta do servidor)',
        );
        if (escolhida == null || !mounted) return;
        pasta = escolhida;
      } else if (!await _confirmarPastaSeRisco(pasta)) {
        final outra = await _escolherPastaComAvisoRisco(
          dialogTitle: 'Escolha outro segundo destino',
        );
        if (outra == null || !mounted) return;
        pasta = outra;
      }
      if (!mounted) return;
      setState(() {
        _backupSegundoDestinoAtivo = true;
        _backupSegundoDestinoPasta = pasta;
      });
    } else {
      setState(() => _backupSegundoDestinoAtivo = false);
    }
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _escolherPastaSegundoDestino() async {
    final escolhida = await _escolherPastaComAvisoRisco(
      dialogTitle: 'Segundo destino do backup',
    );
    if (escolhida == null || !mounted) return;
    setState(() => _backupSegundoDestinoPasta = escolhida);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _exportarZipHistorico(BackupHistoricoItem item) async {
    if (_backupEmAndamento || !item.valido) return;
    final senhaController = TextEditingController();
    final confirmarSenhaController = TextEditingController();
    final exportar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Exportar ZIP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Backup de ${_dataHora.format(item.criadoEm)}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: senhaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha (opcional)',
                  hintText: 'Deixe vazio para ZIP sem criptografia',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmarSenhaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar senha',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exportar'),
            ),
          ],
        );
      },
    );
    final senha = senhaController.text;
    final confirma = confirmarSenhaController.text;
    senhaController.dispose();
    confirmarSenhaController.dispose();
    if (exportar != true || !mounted) return;
    if (senha.isNotEmpty && senha != confirma) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não conferem.')),
      );
      return;
    }

    setState(() {
      _backupEmAndamento = true;
      _progresso = 0;
      _etapaProgresso = 'Exportando ZIP…';
    });
    try {
      final resultado = await BackupZipService.exportarPasta(
        pastaBackup: item.pasta,
        senha: senha.isEmpty ? null : senha,
        onProgress: _atualizarProgresso,
      );
      BackupZipService.registrarExportacao(resultado);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('Arquivo criado: ${resultado.arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar ZIP: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _backupEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _importarBackupChacal() async {
    if (_backupEmAndamento || _restauracaoEmAndamento) return;
    await executarImportacaoChacalBackup(
      context: context,
      produtoRepository: widget.produtoRepository,
      onStatus: (msg, {erro = false}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: erro ? Theme.of(context).colorScheme.error : null,
          ),
        );
      },
    );
  }

  Future<void> _zerarCadastroProdutos() async {
    if (_backupEmAndamento || _restauracaoEmAndamento) return;
    final backupAntes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antes de zerar o cadastro'),
        content: const Text(
          'Zerar produtos apaga o catálogo atual. '
          'Recomendado criar um backup completo agora, antes de continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zerar sem backup'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Backup e continuar'),
          ),
        ],
      ),
    );
    if (backupAntes == null || !mounted) return;
    if (backupAntes) {
      final ok = await _criarBackupDados(escopo: LocalBackupEscopo.completo);
      if (!ok || !mounted) return;
    }
    await executarZerarCadastroProdutos(
      context: context,
      produtoRepository: widget.produtoRepository,
      onStatus: (msg, {erro = false}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: erro ? Theme.of(context).colorScheme.error : null,
          ),
        );
      },
    );
  }

  Future<void> _restaurarDeArquivoZip() async {
    if (_restauracaoEmAndamento || _backupEmAndamento) return;
    final pick = await FilePicker.platform.pickFiles(
      dialogTitle: 'Escolha o arquivo ZIP ou .zip.cript',
      type: FileType.custom,
      allowedExtensions: ['zip', 'cript'],
    );
    if (pick == null || pick.files.isEmpty || !mounted) return;
    final path = pick.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    String? senha;
    if (path.toLowerCase().endsWith('.cript')) {
      final controller = TextEditingController();
      senha = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Senha do backup'),
            content: TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      );
      controller.dispose();
      if (senha == null || !mounted) return;
    }

    setState(() {
      _restauracaoEmAndamento = true;
      _progresso = 0.1;
      _etapaProgresso = 'Extraindo ZIP… 10%';
    });
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('sv_restore_zip_');
      final extraido = await BackupZipService.extrairParaRestauracao(
        arquivo: File(path),
        pastaTemp: tempDir,
        senha: senha,
      );
      await _confirmarERestaurar(extraido);
    } on LocalBackupInvalidoException catch (e) {
      await _tratarErroRestauracao(e.message, invalido: true);
    } catch (e) {
      await _tratarErroRestauracao('Falha ao restaurar ZIP: $e');
    } finally {
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
      _fecharDialogoProgresso();
      if (mounted) {
        setState(() {
          _restauracaoEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _instalarTarefaWindows() async {
    if (!BackupTarefaWindowsService.suportado) return;
    if (_backupAutomaticoPasta.trim().isEmpty && _manual.pastaPadrao.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure a pasta de destino antes da tarefa agendada.'),
        ),
      );
      return;
    }
    try {
      await BackupTarefaWindowsService.instalar(
        horarioHhMm: _tarefaWindowsHorario,
        argumentosExe: BackupAgendadoHeadlessService.argBackupAgendado,
      );
      await widget.configuracoesService.repository.salvarHorarioTarefaBackupWindows(
        _tarefaWindowsHorario,
      );
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupTarefaWindows,
        resumo: 'Tarefa Windows instalada',
        detalhes: {'horario': _tarefaWindowsHorario},
      );
      if (!mounted) return;
      await _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tarefa diária instalada as $_tarefaWindowsHorario. '
            'Ela roda independente do timer do app; preferivel o sistema '
            'fechado nesse horário (banco pode estar em uso se o app estiver aberto).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao instalar tarefa: $e')),
      );
    }
  }

  Future<void> _removerTarefaWindows() async {
    if (!BackupTarefaWindowsService.suportado) return;
    try {
      await BackupTarefaWindowsService.remover();
      if (!mounted) return;
      await _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarefa agendada removida.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao remover tarefa: $e')),
      );
    }
  }

  Future<void> _definirHorarioTarefaWindows(String? horario) async {
    if (horario == null) return;
    setState(
      () => _tarefaWindowsHorario =
          BackupTarefaWindowsService.normalizarHorario(horario),
    );
    await widget.configuracoesService.repository.salvarHorarioTarefaBackupWindows(
      _tarefaWindowsHorario,
    );
  }

  Future<void> _definirRetencaoBackup(int? copias) async {
    if (copias == null) return;
    setState(() => _backupRetencaoMaxCopias = copias);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _definirRetencaoCompletos(int? copias) async {
    if (copias == null) return;
    setState(() => _backupRetencaoCompletos = copias);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  String _formatarResumoDadosLocais(ResumoTamanhoDadosLocais resumo) {
    if (resumo.totalBytes <= 0 && resumo.bancoBytes <= 0) return '—';
    final banco = LocalBackupValidation.formatarTamanhoBytes(resumo.bancoBytes);
    final fotos = LocalBackupValidation.formatarTamanhoBytes(resumo.fotosBytes);
    final total = LocalBackupValidation.formatarTamanhoBytes(resumo.totalBytes);
    final base = 'Banco $banco · Fotos $fotos · Total $total';
    if (resumo.cacheBytes >= 1024 * 1024) {
      final caches =
          LocalBackupValidation.formatarTamanhoBytes(resumo.cacheBytes);
      return '$base · Caches $caches fora do backup';
    }
    return base;
  }

  Future<void> _alternarBackupAoFechar(bool value) async {
    setState(() => _backupAoFecharAtivo = value);
    await widget.configuracoesService.repository.salvarBackupAoFecharAtivo(value);
    await WindowsBackupAoFecharWindowService.atualizarPreventClose();
  }

  void _atualizarProgresso(double v, String etapa) {
    if (!mounted) return;
    final clamped = v.clamp(0.0, 1.0);
    setState(() {
      _progresso = clamped;
      _etapaProgresso = etapa;
    });
    _progressoUi.value = _ProgressoBackupUi(valor: clamped, etapa: etapa);
  }

  Future<void> _abrirDialogoProgresso({required String titulo}) async {
    if (_dialogoProgressoAberto || !mounted) return;
    _dialogoProgressoAberto = true;
    final dialogoPronto = Completer<void>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          _ctxDialogoProgresso = ctx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!dialogoPronto.isCompleted) dialogoPronto.complete();
          });
          final theme = Theme.of(ctx);
          return PopScope(
            canPop: false,
            child: ValueListenableBuilder<_ProgressoBackupUi>(
              valueListenable: _progressoUi,
              builder: (context, p, _) {
                final pct = p.percentual;
                return AlertDialog(
                  title: Text(titulo),
                  content: SizedBox(
                    width: 380,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$pct%',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: p.valor > 0 ? p.valor : null,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.etapa.isEmpty ? 'Preparando…' : p.etapa,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Não feche o programa enquanto a tarefa estiver em andamento.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ).whenComplete(() {
        _dialogoProgressoAberto = false;
        _ctxDialogoProgresso = null;
      }),
    );
    // Espera o dialogo existir na pilha antes do trabalho pesado (evita pop falho).
    await dialogoPronto.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  void _fecharDialogoProgresso() {
    if (!_dialogoProgressoAberto) return;
    final ctx = _ctxDialogoProgresso;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).pop();
    } else if (mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    _dialogoProgressoAberto = false;
    _ctxDialogoProgresso = null;
  }

  Future<bool> _confirmarPastaSeRisco(String pasta) async {
    if (!BackupPastaRisco.pareceRisco(pasta)) return true;
    if (!mounted) return false;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pasta pouco segura'),
        content: Text(BackupPastaRisco.mensagemAviso(pasta)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Escolher outra'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usar mesmo assim'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<String?> _escolherPastaComAvisoRisco({
    required String dialogTitle,
  }) async {
    while (true) {
      final escolhida = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
      if (escolhida == null || escolhida.trim().isEmpty || !mounted) {
        return null;
      }
      final pasta = escolhida.trim();
      if (await _confirmarPastaSeRisco(pasta)) return pasta;
      if (!mounted) return null;
    }
  }

  String _rotuloRelativoUltimoBackup() {
    if (_manual.ultimoMs <= 0) return 'Nenhum backup manual ainda';
    final dt = DateTime.fromMillisecondsSinceEpoch(_manual.ultimoMs);
    final diff = DateTime.now().difference(dt);
    String quando;
    if (diff.inMinutes < 1) {
      quando = 'agora';
    } else if (diff.inMinutes < 60) {
      quando = 'há ${diff.inMinutes} min';
    } else if (diff.inHours < 48) {
      quando = 'há ${diff.inHours} h';
    } else {
      quando = 'há ${diff.inDays} dia(s)';
    }
    return 'Último backup: $quando · ${_dataHora.format(dt)}';
  }

  Future<void> _definirEscopoBackupAutomatico(LocalBackupEscopo? escopo) async {
    if (escopo == null) return;
    setState(() => _backupAutomaticoEscopo = escopo);
    await widget.configuracoesService.repository.salvarBackupAutomaticoEscopo(escopo);
  }

  Future<bool> _criarBackupDados({
    String? pastaDestino,
    required LocalBackupEscopo escopo,
  }) async {
    if (_backupEmAndamento) return false;
    var destinoRaiz = pastaDestino?.trim() ?? '';
    if (destinoRaiz.isEmpty) {
      destinoRaiz = _manual.pastaPadrao.trim();
    }
    if (destinoRaiz.isEmpty) {
      final escolhida = await _escolherPastaComAvisoRisco(
        dialogTitle: 'Escolha a pasta para salvar o backup',
      );
      if (escolhida == null || !mounted) return false;
      destinoRaiz = escolhida;
    } else if (!await _confirmarPastaSeRisco(destinoRaiz)) {
      final outra = await _escolherPastaComAvisoRisco(
        dialogTitle: 'Escolha outra pasta para o backup',
      );
      if (outra == null || !mounted) return false;
      destinoRaiz = outra;
    }

    setState(() {
      _backupEmAndamento = true;
      _progresso = 0;
      _etapaProgresso = 'Iniciando…';
    });
    _progressoUi.value = const _ProgressoBackupUi(valor: 0, etapa: 'Iniciando…');
    await _abrirDialogoProgresso(titulo: 'Backup em andamento');
    try {
      final resultado = await LocalBackupService.executar(
        destinoRaiz: Directory(destinoRaiz),
        tipo: LocalBackupTipo.manual,
        nomeLoja: widget.nomeLoja,
        objectBox: widget.objectBox,
        escopo: escopo,
        lanSyncScheduler: widget.lanSyncScheduler,
        onProgress: _atualizarProgresso,
      );

      // Fecha o modal assim que a copia/exportacao termina; o pos-processamento
      // (retencao, historico) nao deve deixar a tela presa em 100%.
      _fecharDialogoProgresso();

      await widget.configuracoesService.repository.salvarRegistroBackupManual(
        ultimoMs: resultado.criadoEm.millisecondsSinceEpoch,
        ultimoPath: resultado.pastaBackup.path,
        ultimoTamanhoKb: resultado.tamanhoBancoKb,
        pastaPadrao: destinoRaiz,
      );

      await _posProcessarBackup(
        pastaRaiz: Directory(destinoRaiz),
        pastaBackup: resultado.pastaBackup,
      );
      await widget.configuracoesService.repository.limparFalhaBackupAutomatico();

      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupCriar,
        resumo: 'Backup manual ${escopo.rotulo} criado',
        detalhes: {
          'caminho': resultado.pastaBackup.path,
          'escopo': escopo.manifestValue,
          if (resultado.quantidadeProdutos != null)
            'quantidadeProdutos': resultado.quantidadeProdutos,
        },
      );

      if (!mounted) return false;
      await _recarregar();
      final mensagemSucesso = escopo == LocalBackupEscopo.cadastroProdutos
          ? 'Backup de cadastro concluido com '
              '${resultado.quantidadeProdutos ?? 0} produto(s).\n\n'
              'Pasta:\n${resultado.pastaBackup.path}'
          : 'Backup ${escopo.rotulo.toLowerCase()} concluido com sucesso.\n\n'
              'Pasta:\n${resultado.pastaBackup.path}';
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            escopo == LocalBackupEscopo.cadastroProdutos
                ? 'Backup de cadastro (${resultado.quantidadeProdutos ?? 0} '
                    'produto(s)) concluido.'
                : 'Backup ${escopo.rotulo.toLowerCase()} concluido.',
          ),
        ),
      );
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup concluido'),
          content: SelectableText(mensagemSucesso),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return true;
    } on LocalBackupInvalidoException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao criar backup: $e')),
      );
      return false;
    } finally {
      _fecharDialogoProgresso();
      if (mounted) {
        setState(() {
          _backupEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _executarBackupAutomaticoAgora() async {
    // TODO(backlog): Trava global de execucao simultanea (mutex/lock) compartilhada
    // com AutoBackupService / ao fechar / headless — mapeada para versoes futuras.
    // Por ora mantem apenas a flag `_backupEmAndamento` em memoria nesta tela.
    if (_backupEmAndamento) return;
    if (_backupAutomaticoPasta.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escolha a pasta de destino para executar o backup agora.',
          ),
        ),
      );
      await _escolherPastaBackupAutomatico();
      if (_backupAutomaticoPasta.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup cancelado: nenhuma pasta de destino selecionada.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _backupEmAndamento = true;
      _progresso = 0;
      _etapaProgresso = 'Iniciando…';
    });
    _progressoUi.value = const _ProgressoBackupUi(valor: 0, etapa: 'Iniciando…');
    await _abrirDialogoProgresso(titulo: 'Backup em andamento');
    try {
      final resultado = await LocalBackupService.executar(
        destinoRaiz: Directory(_backupAutomaticoPasta.trim()),
        tipo: LocalBackupTipo.automatico,
        nomeLoja: widget.nomeLoja,
        objectBox: widget.objectBox,
        escopo: _backupAutomaticoEscopo,
        lanSyncScheduler: widget.lanSyncScheduler,
        onProgress: _atualizarProgresso,
      );
      _fecharDialogoProgresso();
      await widget.configuracoesService.repository.atualizarUltimoBackupAutomaticoMs(
        resultado.criadoEm.millisecondsSinceEpoch,
      );
      await _posProcessarBackup(
        pastaRaiz: Directory(_backupAutomaticoPasta.trim()),
        pastaBackup: resultado.pastaBackup,
      );
      await widget.configuracoesService.repository.limparFalhaBackupAutomatico();
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupAutomatico,
        resumo: 'Backup automático manual (agora)',
        detalhes: {'caminho': resultado.pastaBackup.path},
      );
      if (!mounted) return;
      await _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup automático concluido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no backup: $e')),
      );
    } finally {
      _fecharDialogoProgresso();
      if (mounted) {
        setState(() {
          _backupEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _alternarBackupAutomatico(bool value) async {
    if (value) {
      var pasta = _backupAutomaticoPasta.trim();
      if (pasta.isEmpty) {
        final escolhida = await _escolherPastaComAvisoRisco(
          dialogTitle:
              'Pasta para backups automáticos (subpastas com data e hora)',
        );
        if (escolhida == null || !mounted) return;
        pasta = escolhida;
      } else if (!await _confirmarPastaSeRisco(pasta)) {
        final outra = await _escolherPastaComAvisoRisco(
          dialogTitle: 'Escolha outra pasta para backups automáticos',
        );
        if (outra == null || !mounted) return;
        pasta = outra;
      }
      if (!mounted) return;
      setState(() {
        _backupAutomaticoAtivo = true;
        _backupAutomaticoPasta = pasta;
      });
      await _persistirPreferenciasBackupAutomatico();
      await AutoBackupService.tentarExecutarSeDevido(
        widget.configuracoesService.repository,
        objectBox: widget.objectBox,
        lanSyncScheduler: widget.lanSyncScheduler,
      );
      await _recarregar();
    } else {
      setState(() => _backupAutomaticoAtivo = false);
      await _persistirPreferenciasBackupAutomatico();
      await _recarregar();
    }
  }

  Future<void> _escolherPastaBackupAutomatico() async {
    final escolhida = await _escolherPastaComAvisoRisco(
      dialogTitle: 'Pasta para backups automáticos',
    );
    if (escolhida == null || !mounted) return;
    setState(() => _backupAutomaticoPasta = escolhida);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _definirIntervaloBackupAutomatico(int? minutos) async {
    if (minutos == null) return;
    setState(() => _backupAutomaticoIntervaloMinutos = minutos);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _abrirPastaDados() async {
    try {
      final baseDir = await obterDiretorioBaseDadosApp();
      if (!baseDir.existsSync()) {
        throw Exception('Pasta de dados local não encontrada.');
      }
      if (Platform.isWindows) {
        await WindowsShellPaths.abrirPastaNoExplorador(baseDir.path);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [baseDir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [baseDir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a pasta: $e')),
      );
    }
  }

  Future<void> _abrirPastaBackup(String caminho) async {
    try {
      final dir = Directory(caminho);
      if (!dir.existsSync()) {
        throw Exception('Pasta não encontrada.');
      }
      if (Platform.isWindows) {
        await WindowsShellPaths.abrirPastaNoExplorador(dir.path);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [dir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a pasta: $e')),
      );
    }
  }

  Future<void> _restaurarBackupDados() async {
    if (_restauracaoEmAndamento || _backupEmAndamento) return;
    setState(() {
      _restauracaoEmAndamento = true;
      _progresso = 0.05;
      _etapaProgresso = 'Selecionando pasta…';
    });
    try {
      final pastaSelecionada = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Escolha a pasta do backup',
      );
      if (pastaSelecionada == null ||
          pastaSelecionada.trim().isEmpty ||
          !mounted) {
        return;
      }
      await _confirmarERestaurar(Directory(pastaSelecionada.trim()));
    } on LocalBackupInvalidoException catch (e) {
      await _tratarErroRestauracao(e.message, invalido: true);
    } catch (e) {
      await _tratarErroRestauracao('Falha ao restaurar backup: $e');
    } finally {
      _fecharDialogoProgresso();
      if (mounted) {
        setState(() {
          _restauracaoEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _restaurarDoHistorico(BackupHistoricoItem item) async {
    if (_restauracaoEmAndamento || _backupEmAndamento) return;
    if (!item.valido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este backup está incompleto ou inválido.'),
        ),
      );
      return;
    }
    setState(() {
      _restauracaoEmAndamento = true;
      _progresso = 0.05;
      _etapaProgresso = 'Preparando restauração…';
    });
    try {
      await _confirmarERestaurar(item.pasta, item: item);
    } on LocalBackupInvalidoException catch (e) {
      await _tratarErroRestauracao(e.message, invalido: true);
    } catch (e) {
      await _tratarErroRestauracao('Falha ao restaurar backup: $e');
    } finally {
      _fecharDialogoProgresso();
      if (mounted) {
        setState(() {
          _restauracaoEmAndamento = false;
          _progresso = 0;
          _etapaProgresso = '';
        });
      }
    }
  }

  Future<void> _confirmarERestaurar(
    Directory pastaBackup, {
    BackupHistoricoItem? item,
  }) async {
    var criarBackupAntes = true;
    final confirmaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final textoValido =
                confirmaController.text.trim().toUpperCase() == 'RESTAURAR';
            return AlertDialog(
              title: const Text('Restaurar backup'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item != null) ...[
                      Text(
                        'Data: ${_dataHora.format(item.criadoEm)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text('Tipo: ${item.rotuloTipo}'),
                      Text('Escopo: ${item.rotuloEscopo}'),
                      Text('Tamanho: ${item.tamanhoFormatado}'),
                      if (item.empresa.trim().isNotEmpty)
                        Text('Empresa: ${item.empresa}'),
                      const SizedBox(height: 8),
                      SelectableText(
                        item.pasta.path,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ] else
                      const Text(
                        'Essa ação vai sobrescrever os dados locais atuais.',
                      ),
                    if (item != null &&
                        item.escopo == LocalBackupEscopo.somenteBanco) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este backup contém somente o banco. Fotos, POD e '
                        'configurações atuais deste PC serão mantidos.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (item != null &&
                        item.escopo == LocalBackupEscopo.semImagens) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este backup não inclui fotos. As imagens atuais '
                        'deste PC serão mantidas.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (item != null &&
                        item.escopo == LocalBackupEscopo.cadastroProdutos) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este backup atualiza o cadastro de produtos por código. '
                        'Vendas, clientes e estoque local dos produtos já '
                        'existentes serão preservados.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Text(
                      'O programa fechará sozinho após copiar o backup.\n'
                      'Sem backup de segurança, não há como desfazer se algo der errado.',
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Criar backup de segurança antes'),
                      subtitle: Text(
                        criarBackupAntes
                            ? 'Recomendado — salva o estado atual antes de sobrescrever.'
                            : 'Atenção: restaurar sem backup de segurança e irreversível.',
                        style: TextStyle(
                          color: criarBackupAntes
                              ? null
                              : Theme.of(context).colorScheme.error,
                          fontWeight: criarBackupAntes
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                      value: criarBackupAntes,
                      onChanged: (v) =>
                          setDialogState(() => criarBackupAntes = v ?? true),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Digite RESTAURAR para confirmar:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: confirmaController,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'RESTAURAR'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: textoValido
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
    confirmaController.dispose();
    if (confirmar != true || !mounted) return;

    if (criarBackupAntes) {
      await _abrirDialogoProgresso(titulo: 'Restauração em andamento');
      _atualizarProgresso(0.05, 'Criando backup de segurança… 5%');
      var destino = _backupAutomaticoPasta.trim();
      if (destino.isEmpty) destino = _manual.pastaPadrao.trim();
      if (destino.isEmpty) {
        final escolhida = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Pasta para backup de segurança',
        );
        if (escolhida == null || escolhida.trim().isEmpty || !mounted) {
          _fecharDialogoProgresso();
          return;
        }
        destino = escolhida.trim();
      }
      try {
        final seguranca = await LocalBackupService.executar(
          destinoRaiz: Directory(destino),
          tipo: LocalBackupTipo.manual,
          nomeLoja: widget.nomeLoja,
          objectBox: widget.objectBox,
          escopo: LocalBackupEscopo.completo,
          lanSyncScheduler: widget.lanSyncScheduler,
          onProgress: (v, etapa) {
            // Reserva 0–40% para o backup de seguranca.
            _atualizarProgresso(v * 0.4, etapa);
          },
        );
        await widget.configuracoesService.repository.salvarRegistroBackupManual(
          ultimoMs: seguranca.criadoEm.millisecondsSinceEpoch,
          ultimoPath: seguranca.pastaBackup.path,
          ultimoTamanhoKb: seguranca.tamanhoBancoKb,
          pastaPadrao: destino,
        );
        await _posProcessarBackup(
          pastaRaiz: Directory(destino),
          pastaBackup: seguranca.pastaBackup,
        );
      } catch (e) {
        if (!mounted) return;
        _fecharDialogoProgresso();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha no backup de segurança: $e')),
        );
        return;
      }
    }

    await _executarRestauracao(pastaBackup);
  }

  Future<void> _tratarErroRestauracao(
    String mensagem, {
    bool invalido = false,
  }) async {
    _fecharDialogoProgresso();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          duration: const Duration(seconds: 12),
          backgroundColor: invalido ? Colors.red.shade700 : null,
        ),
      );
    }
    if (widget.objectBox.store.isClosed()) {
      try {
        await widget.objectBox.reabrirAposCopiaDeArquivos();
      } catch (_) {
        exit(1);
      }
    }
  }

  Future<void> _executarRestauracao(Directory origemSelecionada) async {
    _atualizarProgresso(0.02, 'Validando backup… 2%');
    await _abrirDialogoProgresso(titulo: 'Restauração em andamento');
    final escopo = await LocalBackupService.lerEscopoManifest(origemSelecionada);

    if (escopo == LocalBackupEscopo.cadastroProdutos) {
      LocalBackupValidation.validarCadastroProdutos(origemSelecionada);
      _atualizarProgresso(0.05, 'Importando cadastro de produtos… 5%');
      final resumo = await restaurarDadosLocais(
        pastaBackupSelecionada: origemSelecionada,
        destinoBase: await obterDiretorioBaseDadosApp(),
        limparDestino: _limparDiretorio,
        objectBox: widget.objectBox,
        onProgress: _atualizarProgresso,
      );
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupRestaurar,
        resumo: 'Cadastro de produtos restaurado',
        detalhes: {
          'origem': origemSelecionada.path,
          'inseridos': resumo?.inseridos ?? 0,
          'atualizados': resumo?.atualizados ?? 0,
        },
      );
      if (!mounted) return;
      _fecharDialogoProgresso();
      final msg =
          'Cadastro restaurado com sucesso.\n\n'
          'Novos: ${resumo?.inseridos ?? 0}\n'
          'Atualizados: ${resumo?.atualizados ?? 0}\n'
          'Fotos restauradas: ${resumo?.fotosRestauradas ?? 0}'
          '${(resumo?.fotosFaltando ?? 0) > 0 ? '\nFotos faltando no backup: ${resumo!.fotosFaltando}' : ''}\n\n'
          'Estoque local foi preservado nos produtos existentes.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cadastro restaurado: ${resumo?.inseridos ?? 0} novo(s), '
            '${resumo?.atualizados ?? 0} atualizado(s), '
            '${resumo?.fotosRestauradas ?? 0} foto(s).',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restauração concluída'),
          content: Text(msg),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _recarregar();
      return;
    }

    final origemDados = LocalBackupValidation.resolverPastaDadosBackup(
      origemSelecionada,
    );
    LocalBackupValidation.validarDadosAplicacao(origemDados);
    final baseDir = await obterDiretorioBaseDadosApp();

    if (p.normalize(origemDados.path) == p.normalize(baseDir.path)) {
      throw Exception(
        'A pasta de origem não pode ser a mesma pasta de dados atual.',
      );
    }

    _atualizarProgresso(0.08, 'Preparando arquivos… 8%');

    await widget.lanSyncScheduler?.parar();
    await widget.objectBox.fecharParaCopiaDeArquivos();
    await restaurarDadosLocais(
      pastaBackupSelecionada: origemSelecionada,
      destinoBase: baseDir,
      limparDestino: _limparDiretorio,
      onProgress: _atualizarProgresso,
    );
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.backup,
      acao: AuditoriaAcao.backupRestaurar,
      resumo: 'Backup restaurado (app será fechado)',
      detalhes: {
        'origem': origemDados.path,
        'banco': LocalBackupValidation.descreverTamanhoBanco(baseDir),
      },
    );

    if (!mounted) {
      exit(0);
    }

    _fecharDialogoProgresso();

    final cores = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: Icon(
              Icons.check_circle_outline,
              size: 48,
              color: cores.primary,
            ),
            title: const Text('Backup restaurado'),
            content: const Text(
              'Os dados foram copiados com sucesso.\n\n'
              'Toque em OK para fechar o aplicativo. '
              'Abra-o novamente para usar os dados restaurados.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx, rootNavigator: true).pop();
                  exit(0);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _limparDiretorio(Directory diretorio) async {
    await limparDiretorioDestinoRestauracao(diretorio);
  }

  Color _corSaude(BuildContext context) {
    return switch (_status?.saude) {
      BackupSaude.protegido => Colors.green.shade700,
      BackupSaude.atencao => Colors.orange.shade800,
      BackupSaude.configIncompleta => Colors.orange.shade800,
      BackupSaude.critico => Colors.red.shade700,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  String _textoUltimoBackup() {
    final s = _status;
    if (s?.automaticoSemDestino == true) {
      return 'Ativo sem destino — selecione a pasta para o automático funcionar';
    }
    if (s == null || s.ultimoBackupMs <= 0) {
      return 'Nenhum backup registrado neste PC';
    }
    final quando = _dataHora.format(
      DateTime.fromMillisecondsSinceEpoch(s.ultimoBackupMs),
    );
    final tipo = s.ultimoBackupTipo == 'automatico' ? 'automatico' : 'manual';
    final tam = s.ultimoBackupTamanhoKb > 0
        ? ' · ${LocalBackupValidation.formatarTamanhoKb(s.ultimoBackupTamanhoKb)}'
        : '';
    return 'Último ($tipo): $quando$tam';
  }

  /// Rotulo curto da rotina automatica (timer + copia ao encerrar).
  String? _textoRotinaBackup() {
    if (_backupAutomaticoAtivo && _backupAoFecharAtivo) {
      return 'Backup automático + Cópia ao encerrar ativos';
    }
    if (_backupAutomaticoAtivo) {
      return 'Backup automático ativo';
    }
    if (_backupAoFecharAtivo) {
      return 'Cópia ao encerrar ativa';
    }
    return null;
  }

  String _tooltipRotinaBackup() {
    if (_backupAutomaticoAtivo && _backupAoFecharAtivo) {
      return 'Rotina automática: cópia periódica enquanto o app estiver aberto '
          'e, ao sair, pergunta se deseja uma cópia extra. '
          'Ambos usam a pasta de destino configurada.';
    }
    if (_backupAutomaticoAtivo) {
      return 'Cópia periódica enquanto o app estiver aberto, conforme a frequência.';
    }
    return 'Ao fechar, pergunta se deseja copiar o backup agora '
        '(requer pasta de destino).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ocupado = _backupEmAndamento || _restauracaoEmAndamento;

    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPainelStatus(context),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backup automático',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cópia periódica enquanto o app estiver aberto. Use pasta em '
                  'outro disco, rede ou nuvem sincronizada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativar backup automático'),
                  subtitle: Text(
                    _backupAutomaticoPasta.trim().isEmpty
                        ? 'Requer pasta de destino selecionada.'
                        : 'Cópias periódicas na pasta configurada.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _backupAutomaticoAtivo,
                  onChanged: ocupado ? null : _alternarBackupAutomatico,
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : _escolherPastaBackupAutomatico,
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                  label: Text(
                    _backupAutomaticoPasta.trim().isEmpty
                        ? 'Selecionar Pasta...'
                        : 'Alterar pasta de destino',
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _backupAutomaticoPasta.trim().isEmpty
                      ? 'Nenhuma pasta selecionada'
                      : _backupAutomaticoPasta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _backupAutomaticoPasta.trim().isEmpty
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: _backupAutomaticoPasta.trim().isEmpty
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<LocalBackupEscopo>(
                  key: ValueKey(_backupAutomaticoEscopo),
                  decoration: const InputDecoration(
                    labelText: 'Conteúdo do backup automático',
                  ),
                  initialValue: _backupAutomaticoEscopo,
                  items: localBackupEscoposAutomaticos()
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.rotulo),
                        ),
                      )
                      .toList(),
                  onChanged: ocupado ? null : _definirEscopoBackupAutomatico,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    _backupAutomaticoEscopo.descricaoCurta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Diário recomendado: só o banco. O completo copia as fotos '
                    'e é o que deixa o backup lento — faça um por semana.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_backupAutomaticoAtivo &&
                    _backupAutomaticoEscopo == LocalBackupEscopo.completo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'O automático está em Completo: copia as fotos todo dia. '
                      'Troque para "Só o banco (diário)" e use "Backup completo agora" '
                      'uma vez por semana.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  key: ValueKey(_backupAutomaticoIntervaloMinutos),
                  decoration: const InputDecoration(labelText: 'Frequencia'),
                  initialValue: _backupAutomaticoIntervaloMinutos,
                  items: const [60, 360, 720, 1440]
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(BackupStatusHelper.rotuloIntervalo(m)),
                        ),
                      )
                      .toList(),
                  onChanged: ocupado ? null : _definirIntervaloBackupAutomatico,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('retencao_$_backupRetencaoMaxCopias'),
                  decoration: const InputDecoration(
                    labelText: 'Retenção dos backups leves',
                  ),
                  initialValue: _backupRetencaoMaxCopias,
                  items: BackupRetencaoOpcoes.valoresPermitidos
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(BackupRetencaoOpcoes.rotulo(n)),
                        ),
                      )
                      .toList(),
                  onChanged: ocupado ? null : _definirRetencaoBackup,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Só o banco e sem fotos. Não apaga os completos.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('retencao_completos_$_backupRetencaoCompletos'),
                  decoration: const InputDecoration(
                    labelText: 'Retenção dos backups completos',
                  ),
                  initialValue: _backupRetencaoCompletos,
                  items: BackupRetencaoCompletosOpcoes.valoresPermitidos
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(BackupRetencaoCompletosOpcoes.rotulo(n)),
                        ),
                      )
                      .toList(),
                  onChanged: ocupado ? null : _definirRetencaoCompletos,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Cópias com fotos. O padrão é 4; as mais antigas saem '
                    'no próximo backup.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Backup ao fechar o sistema'),
                  subtitle: Text(
                    'Ao fechar, pergunta se deseja copiar o backup agora '
                    '(requer pasta de destino).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _backupAoFecharAtivo,
                  onChanged: ocupado ? null : _alternarBackupAoFechar,
                ),
                if (_ultimoBackupAutomaticoMs > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Último automático: ${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_ultimoBackupAutomaticoMs))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_status?.proximoBackupAutomaticoMs != null &&
                    _backupAutomaticoAtivo) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Próximo previsto: ${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_status!.proximoBackupAutomaticoMs!))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: ocupado
                      ? null
                      : () => unawaited(_executarBackupAutomaticoAgora()),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(
                    _backupAutomaticoPasta.trim().isEmpty
                        ? 'Executar backup agora (escolher pasta)'
                        : 'Executar backup agora',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            'Opções avançadas',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Segundo destino, exportação ZIP e tarefa agendada no Windows.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            _buildResilienciaConteudo(context, ocupado),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ações agora',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Proteger os dados, recuperar um backup ou ferramentas avançadas.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _buildResumoUltimoBackup(context),
                const SizedBox(height: 14),
                Text(
                  'Recuperar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sobrescreve os dados deste PC. Pede confirmação e backup de segurança.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: ocupado
                      ? null
                      : () => unawaited(_restaurarBackupDados()),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(
                    _restauracaoEmAndamento
                        ? 'Restaurando…'
                        : 'Restaurar backup (pasta)',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      ocupado ? null : () => unawaited(_restaurarDeArquivoZip()),
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('Restaurar de arquivo ZIP'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Proteger',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Completo uma vez por semana (fotos e entregas). '
                  'O diário automático deve ficar em só o banco.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: ocupado
                      ? null
                      : () => unawaited(
                            _criarBackupDados(
                              escopo: LocalBackupEscopo.completo,
                            ),
                          ),
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(
                    _backupEmAndamento
                        ? 'Criando backup…'
                        : 'Backup completo agora',
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: Text(
                    'Ferramentas avançadas',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Backup parcial, pasta de dados, migração e limpeza.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Backup parcial (não substitui o completo no dia a dia)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<LocalBackupEscopo>(
                      value: _escopoBackupParcial,
                      decoration: const InputDecoration(
                        labelText: 'O que incluir',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final e in LocalBackupEscopo.values)
                          if (e != LocalBackupEscopo.completo)
                            DropdownMenuItem(
                              value: e,
                              child: Text(e.rotulo),
                            ),
                      ],
                      onChanged: ocupado
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _escopoBackupParcial = v);
                            },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _escopoBackupParcial.descricaoCurta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: ocupado
                          ? null
                          : () => unawaited(
                                _criarBackupDados(escopo: _escopoBackupParcial),
                              ),
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text('Backup parcial agora'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: ocupado ? null : _abrirPastaDados,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Abrir pasta de dados'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: ocupado
                          ? null
                          : () => unawaited(_importarBackupChacal()),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text(
                        'Importar sistema antigo (Chacal)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: ocupado
                          ? null
                          : () => unawaited(_zerarCadastroProdutos()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error),
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Zerar cadastro de produtos'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildHistoricoCard(context, ocupado),
        if (ocupado) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${(_progresso * 100).round().clamp(0, 100)}%',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _etapaProgresso.isEmpty ? 'Preparando…' : _etapaProgresso,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progresso > 0 ? _progresso : null,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResumoUltimoBackup(BuildContext context) {
    final theme = Theme.of(context);
    final path = _manual.ultimoPath.trim();
    final risco = path.isNotEmpty && BackupPastaRisco.pareceRisco(path);
    final destinoPadrao = _manual.pastaPadrao.trim().isNotEmpty
        ? _manual.pastaPadrao.trim()
        : (_backupAutomaticoPasta.trim().isNotEmpty
            ? _backupAutomaticoPasta.trim()
            : '');
    final riscoDestino =
        destinoPadrao.isNotEmpty && BackupPastaRisco.pareceRisco(destinoPadrao);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _rotuloRelativoUltimoBackup(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (path.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                path,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => unawaited(_abrirPastaBackup(path)),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Abrir pasta do último backup'),
                ),
              ),
            ],
            if (risco || riscoDestino) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pasta em Área de Trabalho, Downloads ou nuvem '
                      '(OneDrive etc.) — prefira um disco local dedicado.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPainelStatus(BuildContext context) {
    final theme = Theme.of(context);
    final cor = _corSaude(context);
    final s = _status;
    final saude = s?.saude ?? BackupSaude.desconhecido;

    final pastaAuto = _backupAutomaticoPasta.trim();
    final pastaTxt = pastaAuto.isEmpty
        ? 'Pasta automática não configurada'
        : pastaAuto;

    String proximoTxt = 'Automático desligado';
    final pastaAutoOk = pastaAuto.isNotEmpty;
    if (_backupAutomaticoAtivo && pastaAutoOk) {
      if (s?.proximoBackupAutomaticoMs != null) {
        proximoTxt =
            'Próximo: ${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(s!.proximoBackupAutomaticoMs!))}';
      } else {
        proximoTxt = 'Próximo: ao abrir o app';
      }
    } else if (_backupAutomaticoAtivo && !pastaAutoOk) {
      proximoTxt = 'Indisponível — sem pasta de destino';
    }

    final bancoTxt = _tamanhoBancoLocal;

    return Card(
      color: cor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: cor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: cor.withValues(alpha: 0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        saude == BackupSaude.configIncompleta
                            ? 'Ativo sem destino'
                            : BackupStatusHelper.rotuloSaude(saude),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _textoUltimoBackup(),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (s?.horasDesdeUltimo != null &&
                          s!.ultimoBackupMs > 0 &&
                          saude != BackupSaude.configIncompleta)
                        Text(
                          'Ha ${s.horasDesdeUltimo} hora(s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_textoRotinaBackup() != null) ...[
                        const SizedBox(height: 6),
                        Tooltip(
                          message: _tooltipRotinaBackup(),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _textoRotinaBackup()!,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResumoLinha(
              icone: Icons.schedule_outlined,
              rotulo: 'Próximo backup',
              valor: proximoTxt,
            ),
            const SizedBox(height: 6),
            _ResumoLinha(
              icone: Icons.folder_outlined,
              rotulo: 'Destino automático',
              valor: pastaTxt,
            ),
            const SizedBox(height: 6),
            _ResumoLinha(
              icone: Icons.storage_outlined,
              rotulo: 'Dados neste PC',
              valor: bancoTxt,
            ),
            if (_pastaDadosLocal.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _ResumoLinha(
                icone: Icons.folder_copy_outlined,
                rotulo: 'Pasta de dados',
                valor: _pastaDadosLocal,
              ),
            ],
            if (saude == BackupSaude.configIncompleta) ...[
              const SizedBox(height: 10),
              Text(
                'Selecione a pasta de destino ou use "Executar backup agora" '
                'para escolher o diretório na hora.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cor,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_backupEmAndamento || _restauracaoEmAndamento)
                    ? null
                    : () => unawaited(_restaurarBackupDados()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar backup'),
              ),
            ] else if (s?.exibirAlerta == true) ...[
              const SizedBox(height: 10),
              Text(
                'Recomendado: faça backup agora ou ative o automático '
                '(alerta após ${BackupStatusHelper.horasAlertaAtencao}h).',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cor,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_backupEmAndamento || _restauracaoEmAndamento)
                    ? null
                    : () => unawaited(_restaurarBackupDados()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar backup'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: (_backupEmAndamento || _restauracaoEmAndamento)
                      ? null
                      : () => unawaited(_restaurarBackupDados()),
                  icon: Icon(
                    Icons.restore_outlined,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Restaurar backup',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ],
            if (_falha.temFalha) ...[
              const SizedBox(height: 8),
              Text(
                'Última falha (${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_falha.ultimaMs))}): '
                '${_falha.mensagem}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResilienciaConteudo(BuildContext context, bool ocupado) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_redeModoServidor) ...[
          Text(
            'Este PC e servidor de sync — recomendado espelhar backups em pasta de rede.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Segundo destino (espelho)'),
              subtitle: const Text(
                'Copia cada backup para outra pasta (OneDrive, NAS, servidor).',
              ),
              value: _backupSegundoDestinoAtivo,
              onChanged: ocupado ? null : _alternarSegundoDestino,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: ocupado ? null : _escolherPastaSegundoDestino,
                icon: const Icon(Icons.folder_shared_outlined, size: 20),
                label: const Text('Pasta do segundo destino'),
              ),
            ),
            if (_backupSegundoDestinoPasta.trim().isNotEmpty)
              SelectableText(
                _backupSegundoDestinoPasta,
                style: theme.textTheme.bodySmall,
              ),
            if (Platform.isWindows) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tarefa agendada Windows',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message:
                        'A Tarefa Agendada do Windows (se instalada) roda de forma '
                        'independente 1x por dia no horário fixo do sistema, sem '
                        'interferir no timer interno da aplicação (ex.: 24h). '
                        'São mecanismos separados: o app checa o intervalo enquanto '
                        'está aberto; a tarefa do SO dispara o backup headless no horário.',
                    child: Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _tarefaWindowsInstalada
                    ? 'Status: instalada (diária as $_tarefaWindowsHorario)'
                    : 'Status: não instalada',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Roda 1x/dia no horário do Windows, de forma independente do '
                'timer interno do app (frequência automática). Não altera nem '
                'substitui o intervalo configurado acima. Requer o .exe instalado; '
                'se o app estiver aberto, o banco pode estar em uso e a tarefa '
                'pode falhar — preferivel o sistema fechado nesse horário.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(_tarefaWindowsHorario),
                decoration: const InputDecoration(
                  labelText: 'Horário da tarefa',
                ),
                initialValue: _tarefaWindowsHorario,
                items: const [
                  '02:00',
                  '22:00',
                  '23:00',
                  '06:00',
                ]
                    .map(
                      (h) => DropdownMenuItem(value: h, child: Text('Diário as $h')),
                    )
                    .toList(),
                onChanged: ocupado ? null : _definirHorarioTarefaWindows,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: ocupado ? null : () => unawaited(_instalarTarefaWindows()),
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('Instalar tarefa'),
                  ),
                  if (_tarefaWindowsInstalada)
                    OutlinedButton.icon(
                      onPressed: ocupado ? null : () => unawaited(_removerTarefaWindows()),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover tarefa'),
                    ),
                ],
              ),
            ],
          ],
    );
  }

  Widget _buildHistoricoCard(BuildContext context, bool ocupado) {
    final theme = Theme.of(context);
    final pastas = _pastasParaHistorico();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Histórico de backups',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar lista',
                  onPressed: ocupado ? null : () => unawaited(_carregarHistorico()),
                  icon: const Icon(Icons.refresh_outlined, size: 20),
                ),
              ],
            ),
            if (pastas.isEmpty)
              Text(
                'Configure a pasta de destino (automático ou manual) para listar cópias.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else if (_carregandoHistorico)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_historico.isEmpty)
              Text(
                'Nenhum backup encontrado nas pastas configuradas.',
                style: theme.textTheme.bodySmall,
              )
            else
              SizedBox(
                height: 280,
                child: ListView.separated(
                  itemCount: _historico.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _historico[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.valido
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: item.valido
                            ? Colors.green.shade700
                            : theme.colorScheme.error,
                      ),
                      title: Text(_dataHora.format(item.criadoEm)),
                      subtitle: Text(
                        '${item.rotuloTipo} · ${item.rotuloEscopo} · '
                        '${item.tamanhoFormatado}',
                      ),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'Exportar ZIP',
                            onPressed: ocupado || !item.valido
                                ? null
                                : () => unawaited(_exportarZipHistorico(item)),
                            icon: const Icon(Icons.archive_outlined),
                          ),
                          IconButton(
                            tooltip: 'Abrir pasta',
                            onPressed: ocupado
                                ? null
                                : () => unawaited(
                                      _abrirPastaBackup(item.pasta.path),
                                    ),
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                          IconButton(
                            tooltip: 'Restaurar',
                            onPressed: ocupado || !item.valido
                                ? null
                                : () => unawaited(_restaurarDoHistorico(item)),
                            icon: Icon(
                              Icons.restore_outlined,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
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

class _ResumoLinha extends StatelessWidget {
  const _ResumoLinha({
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icone,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rotulo,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                valor,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
