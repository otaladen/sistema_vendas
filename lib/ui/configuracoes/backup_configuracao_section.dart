import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/app_config_repository.dart';
import '../../data/backup_agendado_headless_service.dart';
import '../../data/auto_backup_service.dart';
import '../../data/backup_historico_service.dart';
import '../../data/backup_pos_execucao_service.dart';
import '../../data/backup_tarefa_windows_service.dart';
import '../../data/backup_zip_service.dart';
import '../../data/local_app_data_paths.dart';
import '../../data/local_backup_restore.dart';
import '../../data/local_backup_service.dart';
import '../../data/local_backup_validation.dart';
import '../../data/objectbox.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/backup_historico_item.dart';
import '../../domain/backup_retencao.dart';
import '../../domain/backup_status_helper.dart';
import '../../services/auditoria_registrar.dart';

class BackupConfiguracaoSection extends StatefulWidget {
  const BackupConfiguracaoSection({
    super.key,
    required this.appConfigRepository,
    required this.objectBox,
    this.lanSyncScheduler,
    required this.nomeLoja,
  });

  final AppConfigRepository appConfigRepository;
  final ObjectBox objectBox;
  final LanSyncScheduler? lanSyncScheduler;
  final String nomeLoja;

  @override
  State<BackupConfiguracaoSection> createState() =>
      _BackupConfiguracaoSectionState();
}

class _BackupConfiguracaoSectionState extends State<BackupConfiguracaoSection> {
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _backupEmAndamento = false;
  bool _restauracaoEmAndamento = false;
  double _progresso = 0;
  String _etapaProgresso = '';

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
  int _ultimoBackupAutomaticoMs = 0;

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

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    try {
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      final manual =
          await widget.appConfigRepository.carregarRegistroBackupManual();
      final falha =
          await widget.appConfigRepository.carregarFalhaBackupAutomatico();
      final aoFechar =
          await widget.appConfigRepository.carregarBackupAoFecharAtivo();
      final horarioTarefa =
          await widget.appConfigRepository.carregarHorarioTarefaBackupWindows();
      var tarefaInstalada = false;
      if (Platform.isWindows) {
        tarefaInstalada = await BackupTarefaWindowsService.tarefaInstalada();
      }
      final baseDir = await obterDiretorioBaseDadosApp();
      var tamanho = '—';
      if (baseDir.existsSync()) {
        tamanho = LocalBackupValidation.descreverTamanhoBanco(baseDir);
      }
      if (!mounted) return;
      setState(() {
        _manual = manual;
        _falha = falha;
        _backupAoFecharAtivo = aoFechar;
        _backupAutomaticoAtivo = config.backupAutomaticoAtivo;
        _backupAutomaticoPasta = config.backupAutomaticoPasta;
        _backupRetencaoMaxCopias = config.backupRetencaoMaxCopias;
        _backupSegundoDestinoAtivo = config.backupSegundoDestinoAtivo;
        _backupSegundoDestinoPasta = config.backupSegundoDestinoPasta;
        _redeModoServidor = config.redeModoServidor;
        _tarefaWindowsHorario =
            BackupTarefaWindowsService.normalizarHorario(horarioTarefa);
        _tarefaWindowsInstalada = tarefaInstalada;
        _backupAutomaticoIntervaloMinutos = () {
          const opcoes = [60, 360, 720, 1440];
          final raw = config.backupAutomaticoIntervaloMinutos.clamp(15, 10080);
          return opcoes.contains(raw) ? raw : 1440;
        }();
        _ultimoBackupAutomaticoMs = config.ultimoBackupAutomaticoMs;
        _tamanhoBancoLocal = tamanho;
        _pastaDadosLocal = baseDir.path;
        _status = BackupStatusHelper.avaliar(config: config, manual: manual);
        _carregando = false;
      });
      await _carregarHistorico();
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _persistirPreferenciasBackupAutomatico() async {
    final atual = await widget.appConfigRepository.carregarEmpresaConfig();
    await widget.appConfigRepository.salvarEmpresaConfig(
      atual.copyWith(
        backupAutomaticoAtivo: _backupAutomaticoAtivo,
        backupAutomaticoPasta: _backupAutomaticoPasta,
        backupAutomaticoIntervaloMinutos: _backupAutomaticoIntervaloMinutos
            .clamp(15, 10080),
        backupRetencaoMaxCopias: _backupRetencaoMaxCopias,
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
    } catch (_) {
      if (mounted) setState(() => _carregandoHistorico = false);
    }
  }

  Future<void> _posProcessarBackup({
    required Directory pastaRaiz,
    required Directory pastaBackup,
  }) async {
    await BackupPosExecucaoService.aposBackupSucesso(
      repository: widget.appConfigRepository,
      pastaRaizPrimaria: pastaRaiz,
      pastaBackup: pastaBackup,
    );
  }

  Future<void> _alternarSegundoDestino(bool value) async {
    if (value) {
      var pasta = _backupSegundoDestinoPasta.trim();
      if (pasta.isEmpty) {
        final escolhida = await FilePicker.platform.getDirectoryPath(
          dialogTitle:
              'Segundo destino (rede, nuvem ou pasta do servidor)',
        );
        if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
        pasta = escolhida.trim();
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
    final escolhida = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Segundo destino do backup',
    );
    if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
    setState(() => _backupSegundoDestinoPasta = escolhida.trim());
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
        const SnackBar(content: Text('As senhas nao conferem.')),
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
      _etapaProgresso = 'Extraindo ZIP…';
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
      await widget.appConfigRepository.salvarHorarioTarefaBackupWindows(
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
            'Tarefa diaria instalada as $_tarefaWindowsHorario. '
            'Feche o sistema nesse horario para o backup rodar.',
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
    await widget.appConfigRepository.salvarHorarioTarefaBackupWindows(
      _tarefaWindowsHorario,
    );
  }

  Future<void> _definirRetencaoBackup(int? copias) async {
    if (copias == null) return;
    setState(() => _backupRetencaoMaxCopias = copias);
    await _persistirPreferenciasBackupAutomatico();
    await _recarregar();
  }

  Future<void> _alternarBackupAoFechar(bool value) async {
    setState(() => _backupAoFecharAtivo = value);
    await widget.appConfigRepository.salvarBackupAoFecharAtivo(value);
  }

  void _atualizarProgresso(double v, String etapa) {
    if (!mounted) return;
    setState(() {
      _progresso = v.clamp(0, 1);
      _etapaProgresso = etapa;
    });
  }

  Future<void> _criarBackupDados({String? pastaDestino}) async {
    if (_backupEmAndamento) return;
    var destinoRaiz = pastaDestino?.trim() ?? '';
    if (destinoRaiz.isEmpty) {
      destinoRaiz = _manual.pastaPadrao.trim();
    }
    if (destinoRaiz.isEmpty) {
      final escolhida = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Escolha a pasta para salvar o backup',
      );
      if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
      destinoRaiz = escolhida.trim();
    }

    setState(() {
      _backupEmAndamento = true;
      _progresso = 0;
      _etapaProgresso = 'Iniciando…';
    });
    try {
      final resultado = await LocalBackupService.executar(
        destinoRaiz: Directory(destinoRaiz),
        tipo: LocalBackupTipo.manual,
        nomeLoja: widget.nomeLoja,
        objectBox: widget.objectBox,
        lanSyncScheduler: widget.lanSyncScheduler,
        onProgress: _atualizarProgresso,
      );

      await widget.appConfigRepository.salvarRegistroBackupManual(
        ultimoMs: resultado.criadoEm.millisecondsSinceEpoch,
        ultimoPath: resultado.pastaBackup.path,
        ultimoTamanhoKb: resultado.tamanhoBancoKb,
        pastaPadrao: destinoRaiz,
      );

      await _posProcessarBackup(
        pastaRaiz: Directory(destinoRaiz),
        pastaBackup: resultado.pastaBackup,
      );
      await widget.appConfigRepository.limparFalhaBackupAutomatico();

      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupCriar,
        resumo: 'Backup manual criado',
        detalhes: {'caminho': resultado.pastaBackup.path},
      );

      if (!mounted) return;
      await _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Backup concluido: ${resultado.pastaBackup.path}',
          ),
        ),
      );
    } on LocalBackupInvalidoException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao criar backup: $e')),
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

  Future<void> _executarBackupAutomaticoAgora() async {
    if (_backupEmAndamento) return;
    if (_backupAutomaticoPasta.trim().isEmpty) {
      await _escolherPastaBackupAutomatico();
      if (_backupAutomaticoPasta.trim().isEmpty) return;
    }

    setState(() {
      _backupEmAndamento = true;
      _progresso = 0;
      _etapaProgresso = 'Iniciando…';
    });
    try {
      final resultado = await LocalBackupService.executar(
        destinoRaiz: Directory(_backupAutomaticoPasta.trim()),
        tipo: LocalBackupTipo.automatico,
        nomeLoja: widget.nomeLoja,
        objectBox: widget.objectBox,
        lanSyncScheduler: widget.lanSyncScheduler,
        onProgress: _atualizarProgresso,
      );
      await widget.appConfigRepository.atualizarUltimoBackupAutomaticoMs(
        resultado.criadoEm.millisecondsSinceEpoch,
      );
      await _posProcessarBackup(
        pastaRaiz: Directory(_backupAutomaticoPasta.trim()),
        pastaBackup: resultado.pastaBackup,
      );
      await widget.appConfigRepository.limparFalhaBackupAutomatico();
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupAutomatico,
        resumo: 'Backup automatico manual (agora)',
        detalhes: {'caminho': resultado.pastaBackup.path},
      );
      if (!mounted) return;
      await _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup automatico concluido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no backup: $e')),
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

  Future<void> _alternarBackupAutomatico(bool value) async {
    if (value) {
      var pasta = _backupAutomaticoPasta.trim();
      if (pasta.isEmpty) {
        final escolhida = await FilePicker.platform.getDirectoryPath(
          dialogTitle:
              'Pasta para backups automaticos (subpastas com data e hora)',
        );
        if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
        pasta = escolhida.trim();
      }
      if (!mounted) return;
      setState(() {
        _backupAutomaticoAtivo = true;
        _backupAutomaticoPasta = pasta;
      });
      await _persistirPreferenciasBackupAutomatico();
      await AutoBackupService.tentarExecutarSeDevido(
        widget.appConfigRepository,
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
    final escolhida = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para backups automaticos',
    );
    if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
    setState(() => _backupAutomaticoPasta = escolhida.trim());
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
        throw Exception('Pasta de dados local nao encontrada.');
      }
      if (Platform.isWindows) {
        await Process.start('explorer', [baseDir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [baseDir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [baseDir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir a pasta: $e')),
      );
    }
  }

  Future<void> _abrirPastaBackup(String caminho) async {
    try {
      final dir = Directory(caminho);
      if (!dir.existsSync()) {
        throw Exception('Pasta nao encontrada.');
      }
      if (Platform.isWindows) {
        await Process.start('explorer', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [dir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir a pasta: $e')),
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
          content: Text('Este backup esta incompleto ou invalido.'),
        ),
      );
      return;
    }
    setState(() {
      _restauracaoEmAndamento = true;
      _progresso = 0.05;
      _etapaProgresso = 'Preparando restauracao…';
    });
    try {
      await _confirmarERestaurar(item.pasta, item: item);
    } on LocalBackupInvalidoException catch (e) {
      await _tratarErroRestauracao(e.message, invalido: true);
    } catch (e) {
      await _tratarErroRestauracao('Falha ao restaurar backup: $e');
    } finally {
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
                        'Essa acao vai sobrescrever os dados locais atuais.',
                      ),
                    const Text(
                      'Recomendado: criar um backup de seguranca antes.\n\n'
                      'O programa fechara sozinho apos copiar o backup.',
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Criar backup de seguranca antes'),
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
      _atualizarProgresso(0.12, 'Criando backup de seguranca…');
      var destino = _backupAutomaticoPasta.trim();
      if (destino.isEmpty) destino = _manual.pastaPadrao.trim();
      if (destino.isEmpty) {
        final escolhida = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Pasta para backup de seguranca',
        );
        if (escolhida == null || escolhida.trim().isEmpty || !mounted) return;
        destino = escolhida.trim();
      }
      try {
        final seguranca = await LocalBackupService.executar(
          destinoRaiz: Directory(destino),
          tipo: LocalBackupTipo.manual,
          nomeLoja: widget.nomeLoja,
          objectBox: widget.objectBox,
          lanSyncScheduler: widget.lanSyncScheduler,
          onProgress: _atualizarProgresso,
        );
        await widget.appConfigRepository.salvarRegistroBackupManual(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha no backup de seguranca: $e')),
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
    if (mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
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
    _atualizarProgresso(0.15, 'Validando backup…');
    final origemDados = LocalBackupValidation.resolverPastaDadosBackup(
      origemSelecionada,
    );
    LocalBackupValidation.validarDadosAplicacao(origemDados);
    final baseDir = await obterDiretorioBaseDadosApp();

    if (p.normalize(origemDados.path) == p.normalize(baseDir.path)) {
      throw Exception(
        'A pasta de origem nao pode ser a mesma pasta de dados atual.',
      );
    }

    _atualizarProgresso(0.35, 'Restaurando arquivos…');

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    Platform.isWindows
                        ? 'Restaurando backup… O aplicativo sera fechado ao terminar.'
                        : 'Restaurando backup… Aguarde.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    await widget.lanSyncScheduler?.parar();
    await widget.objectBox.fecharParaCopiaDeArquivos();
    await restaurarDadosLocais(
      pastaBackupSelecionada: origemSelecionada,
      destinoBase: baseDir,
      limparDestino: _limparDiretorio,
    );
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.backup,
      acao: AuditoriaAcao.backupRestaurar,
      resumo: 'Backup restaurado (app sera fechado)',
      detalhes: {
        'origem': origemDados.path,
        'banco': LocalBackupValidation.descreverTamanhoBanco(baseDir),
      },
    );

    if (!mounted) {
      exit(0);
    }

    Navigator.of(context, rootNavigator: true).pop();

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
    if (!diretorio.existsSync()) {
      diretorio.createSync(recursive: true);
      return;
    }
    await for (final entidade in diretorio.list(recursive: false)) {
      if (entidade is Directory) {
        await entidade.delete(recursive: true);
      } else if (entidade is File) {
        await entidade.delete();
      }
    }
  }

  Color _corSaude(BuildContext context) {
    return switch (_status?.saude) {
      BackupSaude.protegido => Colors.green.shade700,
      BackupSaude.atencao => Colors.orange.shade800,
      BackupSaude.critico => Colors.red.shade700,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  String _textoUltimoBackup() {
    final s = _status;
    if (s == null || s.ultimoBackupMs <= 0) {
      return 'Nenhum backup registrado neste PC';
    }
    final quando = _dataHora.format(
      DateTime.fromMillisecondsSinceEpoch(s.ultimoBackupMs),
    );
    final tipo = s.ultimoBackupTipo == 'automatico' ? 'automatico' : 'manual';
    final tam = s.ultimoBackupTamanhoKb > 0
        ? ' · ${s.ultimoBackupTamanhoKb.toStringAsFixed(1)} KB'
        : '';
    return 'Ultimo ($tipo): $quando$tam';
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
                  'Backup automatico',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Copia periodica enquanto o app estiver aberto. Use pasta em '
                  'outro disco, rede ou nuvem sincronizada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativar backup automatico'),
                  value: _backupAutomaticoAtivo,
                  onChanged: ocupado ? null : _alternarBackupAutomatico,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: ocupado ? null : _escolherPastaBackupAutomatico,
                    icon: const Icon(Icons.folder_outlined, size: 20),
                    label: const Text('Pasta de destino'),
                  ),
                ),
                if (_backupAutomaticoPasta.trim().isNotEmpty)
                  SelectableText(
                    _backupAutomaticoPasta,
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
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
                    labelText: 'Retencao na pasta de destino',
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Backup ao fechar o sistema'),
                  subtitle: Text(
                    'Executa ao sair da sessao ou fechar o app (requer pasta de destino).',
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
                    'Ultimo automatico: ${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_ultimoBackupAutomaticoMs))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_status?.proximoBackupAutomaticoMs != null &&
                    _backupAutomaticoAtivo) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Proximo previsto: ${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_status!.proximoBackupAutomaticoMs!))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: ocupado || _backupAutomaticoPasta.trim().isEmpty
                      ? null
                      : () => unawaited(_executarBackupAutomaticoAgora()),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Executar backup agora'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildResilienciaCard(context, ocupado),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Acoes manuais',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: ocupado ? null : () => unawaited(_criarBackupDados()),
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(
                    _backupEmAndamento
                        ? 'Criando backup…'
                        : 'Criar backup agora',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : _abrirPastaDados,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Abrir pasta de dados'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : () => unawaited(_restaurarBackupDados()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(
                    _restauracaoEmAndamento
                        ? 'Restaurando…'
                        : 'Restaurar backup',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : () => unawaited(_restaurarDeArquivoZip()),
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('Restaurar de arquivo ZIP'),
                ),
                if (_manual.ultimoPath.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ultimo manual: ${_manual.ultimoPath}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
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
                    _etapaProgresso,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progresso > 0 ? _progresso : null),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPainelStatus(BuildContext context) {
    final theme = Theme.of(context);
    final cor = _corSaude(context);
    final s = _status;

    return Card(
      color: cor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: cor, size: 22),
                const SizedBox(width: 8),
                Text(
                  BackupStatusHelper.rotuloSaude(s?.saude ?? BackupSaude.desconhecido),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_textoUltimoBackup(), style: theme.textTheme.bodyMedium),
            if (s?.horasDesdeUltimo != null && s!.ultimoBackupMs > 0)
              Text(
                'Ha ${s.horasDesdeUltimo} hora(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Banco local: $_tamanhoBancoLocal',
              style: theme.textTheme.bodySmall,
            ),
            if (_pastaDadosLocal.isNotEmpty)
              Text(
                _pastaDadosLocal,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (s?.exibirAlerta == true) ...[
              const SizedBox(height: 8),
              Text(
                'Recomendado: faca backup agora ou ative o automatico '
                '(alerta apos ${BackupStatusHelper.horasAlertaAtencao}h).',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cor,
                ),
              ),
            ],
            if (_falha.temFalha) ...[
              const SizedBox(height: 8),
              Text(
                'Ultima falha (${_dataHora.format(DateTime.fromMillisecondsSinceEpoch(_falha.ultimaMs))}): '
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

  Widget _buildResilienciaCard(BuildContext context, bool ocupado) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resiliencia avancada',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Segundo destino (rede/nuvem), exportacao ZIP e tarefa no Windows.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_redeModoServidor) ...[
              const SizedBox(height: 6),
              Text(
                'Este PC e servidor de sync — recomendado espelhar backups em pasta de rede.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
              Text(
                'Tarefa agendada Windows',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _tarefaWindowsInstalada
                    ? 'Status: instalada (diaria as $_tarefaWindowsHorario)'
                    : 'Status: nao instalada',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(_tarefaWindowsHorario),
                decoration: const InputDecoration(
                  labelText: 'Horario da tarefa',
                ),
                initialValue: _tarefaWindowsHorario,
                items: const [
                  '02:00',
                  '22:00',
                  '23:00',
                  '06:00',
                ]
                    .map(
                      (h) => DropdownMenuItem(value: h, child: Text('Diario as $h')),
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
              Text(
                'Requer o .exe instalado. Feche o sistema no horario — nao roda com o app aberto.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
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
                    'Historico de backups',
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
                'Configure a pasta de destino (automatico ou manual) para listar copias.',
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
                        '${item.rotuloTipo} · ${item.tamanhoFormatado}',
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
