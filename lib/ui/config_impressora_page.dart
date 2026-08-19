import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_config_repository.dart';
import '../services/esc_pos_printer_service.dart';
import '../services/gaveta_esc_pos_service.dart';
import '../services/print_service.dart';

/// Tela: modo PDF (A4/orçamentos) vs ESC/POS termico + gaveta.
class ConfigImpressoraPage extends StatefulWidget {
  const ConfigImpressoraPage({
    super.key,
    required this.printService,
    required this.appConfigRepository,
  });

  final PrintService printService;
  final AppConfigRepository appConfigRepository;

  @override
  State<ConfigImpressoraPage> createState() => _ConfigImpressoraPageState();
}

class _ConfigImpressoraPageState extends State<ConfigImpressoraPage> {
  List<String> _nomesImpressoras = const [];
  String? _selecionada;
  bool _carregando = true;
  String? _erroLista;
  bool _abrirGavetaAutomatica = true;
  int _gavetaPino = 0;
  bool _salvando = false;

  String _modoImpressaoBalcao = 'pdf';
  String _escPosLargura = '80';
  String _escPosDestino = 'windows';
  final _escPosHostCtrl = TextEditingController();
  final _escPosPortaTcpCtrl = TextEditingController(text: '9100');
  final _escPosPortaComCtrl = TextEditingController();

  late final GavetaEscPosService _gavetaService =
      GavetaEscPosService(widget.appConfigRepository);
  late final EscPosPrinterService _escPosService =
      EscPosPrinterService(widget.appConfigRepository);

  static const _erpGap16 = 16.0;
  static const _erpGap24 = 24.0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _escPosHostCtrl.dispose();
    _escPosPortaTcpCtrl.dispose();
    _escPosPortaComCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroLista = null;
    });
    try {
      final impressoras =
          await widget.printService.listarImpressorasDisponiveis();
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      final salva = config.impressoraPadrao.trim();
      final nomes = impressoras.map((p) => p.name).toList();
      if (!mounted) return;
      setState(() {
        _nomesImpressoras = nomes;
        if (salva.isEmpty) {
          _selecionada = null;
        } else if (nomes.contains(salva)) {
          _selecionada = salva;
        } else {
          _selecionada = salva; // mantem nome mesmo se lista vazia / offline
        }
        _abrirGavetaAutomatica = config.abrirGavetaAutomatica;
        _gavetaPino = config.gavetaPino.clamp(0, 1);
        _modoImpressaoBalcao =
            config.modoImpressaoBalcao == 'escpos' ? 'escpos' : 'pdf';
        _escPosLargura = config.escPosLargura == '58' ? '58' : '80';
        _escPosDestino = config.escPosDestino;
        _escPosHostCtrl.text = config.escPosHost;
        _escPosPortaTcpCtrl.text = '${config.escPosPortaTcp}';
        _escPosPortaComCtrl.text = config.escPosPortaCom;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroLista = 'Falha ao listar impressoras: $e';
      });
    }
  }

  Future<void> _salvarTudo() async {
    setState(() => _salvando = true);
    try {
      final nome = (_selecionada ?? '').trim();
      final c = await widget.appConfigRepository.carregarEmpresaConfig();
      final portaTcp = int.tryParse(_escPosPortaTcpCtrl.text.trim()) ?? 9100;
      await widget.appConfigRepository.salvarEmpresaConfig(
        c.copyWith(
          impressoraPadrao: nome,
          abrirGavetaAutomatica: _abrirGavetaAutomatica,
          gavetaPino: _gavetaPino,
          modoImpressaoBalcao: _modoImpressaoBalcao,
          escPosLargura: _escPosLargura,
          escPosDestino: _escPosDestino,
          escPosHost: _escPosHostCtrl.text.trim(),
          escPosPortaTcp: portaTcp.clamp(1, 65535),
          escPosPortaCom: _escPosPortaComCtrl.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao de impressao salva.')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _imprimirTestePdf() async {
    try {
      final r = await widget.printService.imprimirTeste();
      if (!mounted) return;
      final msg = switch (r) {
        PrintTestOutcome.sentToDefaultPrinter =>
          'Teste PDF enviado para a impressora configurada.',
        PrintTestOutcome.usedSystemDialog =>
          'Aberto o dialogo do Windows Print Manager.',
        PrintTestOutcome.noSavedPrinter =>
          'Nenhuma impressora salva — use o dialogo do sistema.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao imprimir teste: $e')));
    }
  }

  Future<void> _imprimirTesteEscPos() async {
    await _salvarTudo();
    final r = await _escPosService.imprimirTeste();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.mensagem)));
  }

  Future<void> _testarGaveta() async {
    await _salvarTudo();
    final r = await _gavetaService.testarAbrir();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.mensagem)),
    );
  }

  Widget _cardModo(ThemeData theme, ColorScheme cs) {
    return _cardShell(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Modo de impressao do balcao',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          Text(
            'PDF / Windows Print Manager e ideal para orcamentos A4. '
            'ESC/POS termico envia bytes direto (USB/COM ou IP:9100) com corte e gaveta.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.68),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo PDF / Windows Print Manager'),
            subtitle: const Text('Orcamentos A4 e cupom via driver do Windows'),
            value: 'pdf',
            groupValue: _modoImpressaoBalcao,
            onChanged: _carregando
                ? null
                : (v) {
                    if (v != null) setState(() => _modoImpressaoBalcao = v);
                  },
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo ESC/POS termico direto'),
            subtitle: const Text('Cupom 80mm/58mm via USB, COM ou rede (9100)'),
            value: 'escpos',
            groupValue: _modoImpressaoBalcao,
            onChanged: _carregando
                ? null
                : (v) {
                    if (v != null) setState(() => _modoImpressaoBalcao = v);
                  },
          ),
        ],
      ),
    );
  }

  Widget _cardPdf(ThemeData theme, ColorScheme cs) {
    return _cardShell(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.print_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Impressora Windows (PDF / fila)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          if (_erroLista != null)
            Padding(
              padding: const EdgeInsets.only(bottom: _erpGap16),
              child: Text(
                _erroLista!,
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            'Selecionar impressora',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _selecionada != null &&
                        (_nomesImpressoras.contains(_selecionada) ||
                            _selecionada!.isNotEmpty)
                    ? _selecionada
                    : null,
                hint: Text(
                  _nomesImpressoras.isEmpty
                      ? 'Nenhuma impressora detectada'
                      : 'Escolha uma impressora',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Nenhuma (dialogo ao imprimir)'),
                  ),
                  if (_selecionada != null &&
                      _selecionada!.isNotEmpty &&
                      !_nomesImpressoras.contains(_selecionada))
                    DropdownMenuItem<String?>(
                      value: _selecionada,
                      child: Text(
                        '${_selecionada!} (salva)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ..._nomesImpressoras.map(
                    (n) => DropdownMenuItem<String?>(
                      value: n,
                      child: Text(n, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selecionada = v),
              ),
            ),
          ),
          const SizedBox(height: _erpGap16),
          Wrap(
            spacing: _erpGap16,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Atualizar lista'),
              ),
              FilledButton.tonalIcon(
                onPressed: _imprimirTestePdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Teste PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardEscPos(ThemeData theme, ColorScheme cs) {
    return _cardShell(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'ESC/POS termico direto',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          Text(
            'Largura da bobina',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '80', label: Text('80 mm')),
              ButtonSegment(value: '58', label: Text('58 mm')),
            ],
            selected: {_escPosLargura},
            onSelectionChanged: (s) =>
                setState(() => _escPosLargura = s.first),
          ),
          const SizedBox(height: _erpGap16),
          Text(
            'Destino',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _escPosDestino,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'windows',
                child: Text('USB / fila Windows (RAW)'),
              ),
              DropdownMenuItem(
                value: 'rede',
                child: Text('Rede local (IP : 9100)'),
              ),
              DropdownMenuItem(
                value: 'com',
                child: Text('Porta serial COM'),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _escPosDestino = v);
            },
          ),
          const SizedBox(height: 12),
          if (_escPosDestino == 'windows')
            Text(
              'Use a impressora selecionada no card "Impressora Windows" acima '
              '(mesmo nome da termica USB).',
              style: theme.textTheme.bodySmall,
            ),
          if (_escPosDestino == 'rede') ...[
            TextField(
              controller: _escPosHostCtrl,
              decoration: const InputDecoration(
                labelText: 'IP da impressora',
                hintText: '192.168.0.50',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _escPosPortaTcpCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Porta TCP',
                hintText: '9100',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_escPosDestino == 'com')
            TextField(
              controller: _escPosPortaComCtrl,
              decoration: const InputDecoration(
                labelText: 'Porta COM',
                hintText: 'COM3',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: _erpGap16),
          FilledButton.tonalIcon(
            onPressed: _imprimirTesteEscPos,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Teste ESC/POS (corte + gaveta)'),
          ),
        ],
      ),
    );
  }

  Widget _cardGaveta(ThemeData theme, ColorScheme cs) {
    final windows = Platform.isWindows;
    return _cardShell(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.point_of_sale_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Gaveta de dinheiro (ESC/POS)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Abrir gaveta automaticamente no caixa'),
            subtitle: const Text(
              'Tambem ao final do cupom ESC/POS (pulso + corte).',
            ),
            value: _abrirGavetaAutomatica,
            onChanged: !_carregando
                ? (v) => setState(() => _abrirGavetaAutomatica = v)
                : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _gavetaPino,
            decoration: const InputDecoration(
              labelText: 'Pino da gaveta',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Pino 0 (padrao Epson)')),
              DropdownMenuItem(value: 1, child: Text('Pino 1')),
            ],
            onChanged: !_carregando
                ? (v) {
                    if (v != null) setState(() => _gavetaPino = v);
                  }
                : null,
          ),
          const SizedBox(height: _erpGap16),
          FilledButton.tonalIcon(
            onPressed: windows || _escPosDestino == 'rede' ? _testarGaveta : null,
            icon: const Icon(Icons.open_in_browser_outlined),
            label: const Text('Testar gaveta'),
          ),
        ],
      ),
    );
  }

  Widget _cardShell(ColorScheme cs, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      padding: const EdgeInsets.all(_erpGap24),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impressora'),
        actions: [
          TextButton.icon(
            onPressed: _salvando ? null : _salvarTudo,
            icon: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(_erpGap24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cardModo(theme, cs),
                      const SizedBox(height: _erpGap24),
                      _cardPdf(theme, cs),
                      const SizedBox(height: _erpGap24),
                      _cardEscPos(theme, cs),
                      const SizedBox(height: _erpGap24),
                      _cardGaveta(theme, cs),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
