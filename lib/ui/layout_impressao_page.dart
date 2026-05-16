import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../model/config_layout_impressao.dart';
import '../services/cupom_layout_preview_pdf.dart';

class LayoutImpressaoPage extends StatefulWidget {
  const LayoutImpressaoPage({
    super.key,
    required this.appConfigRepository,
  });

  final AppConfigRepository appConfigRepository;

  @override
  State<LayoutImpressaoPage> createState() => _LayoutImpressaoPageState();
}

class _LayoutImpressaoPageState extends State<LayoutImpressaoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  LayoutImpressaoEmpresa _layout = LayoutImpressaoEmpresa.padrao();
  EmpresaConfig? _empresa;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresa = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _empresa = empresa;
      _layout = empresa.layoutImpressao;
      _carregando = false;
    });
  }

  ConfigLayoutImpressao get _layoutAtual =>
      _tabs.index == 0 ? _layout.cupom : _layout.orcamento;

  bool get _orcamento => _tabs.index == 1;

  void _patchLayout(ConfigLayoutImpressao Function(ConfigLayoutImpressao) patch) {
    final base = _layoutAtual;
    final novo = patch(base).copyWith(
      preset: LayoutImpressaoPreset.personalizado,
    );
    setState(() {
      if (_orcamento) {
        _layout = _layout.copyWith(orcamento: novo);
      } else {
        _layout = _layout.copyWith(cupom: novo);
      }
    });
  }

  Future<void> _salvar() async {
    final empresa = _empresa;
    if (empresa == null) return;
    setState(() => _salvando = true);
    try {
      await widget.appConfigRepository.salvarEmpresaConfig(
        empresa.copyWith(layoutImpressao: _layout),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Layout de impressao salvo.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _abrirPreview() async {
    final empresa = _empresa;
    if (empresa == null) return;
    final bytes = await CupomLayoutPreviewPdf.gerarBytes(
      empresa: empresa,
      layout: _layoutAtual,
      orcamento: _orcamento,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _orcamento
              ? 'Pre-visualizacao — Orcamento'
              : 'Pre-visualizacao — Cupom',
        ),
        content: SizedBox(
          width: 420,
          height: 560,
          child: PdfPreview(
            build: (_) async => bytes,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
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

  void _aplicarPreset(LayoutImpressaoPreset preset) {
    final novo = ConfigLayoutImpressao.fromPreset(
      preset,
      orcamento: _orcamento,
    );
    setState(() {
      if (_orcamento) {
        _layout = _layout.copyWith(orcamento: novo);
      } else {
        _layout = _layout.copyWith(cupom: novo);
      }
    });
  }

  void _restaurarPadrao() {
    setState(() {
      if (_orcamento) {
        _layout = _layout.copyWith(
          orcamento: ConfigLayoutImpressao.padraoOrcamento(),
        );
      } else {
        _layout = _layout.copyWith(cupom: ConfigLayoutImpressao.padraoCupom());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layout de impressao'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Cupom'),
            Tab(text: 'Orcamento'),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _painelOpcoes(),
                      _painelOpcoes(),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _restaurarPadrao,
                          child: const Text('Restaurar'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _abrirPreview,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Preview'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _salvando ? null : _salvar,
                            icon: _salvando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _painelOpcoes() {
    final l = _layoutAtual;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _campoDropdown<LayoutImpressaoPreset>(
              rotulo: 'Modelo rapido',
              value: l.preset == LayoutImpressaoPreset.personalizado
                  ? null
                  : l.preset,
              hint: l.preset == LayoutImpressaoPreset.personalizado
                  ? 'Personalizado'
                  : null,
              items: const [
                DropdownMenuItem(
                  value: LayoutImpressaoPreset.padrao,
                  child: Text('Padrao'),
                ),
                DropdownMenuItem(
                  value: LayoutImpressaoPreset.compacto,
                  child: Text('Compacto (menos papel)'),
                ),
                DropdownMenuItem(
                  value: LayoutImpressaoPreset.destaque,
                  child: Text('Destaque'),
                ),
              ],
              onChanged: (p) {
                if (p != null) _aplicarPreset(p);
              },
            ),
          ),
        ),
        _secao('Fontes', [
          _dropdownFamilia(l),
          _dropdownFonte(
            'Nome da loja',
            l.tamanhoNomeLoja,
            (c, v) => c.copyWith(tamanhoNomeLoja: v),
          ),
          _dropdownFonte(
            'Texto geral (cliente, venda)',
            l.tamanhoFonteCorpo,
            (c, v) => c.copyWith(tamanhoFonteCorpo: v),
          ),
          _dropdownFonte(
            'Itens',
            l.tamanhoFonteItens,
            (c, v) => c.copyWith(tamanhoFonteItens: v),
          ),
          _dropdownFonte(
            'Totais e pagamento',
            l.tamanhoFonteTotais,
            (c, v) => c.copyWith(tamanhoFonteTotais: v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Courier alinha melhor colunas de preco; Helvetica e a padrao.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
        _secao('Cabecalho', [
          _switch(
            'Exibir logo',
            l.exibirLogo,
            (c, v) => c.copyWith(exibirLogo: v),
          ),
          _switch(
            'Telefone',
            l.exibirTelefone,
            (c, v) => c.copyWith(exibirTelefone: v),
          ),
          _switch(
            'Endereco',
            l.exibirEndereco,
            (c, v) => c.copyWith(exibirEndereco: v),
          ),
          _texto(
            'Titulo (vazio = padrao)',
            l.tituloDocumento,
            (c, v) => c.copyWith(tituloDocumento: v),
          ),
          _switch(
            'Faixa com divisorias',
            l.faixaComDivisorias,
            (c, v) => c.copyWith(faixaComDivisorias: v),
          ),
          if (!_orcamento)
            _switch(
              'Destacar 2a via',
              l.destacarSegundaVia,
              (c, v) => c.copyWith(destacarSegundaVia: v),
            ),
        ]),
        _secao('Divisorias', [
          _dropdownComprimento(l),
          _switch(
            'Divisoria forte antes dos totais',
            l.divisoriaDestaqueAntesTotais,
            (c, v) => c.copyWith(divisoriaDestaqueAntesTotais: v),
          ),
          _switch(
            'Divisoria antes do rodape',
            l.divisoriaAntesRodape,
            (c, v) => c.copyWith(divisoriaAntesRodape: v),
          ),
        ]),
        _secao('Cliente / venda', [
          _switch(
            'Vendedor',
            l.exibirVendedor,
            (c, v) => c.copyWith(exibirVendedor: v),
          ),
          _switch(
            'Documento do cliente',
            l.exibirDocumentoCliente,
            (c, v) => c.copyWith(exibirDocumentoCliente: v),
          ),
          _switch(
            'Telefone do cliente',
            l.exibirTelefoneCliente,
            (c, v) => c.copyWith(exibirTelefoneCliente: v),
          ),
          _switch(
            'Entrega',
            l.exibirEntrega,
            (c, v) => c.copyWith(exibirEntrega: v),
          ),
          _switch(
            'Endereco de entrega',
            l.exibirEnderecoEntrega,
            (c, v) => c.copyWith(exibirEnderecoEntrega: v),
          ),
          if (_orcamento) ...[
            _switch(
              'Validade do orcamento',
              l.exibirValidadeOrcamento,
              (c, v) => c.copyWith(exibirValidadeOrcamento: v),
            ),
            _switch(
              'Observacao de entrega',
              l.exibirObservacaoEntrega,
              (c, v) => c.copyWith(exibirObservacaoEntrega: v),
            ),
          ],
        ]),
        _secao('Itens', [
          _switch(
            'Colunas esquerda-direita',
            l.colunasEsquerdaDireita,
            (c, v) => c.copyWith(colunasEsquerdaDireita: v),
          ),
          _switch(
            'Cabecalho DESCRICAO | VALOR',
            l.cabecalhoColunasItens,
            (c, v) => c.copyWith(cabecalhoColunasItens: v),
          ),
          _switch(
            'Linha qtd x preco',
            l.linhaQuantidadePreco,
            (c, v) => c.copyWith(linhaQuantidadePreco: v),
          ),
        ]),
        _secao('Totais e pagamento', [
          _switch(
            'Alinhar totais em colunas',
            l.alinharTotaisColunas,
            (c, v) => c.copyWith(alinharTotaisColunas: v),
          ),
          _switch(
            'Alinhar pagamento em colunas',
            l.alinharPagamentoColunas,
            (c, v) => c.copyWith(alinharPagamentoColunas: v),
          ),
          _switch(
            'Destacar TOTAL',
            l.destacarTotal,
            (c, v) => c.copyWith(destacarTotal: v),
          ),
          if (!_orcamento)
            _switch(
              'Destacar troco',
              l.destacarTroco,
              (c, v) => c.copyWith(destacarTroco: v),
            ),
        ]),
        Text(
          'Texto do rodape: Configuracoes > Impressao e PDF. '
          'Salvar aqui propaga o layout na rede (mesma config da loja).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _secao(String titulo, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// Dropdown com rotulo fixo acima (evita corte do label flutuante).
  Widget _campoDropdown<T>({
    required String rotulo,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            value: value,
            hint: hint != null ? Text(hint) : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: false,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(),
            ),
            items: items,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _switch(
    String label,
    bool value,
    ConfigLayoutImpressao Function(ConfigLayoutImpressao, bool) patch,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: (v) => _patchLayout((c) => patch(c, v)),
    );
  }

  Widget _dropdownFonte(
    String label,
    LayoutTamanhoFonte value,
    ConfigLayoutImpressao Function(ConfigLayoutImpressao, LayoutTamanhoFonte)
        patch,
  ) {
    return _campoDropdown<LayoutTamanhoFonte>(
      rotulo: label,
      value: value,
      items: const [
        DropdownMenuItem(value: LayoutTamanhoFonte.p, child: Text('Pequeno')),
        DropdownMenuItem(value: LayoutTamanhoFonte.m, child: Text('Medio')),
        DropdownMenuItem(value: LayoutTamanhoFonte.g, child: Text('Grande')),
      ],
      onChanged: (v) {
        if (v != null) _patchLayout((c) => patch(c, v));
      },
    );
  }

  Widget _dropdownFamilia(ConfigLayoutImpressao l) {
    return _campoDropdown<LayoutFamiliaFonte>(
      rotulo: 'Familia da fonte',
      value: l.familiaFonte,
      items: LayoutFamiliaFonte.values
          .map(
            (f) => DropdownMenuItem(
              value: f,
              child: Text(f.rotulo),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) {
          _patchLayout((c) => c.copyWith(familiaFonte: v));
        }
      },
    );
  }

  Widget _dropdownComprimento(ConfigLayoutImpressao l) {
    return _campoDropdown<LayoutComprimentoDivisoria>(
      rotulo: 'Largura das divisorias',
      value: l.comprimentoDivisoria,
      items: const [
        DropdownMenuItem(
          value: LayoutComprimentoDivisoria.curto,
          child: Text('Curto'),
        ),
        DropdownMenuItem(
          value: LayoutComprimentoDivisoria.medio,
          child: Text('Medio'),
        ),
        DropdownMenuItem(
          value: LayoutComprimentoDivisoria.longo,
          child: Text('Longo'),
        ),
      ],
      onChanged: (v) {
        if (v != null) {
          _patchLayout((c) => c.copyWith(comprimentoDivisoria: v));
        }
      },
    );
  }

  Widget _texto(
    String label,
    String value,
    ConfigLayoutImpressao Function(ConfigLayoutImpressao, String) patch,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('${_orcamento}_${label}_$value'),
            initialValue: value,
            decoration: const InputDecoration(
              hintText: 'Enter para aplicar',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onFieldSubmitted: (v) => _patchLayout((c) => patch(c, v)),
          ),
        ],
      ),
    );
  }
}
