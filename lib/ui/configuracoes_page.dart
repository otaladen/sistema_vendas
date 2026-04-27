import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

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
  final _configRepository = AppConfigRepository();
  String _modeloPdf = 'cupom';
  String _impressoraPadrao = '';
  String _logoPath = '';
  List<Printer> _impressoras = [];
  bool _salvando = false;
  bool _prefsEmpresaAplicadas = false;

  @override
  void initState() {
    super.initState();
    _carregarConfig();
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _pastaPadraoPdfController.dispose();
    _rodapeNotaController.dispose();
    _rodapeOrcamentoController.dispose();
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
      _modeloPdf = config.modeloPdf;
      _impressoraPadrao = config.impressoraPadrao;
      _logoPath = config.logoPath;
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

  @override
  Widget build(BuildContext context) {
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
          const _ConfigCard(
            titulo: 'Vendas e Orcamentos',
            descricao: 'Validade padrao do orcamento, regras de frete e entrega.',
          ),
          const SizedBox(height: 10),
          const _ConfigCard(
            titulo: 'Usuarios e Permissoes',
            descricao: 'Controle de acesso para caixa, vendedor e administrador.',
          ),
          const SizedBox(height: 10),
          const _ConfigCard(
            titulo: 'Backup e Dados',
            descricao: 'Rotina de backup e restauracao do banco local.',
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
