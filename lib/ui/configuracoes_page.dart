import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../data/venda_repository.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key, required this.vendaRepository});

  final VendaRepository vendaRepository;

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _nomeLojaController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _pastaPadraoPdfController = TextEditingController();
  final _rodapeNotaController = TextEditingController();
  final _rodapeOrcamentoController = TextEditingController();
  final _limiteDivergenciaCaixaController = TextEditingController();
  final _configRepository = AppConfigRepository();
  String _modeloPdf = 'cupom';
  String _impressoraPadrao = '';
  String _logoPath = '';
  List<Printer> _impressoras = [];
  bool _salvando = false;
  bool _prefsEmpresaAplicadas = false;
  DateTime _agoraSistema = DateTime.now();
  DateTime? _ultimaVendaFinalizada;
  bool _horarioInconsistente = false;
  String _diagnosticoHorario = '';
  bool _backupEmAndamento = false;
  bool _restauracaoEmAndamento = false;
  String _ultimoBackupPath = '';
  bool _permitirVendaSemEstoque = true;

  @override
  void initState() {
    super.initState();
    _carregarConfig();
    _carregarDiagnosticoHorario();
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _pastaPadraoPdfController.dispose();
    _rodapeNotaController.dispose();
    _rodapeOrcamentoController.dispose();
    _limiteDivergenciaCaixaController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _nomeLojaController.text = config.nomeLoja;
      _telefoneController.text = config.telefone;
      _enderecoController.text = config.endereco;
      _pastaPadraoPdfController.text = config.pastaPadraoPdf;
      _rodapeNotaController.text = config.rodapeNota;
      _rodapeOrcamentoController.text = config.rodapeOrcamento;
      _limiteDivergenciaCaixaController.text = config.limiteDivergenciaCaixa
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _modeloPdf = config.modeloPdf;
      _impressoraPadrao = config.impressoraPadrao;
      _logoPath = config.logoPath;
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      _prefsEmpresaAplicadas = true;
    });
    try {
      final impressoras = await Printing.listPrinters();
      if (!mounted) return;
      setState(() {
        _impressoras = impressoras;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _impressoras = [];
      });
    }
  }

  Future<void> _carregarDiagnosticoHorario() async {
    final agora = DateTime.now();
    final vendas = widget.vendaRepository.listarTodas();
    DateTime? ultimaFinalizada;
    for (final venda in vendas) {
      if (venda.status == 'finalizada' && !venda.cancelada) {
        if (ultimaFinalizada == null || venda.data.isAfter(ultimaFinalizada)) {
          ultimaFinalizada = venda.data;
        }
      }
    }
    final inconsistente = ultimaFinalizada != null &&
        agora.isBefore(ultimaFinalizada.subtract(const Duration(minutes: 2)));
    if (!mounted) return;
    setState(() {
      _agoraSistema = agora;
      _ultimaVendaFinalizada = ultimaFinalizada;
      _horarioInconsistente = inconsistente;
      _diagnosticoHorario = inconsistente
          ? 'Horario do sistema esta atrasado em relacao a ultima venda finalizada. '
                'Corrija data/hora no Windows antes de emitir novas notas.'
          : 'Horario do sistema consistente para operacao de vendas e impressao.';
    });
  }

  Future<void> _abrirAjusteDataHoraSO() async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'ms-settings:dateandtime']);
      } else if (Platform.isLinux) {
        await Process.start('sh', ['-c', 'gnome-control-center datetime']);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          'x-apple.systempreferences:com.apple.preference.datetime',
        ]);
      }
    } catch (_) {
      // ignore and inform via snackbar below
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Abra as configuracoes de data/hora do sistema operacional para ajustar.',
        ),
      ),
    );
  }

  Future<void> _sincronizarHorarioWindows() async {
    if (!Platform.isWindows) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sincronizacao automatica disponivel apenas no Windows.',
          ),
        ),
      );
      return;
    }

    try {
      final resultado = await Process.run(
        'w32tm',
        ['/resync'],
        runInShell: true,
      );
      final codigo = resultado.exitCode;
      final saida = '${resultado.stdout}\n${resultado.stderr}'
          .trim()
          .toLowerCase();
      if (!mounted) return;
      if (codigo == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relogio sincronizado com sucesso.')),
        );
      } else {
        final precisaPermissao = saida.contains('acesso negado') ||
            saida.contains('access is denied') ||
            saida.contains('0x80070005');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              precisaPermissao
                  ? 'Sem permissao para sincronizar automaticamente. Execute o app/terminal como administrador.'
                  : 'Nao foi possivel sincronizar automaticamente. Verifique internet e servico de horario do Windows.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falha ao tentar sincronizar automaticamente. Use "Ajustar no sistema".',
          ),
        ),
      );
    } finally {
      await _carregarDiagnosticoHorario();
    }
  }

  Future<void> _escolherPastaPadraoPdf() async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta padrao para PDFs',
    );
    if (pasta == null || !mounted) return;
    setState(() {
      _pastaPadraoPdfController.text = pasta;
    });
  }

  Future<void> _escolherLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final sourcePath = result.files.single.path!;
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final logosDir = Directory(p.join(baseDir.path, 'logos'));
    if (!logosDir.existsSync()) {
      logosDir.createSync(recursive: true);
    }
    final ext = p.extension(sourcePath);
    final destPath = p.join(logosDir.path, 'logo_loja$ext');
    await File(sourcePath).copy(destPath);
    if (!mounted) return;
    setState(() {
      _logoPath = destPath;
    });
  }

  void _removerLogo() {
    setState(() {
      _logoPath = '';
    });
  }

  Future<void> _salvarConfig() async {
    if (!_prefsEmpresaAplicadas) {
      await _carregarConfig();
    }
    if (!mounted) return;
    setState(() => _salvando = true);
    try {
      await _configRepository.salvarEmpresaConfig(
        EmpresaConfig(
          nomeLoja: _nomeLojaController.text,
          telefone: _telefoneController.text,
          endereco: _enderecoController.text,
          pastaPadraoPdf: _pastaPadraoPdfController.text,
          impressoraPadrao: _impressoraPadrao,
          modeloPdf: _modeloPdf,
          rodapeNota: _rodapeNotaController.text,
          rodapeOrcamento: _rodapeOrcamentoController.text,
          logoPath: _logoPath,
          limiteDivergenciaCaixa:
              _parseMoeda(_limiteDivergenciaCaixaController.text) ?? 20,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuracoes da empresa salvas.')));
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Future<Printer?> _obterImpressoraPadrao() async {
    if (_impressoraPadrao.trim().isEmpty) return null;
    final printers = await Printing.listPrinters();
    for (final printer in printers) {
      if (printer.name == _impressoraPadrao) return printer;
    }
    return null;
  }

  Future<Uint8List> _gerarPdfTeste() async {
    final doc = pw.Document();
    final agora = DateTime.now();
    final dataFmt =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
    final logoBytes = _logoPath.trim().isNotEmpty
        ? await File(_logoPath).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    doc.addPage(
      pw.Page(
        pageFormat: _modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(10),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  _nomeLojaController.text.trim().isEmpty
                      ? 'LOJA DE MATERIAIS'
                      : _nomeLojaController.text.trim(),
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (_telefoneController.text.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text('Tel: ${_telefoneController.text.trim()}'),
                ),
              if (_enderecoController.text.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    _enderecoController.text.trim(),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(height: 10),
              pw.Text(
                'TESTE DE IMPRESSAO',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Data/hora: $dataFmt'),
              pw.Text('Modelo selecionado: ${_modeloPdf == 'a4' ? 'A4' : 'Cupom (80mm)'}'),
              pw.Text('Impressora padrao: ${_impressoraPadrao.isEmpty ? 'Nao definida' : _impressoraPadrao}'),
              pw.Text('Pasta padrao PDF: ${_pastaPadraoPdfController.text.trim().isEmpty ? 'Nao definida' : _pastaPadraoPdfController.text.trim()}'),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Text(
                _rodapeNotaController.text.trim().isEmpty
                    ? 'Documento nao fiscal'
                    : _rodapeNotaController.text.trim(),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _imprimirTeste() async {
    try {
      final printer = await _obterImpressoraPadrao();
      if (printer == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Defina uma impressora padrao para o teste.')),
        );
        return;
      }
      final pdfBytes = await _gerarPdfTeste();
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => pdfBytes,
        name: 'Teste Impressao Sistema Vendas',
        format: _modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Teste de impressao enviado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no teste de impressao: $e')),
      );
    }
  }

  Future<Directory> _obterDiretorioBaseDados() async {
    return Platform.isWindows
        ? getApplicationSupportDirectory()
        : getApplicationDocumentsDirectory();
  }

  Future<void> _criarBackupDados() async {
    if (_backupEmAndamento) return;
    final destinoRaiz = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para salvar o backup',
    );
    if (destinoRaiz == null || destinoRaiz.trim().isEmpty || !mounted) {
      return;
    }

    setState(() => _backupEmAndamento = true);
    try {
      final baseDadosDir = await _obterDiretorioBaseDados();
      if (!baseDadosDir.existsSync()) {
        throw Exception('Pasta de dados local nao encontrada.');
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final pastaBackup = Directory(
        p.join(destinoRaiz, 'backup_sistema_vendas_$timestamp'),
      );
      pastaBackup.createSync(recursive: true);
      await _copiarDiretorioRecursivo(
        origem: baseDadosDir,
        destino: Directory(p.join(pastaBackup.path, 'dados_aplicacao')),
      );

      if (!mounted) return;
      setState(() {
        _ultimoBackupPath = pastaBackup.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup concluido com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao criar backup: $e')));
    } finally {
      if (mounted) {
        setState(() => _backupEmAndamento = false);
      }
    }
  }

  Future<void> _copiarDiretorioRecursivo({
    required Directory origem,
    required Directory destino,
  }) async {
    if (!origem.existsSync()) return;
    destino.createSync(recursive: true);
    await for (final entidade in origem.list(recursive: false)) {
      final nome = p.basename(entidade.path);
      final destinoPath = p.join(destino.path, nome);
      if (entidade is Directory) {
        await _copiarDiretorioRecursivo(
          origem: entidade,
          destino: Directory(destinoPath),
        );
      } else if (entidade is File) {
        await entidade.copy(destinoPath);
      }
    }
  }

  Future<void> _abrirPastaDados() async {
    try {
      final baseDir = await _obterDiretorioBaseDados();
      if (!baseDir.existsSync()) {
        throw Exception('Pasta de dados local nao encontrada.');
      }
      if (Platform.isWindows) {
        await Process.start('explorer', [baseDir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [baseDir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [baseDir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nao foi possivel abrir a pasta de dados: $e')));
    }
  }

  double? _parseMoeda(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    return double.tryParse(normalizado);
  }

  Future<void> _restaurarBackupDados() async {
    if (_restauracaoEmAndamento || _backupEmAndamento) return;
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
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Essa acao vai sobrescrever os dados locais atuais.\n\n'
                    'Recomendado: criar um backup antes de restaurar.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Digite RESTAURAR para confirmar:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: confirmaController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'RESTAURAR',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: textoValido ? () => Navigator.pop(context, true) : null,
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

    final pastaSelecionada = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta do backup',
    );
    if (pastaSelecionada == null || pastaSelecionada.trim().isEmpty || !mounted) {
      return;
    }

    setState(() => _restauracaoEmAndamento = true);
    try {
      final origemSelecionada = Directory(pastaSelecionada);
      final origemDadosAplicacao = Directory(
        p.join(origemSelecionada.path, 'dados_aplicacao'),
      );
      final origemRestore = origemDadosAplicacao.existsSync()
          ? origemDadosAplicacao
          : origemSelecionada;
      final baseDir = await _obterDiretorioBaseDados();

      if (!origemRestore.existsSync()) {
        throw Exception('Pasta de backup invalida.');
      }
      if (p.normalize(origemRestore.path) == p.normalize(baseDir.path)) {
        throw Exception('A pasta de origem nao pode ser a mesma pasta de dados atual.');
      }

      await _limparDiretorio(baseDir);
      await _copiarDiretorioRecursivo(origem: origemRestore, destino: baseDir);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup restaurado com sucesso. Feche e abra o app para recarregar os dados.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao restaurar backup: $e')));
    } finally {
      if (mounted) {
        setState(() => _restauracaoEmAndamento = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final agoraFmt = dtFmt.format(_agoraSistema);
    final ultimaVendaFmt = _ultimaVendaFinalizada == null
        ? 'Nenhuma venda finalizada ainda'
        : dtFmt.format(_ultimaVendaFinalizada!.toLocal());
    final offset = _agoraSistema.timeZoneOffset;
    final sinal = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('CONFIGURACOES')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data e hora do sistema',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Agora (sistema): $agoraFmt'),
                  Text(
                    'Fuso horario: ${_agoraSistema.timeZoneName} (UTC$sinal$h:$m)',
                  ),
                  Text('Ultima venda finalizada: $ultimaVendaFmt'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _horarioInconsistente
                          ? Colors.red.withValues(alpha: 0.08)
                          : Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _horarioInconsistente
                            ? Colors.red.withValues(alpha: 0.45)
                            : Colors.green.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(_diagnosticoHorario),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _carregarDiagnosticoHorario,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Atualizar diagnostico'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _abrirAjusteDataHoraSO,
                          icon: const Icon(Icons.schedule),
                          label: const Text('Ajustar no sistema'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sincronizarHorarioWindows,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sincronizar horario agora (Windows)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Empresa',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nomeLojaController,
                    decoration: const InputDecoration(labelText: 'Nome da loja'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _telefoneController,
                    decoration: const InputDecoration(labelText: 'Telefone da loja'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _enderecoController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Endereco da loja'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _salvando ? null : _salvarConfig,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_salvando ? 'Salvando...' : 'Salvar dados da empresa'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Impressao e PDF',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pastaPadraoPdfController,
                    decoration: InputDecoration(
                      labelText: 'Pasta padrao de PDF (opcional)',
                      suffixIcon: IconButton(
                        tooltip: 'Escolher pasta',
                        onPressed: _escolherPastaPadraoPdf,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _modeloPdf,
                    decoration: const InputDecoration(labelText: 'Modelo de PDF'),
                    items: const [
                      DropdownMenuItem(value: 'cupom', child: Text('Cupom (80mm)')),
                      DropdownMenuItem(value: 'a4', child: Text('A4')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _modeloPdf = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _impressoras.any((p) => p.name == _impressoraPadrao)
                        ? _impressoraPadrao
                        : '',
                    decoration: const InputDecoration(labelText: 'Impressora padrao (opcional)'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Nenhuma')),
                      ..._impressoras.map(
                        (printer) => DropdownMenuItem(
                          value: printer.name,
                          child: Text(printer.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _impressoraPadrao = value ?? ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rodapeNotaController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Rodape da nota/cupom nao fiscal',
                      alignLabelWithHint: true,
                      hintText: 'Use Enter para nova linha',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rodapeOrcamentoController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Rodape do orcamento',
                      alignLabelWithHint: true,
                      hintText: 'Use Enter para nova linha',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _escolherLogo,
                          icon: const Icon(Icons.image_outlined),
                          label: Text(_logoPath.isEmpty ? 'Selecionar logo' : 'Trocar logo'),
                        ),
                      ),
                      if (_logoPath.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _removerLogo,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remover'),
                        ),
                      ],
                    ],
                  ),
                  if (_logoPath.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Logo selecionada: ${p.basename(_logoPath)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _salvando ? null : _salvarConfig,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_salvando ? 'Salvando...' : 'Salvar configuracoes de impressao/PDF'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _imprimirTeste,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Teste de impressao'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Caixa',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _limiteDivergenciaCaixaController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Limite de divergencia sem supervisor (R\$)',
                      hintText: 'Ex.: 20,00',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Defina o limite de divergencia para exigir autorizacao '
                    'de supervisor (admin/financeiro) no fechamento do caixa.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _permitirVendaSemEstoque,
                    onChanged: (value) {
                      setState(() {
                        _permitirVendaSemEstoque = value;
                      });
                    },
                    title: const Text('Permitir venda sem estoque'),
                    subtitle: const Text(
                      'Quando ativo, o sistema permite finalizar venda mesmo sem saldo e o estoque pode ficar negativo.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _salvando ? null : _salvarConfig,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_salvando ? 'Salvando...' : 'Salvar regras do caixa'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _ConfigCard(
            titulo: 'Usuarios e Permissoes',
            descricao: 'Controle de acesso para caixa, vendedor e administrador.',
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup e Dados',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Crie backup completo dos dados locais da aplicacao e acesse a pasta do banco.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _backupEmAndamento ? null : _criarBackupDados,
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(
                        _backupEmAndamento ? 'Criando backup...' : 'Criar backup agora',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _abrirPastaDados,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Abrir pasta de dados'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _restauracaoEmAndamento || _backupEmAndamento
                          ? null
                          : _restaurarBackupDados,
                      icon: const Icon(Icons.restore_outlined),
                      label: Text(
                        _restauracaoEmAndamento
                            ? 'Restaurando backup...'
                            : 'Restaurar backup',
                      ),
                    ),
                  ),
                  if (_ultimoBackupPath.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ultimo backup: $_ultimoBackupPath',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({required this.titulo, required this.descricao});

  final String titulo;
  final String descricao;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: Text(titulo),
        subtitle: Text(descricao),
      ),
    );
  }
}
