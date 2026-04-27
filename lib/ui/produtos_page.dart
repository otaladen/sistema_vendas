import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../data/produto_repository.dart';
import '../model/produto.dart';
import '../services/produto_imagem_service.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  static const List<String> _unidades = ['UN', 'M', 'M2', 'M3', 'KG', 'SC', 'CX', 'LT'];
  static const String _categoriaOutros = 'Outros';
  static const Map<String, List<String>> _categoriasMateriaisConstrucao = {
    'Cimento e Argamassas': ['Cimento', 'Argamassa', 'Rejunte', 'Cal'],
    'Tintas e Acessorios': ['Tinta Acrilica', 'Tinta Esmalte', 'Selador', 'Verniz', 'Rolo e Pincel'],
    'Hidraulica': ['Tubos e Conexoes', 'Registros', 'Torneiras', 'Caixa d\'agua', 'Sifoes e Valvulas'],
    'Eletrica': ['Fios e Cabos', 'Disjuntores', 'Tomadas e Interruptores', 'Quadro de Distribuicao', 'Iluminacao'],
    'Ferragens': ['Parafusos e Buchas', 'Pregos', 'Dobradiças', 'Fechaduras', 'Correntes e Cabos de Aco'],
    'Madeiras e Chapas': ['Compensado', 'MDF', 'OSB', 'Vigas e Ripas', 'Portas e Batentes'],
    'Pisos e Revestimentos': ['Piso Ceramico', 'Porcelanato', 'Revestimento de Parede', 'Rodape', 'Pastilha'],
    'Ferramentas': ['Manuais', 'Eletricas', 'Medicao', 'EPIs', 'Acessorios de Corte'],
    _categoriaOutros: [],
  };

  final _codigoInternoController = TextEditingController();
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _marcaController = TextEditingController();
  final _fornecedorController = TextEditingController();
  final _fabricanteController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _ncmController = TextEditingController();
  final _localizacaoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _preco1Controller = TextEditingController();
  final _preco2Controller = TextEditingController();
  final _preco3Controller = TextEditingController();
  final _estoqueController = TextEditingController();
  final _quantidadeMinimaController = TextEditingController();
  final _subcategoriaLivreController = TextEditingController();
  String _unidadeSelecionada = 'UN';
  String? _categoriaSelecionada;
  String? _subcategoriaSelecionada;
  int? _produtoEmEdicaoId;
  bool _gerarSkuAutomatico = true;
  final _formKey = GlobalKey<FormState>();
  bool _tentouSalvar = false;
  late final ProdutoImagemService _produtoImagemService;
  String _fotoPathAtual = '';
  String? _fotoOrigemLocalPath;
  bool _fotoFoiRemovida = false;
  final ScrollController _scrollController = ScrollController();

  String _status = '';
  bool _statusEhErro = false;
  final NumberFormat _moedaBrFormatter = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _produtoImagemService = ProdutoImagemService(
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
  }

  @override
  void dispose() {
    _codigoInternoController.dispose();
    _nomeController.dispose();
    _descricaoController.dispose();
    _marcaController.dispose();
    _fornecedorController.dispose();
    _fabricanteController.dispose();
    _codigoBarrasController.dispose();
    _ncmController.dispose();
    _localizacaoController.dispose();
    _precoCustoController.dispose();
    _preco1Controller.dispose();
    _preco2Controller.dispose();
    _preco3Controller.dispose();
    _estoqueController.dispose();
    _quantidadeMinimaController.dispose();
    _subcategoriaLivreController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _gerarSkuAutomaticamente() {
    return 'SKU-${DateTime.now().millisecondsSinceEpoch}';
  }

  bool _skuJaExiste(String skuNormalizado) {
    final produtos = widget.produtoRepository.listarTodos();
    for (final produto in produtos) {
      final mesmoSku = produto.codigoInterno.trim().toLowerCase() == skuNormalizado;
      final emEdicao = _produtoEmEdicaoId != null && produto.id == _produtoEmEdicaoId;
      if (mesmoSku && !emEdicao) {
        return true;
      }
    }
    return false;
  }

  bool _temDadosNoFormulario() {
    final controllers = [
      _codigoInternoController,
      _nomeController,
      _descricaoController,
      _marcaController,
      _fornecedorController,
      _fabricanteController,
      _codigoBarrasController,
      _ncmController,
      _localizacaoController,
      _precoCustoController,
      _preco1Controller,
      _preco2Controller,
      _preco3Controller,
      _estoqueController,
      _quantidadeMinimaController,
    ];
    final existeTexto = controllers.any((controller) => controller.text.trim().isNotEmpty);
    return existeTexto ||
        _produtoEmEdicaoId != null ||
        _unidadeSelecionada != 'UN' ||
        _categoriaSelecionada != null ||
        _subcategoriaSelecionada != null ||
        _fotoPathAtual.trim().isNotEmpty ||
        (_fotoOrigemLocalPath?.trim().isNotEmpty ?? false) ||
        _subcategoriaLivreController.text.trim().isNotEmpty;
  }

  String? _fotoPreviewPath() {
    if (_fotoOrigemLocalPath != null && _fotoOrigemLocalPath!.trim().isNotEmpty) {
      return _fotoOrigemLocalPath;
    }
    if (_fotoPathAtual.trim().isNotEmpty) {
      return _fotoPathAtual;
    }
    return null;
  }

  String _normalizarNomeProduto(String nome) {
    final texto = nome.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (texto.isEmpty) {
      return '';
    }
    return texto
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .map((parte) {
          final inicial = parte[0].toUpperCase();
          final restante = parte.length > 1 ? parte.substring(1).toLowerCase() : '';
          return '$inicial$restante';
        })
        .join(' ');
  }

  void _definirStatus(String mensagem, {required bool erro}) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    setState(() {
      _status = mensagem;
      _statusEhErro = erro;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro
            ? semantic?.errorFg ?? Colors.red.shade700
            : semantic?.successFg ?? Colors.green.shade700,
      ),
    );
  }

  void _resetarFormulario() {
    setState(() {
      _codigoInternoController.clear();
      _nomeController.clear();
      _descricaoController.clear();
      _marcaController.clear();
      _fornecedorController.clear();
      _fabricanteController.clear();
      _codigoBarrasController.clear();
      _ncmController.clear();
      _localizacaoController.clear();
      _precoCustoController.clear();
      _preco1Controller.clear();
      _preco2Controller.clear();
      _preco3Controller.clear();
      _estoqueController.clear();
      _quantidadeMinimaController.clear();
      _subcategoriaLivreController.clear();
      _unidadeSelecionada = 'UN';
      _categoriaSelecionada = null;
      _subcategoriaSelecionada = null;
      _produtoEmEdicaoId = null;
      _gerarSkuAutomatico = true;
      _tentouSalvar = false;
      _fotoPathAtual = '';
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _importarFotoProduto() async {
    final pathSelecionado = await _produtoImagemService.selecionarImagemLocal();
    if (pathSelecionado == null) {
      return;
    }
    setState(() {
      _fotoOrigemLocalPath = pathSelecionado;
      _fotoFoiRemovida = false;
    });
  }

  void _removerFotoProduto() {
    setState(() {
      _fotoOrigemLocalPath = null;
      if (_fotoPathAtual.trim().isNotEmpty) {
        _fotoFoiRemovida = true;
      }
      _fotoPathAtual = '';
    });
  }

  Future<void> _limparFormularioComConfirmacao() async {
    if (!_temDadosNoFormulario()) {
      _resetarFormulario();
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Limpar formulario'),
          content: const Text('Existem dados preenchidos. Deseja limpar os campos?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Limpar'),
            ),
          ],
        );
      },
    );
    if (confirmar == true) {
      _resetarFormulario();
      _definirStatus('Formulario limpo com sucesso.', erro: false);
    }
  }

  double _margemCalculadaPorController(TextEditingController precoController) {
    final custo = _parseValorMonetario(_precoCustoController.text) ?? 0;
    final venda = _parseValorMonetario(precoController.text) ?? 0;
    if (venda <= 0) {
      return 0;
    }
    return ((venda - custo) / venda) * 100;
  }

  double _markupCalculadoPorController(TextEditingController precoController) {
    final custo = _parseValorMonetario(_precoCustoController.text) ?? 0;
    final venda = _parseValorMonetario(precoController.text) ?? 0;
    if (custo <= 0) {
      return 0;
    }
    return ((venda - custo) / custo) * 100;
  }

  String _normalizarUnidade(String? unidade) {
    if (unidade == null || unidade.trim().isEmpty) {
      return 'UN';
    }
    return _unidades.contains(unidade) ? unidade : 'UN';
  }

  double? _parseValorMonetario(String texto) {
    final valor = texto.trim();
    if (valor.isEmpty) {
      return null;
    }
    final semPontos = valor.replaceAll('.', '');
    final normalizado = semPontos.replaceAll(',', '.');
    return double.tryParse(normalizado);
  }

  String _formatarValorMonetario(double valor) {
    return _moedaBrFormatter.format(valor);
  }

  String? _validarSku(String? value) {
    if (_gerarSkuAutomatico) {
      return null;
    }
    final sku = (value ?? '').trim();
    if (sku.isEmpty) {
      return 'Informe o SKU ou habilite geracao automatica.';
    }
    if (_skuJaExiste(sku.toLowerCase())) {
      return 'SKU ja cadastrado.';
    }
    return null;
  }

  String? _validarNome(String? value) {
    final nome = (value ?? '').trim();
    if (nome.isEmpty) {
      return 'Nome do produto e obrigatorio.';
    }
    return null;
  }

  String? _validarCategoria(String? value) {
    if (_categoriaSelecionada == null || _categoriaSelecionada!.trim().isEmpty) {
      return 'Categoria e obrigatoria.';
    }
    return null;
  }

  String? _validarSubcategoria(String? value) {
    if (_categoriaSelecionada == null) {
      return 'Escolha uma categoria primeiro.';
    }
    if (_categoriaSelecionada == _categoriaOutros) {
      if (_subcategoriaLivreController.text.trim().isEmpty) {
        return 'Informe a subcategoria personalizada.';
      }
      return null;
    }
    if (_subcategoriaSelecionada == null || _subcategoriaSelecionada!.trim().isEmpty) {
      return 'Subcategoria obrigatoria.';
    }
    final subcategorias = _categoriasMateriaisConstrucao[_categoriaSelecionada] ?? [];
    if (!subcategorias.contains(_subcategoriaSelecionada)) {
      return 'Subcategoria invalida para a categoria.';
    }
    return null;
  }

  String? _validarPrecoCusto(String? value) {
    final texto = (value ?? '').trim();
    final precoCusto = _parseValorMonetario(texto);
    if (precoCusto == null) {
      return 'Preco de custo invalido.';
    }
    if (precoCusto < 0) {
      return 'Preco de custo nao pode ser negativo.';
    }
    return null;
  }

  String? _validarPrecoTabela(String? value) {
    final texto = (value ?? '').trim();
    final preco = _parseValorMonetario(texto);
    if (preco == null || preco <= 0) {
      return 'Preco deve ser maior que zero.';
    }
    return null;
  }

  Future<void> _salvarProduto() async {
    setState(() {
      _tentouSalvar = true;
    });
    final formValido = _formKey.currentState?.validate() ?? false;
    if (!formValido) {
      _definirStatus('Revise os campos destacados em vermelho.', erro: true);
      return;
    }

    final codigoInternoDigitado = _codigoInternoController.text.trim();
    final nomePadrao = _normalizarNomeProduto(_nomeController.text);
    final descricao = _descricaoController.text.trim();
    final categoria = _categoriaSelecionada?.trim() ?? '';
    final subcategoria = _categoriaSelecionada == _categoriaOutros
        ? _subcategoriaLivreController.text.trim()
        : (_subcategoriaSelecionada?.trim() ?? '');
    final marca = _marcaController.text.trim();
    final fornecedor = _fornecedorController.text.trim();
    final fabricante = _fabricanteController.text.trim();
    final codigoBarras = _codigoBarrasController.text.trim();
    final ncm = _ncmController.text.trim();
    final localizacao = _localizacaoController.text.trim();
    final precoCusto = _parseValorMonetario(_precoCustoController.text);
    final preco1 = _parseValorMonetario(_preco1Controller.text);
    final preco2 = _parseValorMonetario(_preco2Controller.text);
    final preco3 = _parseValorMonetario(_preco3Controller.text);
    final estoque = int.tryParse(_estoqueController.text) ?? 0;
    final quantidadeMinima = int.tryParse(_quantidadeMinimaController.text) ?? 0;
    final codigoInternoFinal = _gerarSkuAutomatico
        ? _gerarSkuAutomaticamente()
        : codigoInternoDigitado;

    _nomeController.text = nomePadrao;

    final produtoExistente = _produtoEmEdicaoId == null
        ? null
        : widget.produtoRepository.obterPorId(_produtoEmEdicaoId!);
    final fotoPathExistente = produtoExistente?.fotoPath ?? '';
    final identificadorFoto = codigoInternoFinal.isNotEmpty
        ? codigoInternoFinal
        : 'produto_${DateTime.now().millisecondsSinceEpoch}';
    var fotoPathFinal = fotoPathExistente;

    if (_fotoOrigemLocalPath != null && _fotoOrigemLocalPath!.trim().isNotEmpty) {
      final fotoProcessada = await _produtoImagemService.processarESalvarImagemProduto(
        sourceImagePath: _fotoOrigemLocalPath!,
        productIdentifier: identificadorFoto,
      );
      if (fotoProcessada == null) {
        _definirStatus('Nao foi possivel processar a foto selecionada.', erro: true);
        return;
      }
      if (fotoPathExistente.trim().isNotEmpty && fotoPathExistente != fotoProcessada) {
        await _produtoImagemService.removerImagemProduto(fotoPathExistente);
      }
      fotoPathFinal = fotoProcessada;
    } else if (_fotoFoiRemovida && fotoPathExistente.trim().isNotEmpty) {
      await _produtoImagemService.removerImagemProduto(fotoPathExistente);
      fotoPathFinal = '';
    }

    final produto = Produto(
      id: produtoExistente?.id ?? 0,
      codigoInterno: codigoInternoFinal,
      nome: nomePadrao,
      descricao: descricao,
      unidade: _normalizarUnidade(_unidadeSelecionada),
      categoria: categoria,
      subcategoria: subcategoria,
      marca: marca,
      fornecedor: fornecedor,
      fabricante: fabricante,
      codigoBarras: codigoBarras,
      fotoPath: fotoPathFinal,
      localizacao: localizacao,
      ncm: ncm,
      estoque: estoque,
      quantidadeMinima: quantidadeMinima,
      precoCusto: precoCusto!,
      preco1: preco1!,
      preco2: preco2!,
      preco3: preco3!,
      precoVenda: preco1,
      criadoEm: produtoExistente?.criadoEm,
    );
    final estavaEditando = _produtoEmEdicaoId != null;
    widget.produtoRepository.salvar(produto);
    _resetarFormulario();
    _definirStatus(
      !estavaEditando
          ? 'Produto incluido com sucesso.'
          : 'Produto atualizado com sucesso.',
      erro: false,
    );
  }

  void _editarProdutoNoCabecalho(Produto produto) {
    setState(() {
      _produtoEmEdicaoId = produto.id;
      _codigoInternoController.text = produto.codigoInterno;
      _nomeController.text = produto.nome;
      _descricaoController.text = produto.descricao;
      if (_categoriasMateriaisConstrucao.containsKey(produto.categoria)) {
        _categoriaSelecionada = produto.categoria;
        if (produto.categoria == _categoriaOutros) {
          _subcategoriaSelecionada = null;
          _subcategoriaLivreController.text = produto.subcategoria;
        } else {
          _subcategoriaLivreController.clear();
          final subcategorias = _categoriasMateriaisConstrucao[produto.categoria] ?? [];
          _subcategoriaSelecionada = subcategorias.contains(produto.subcategoria)
              ? produto.subcategoria
              : null;
        }
      } else {
        _categoriaSelecionada = null;
        _subcategoriaSelecionada = null;
        _subcategoriaLivreController.clear();
      }
      _marcaController.text = produto.marca;
      _fornecedorController.text = produto.fornecedor;
      _fabricanteController.text = produto.fabricante;
      _codigoBarrasController.text = produto.codigoBarras;
      _fotoPathAtual = produto.fotoPath;
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
      _ncmController.text = produto.ncm;
      _localizacaoController.text = produto.localizacao;
      _precoCustoController.text = _formatarValorMonetario(produto.precoCusto);
      _preco1Controller.text = _formatarValorMonetario(
        produto.preco1 > 0 ? produto.preco1 : produto.precoVenda,
      );
      _preco2Controller.text = _formatarValorMonetario(
        produto.preco2 > 0 ? produto.preco2 : produto.precoVenda,
      );
      _preco3Controller.text = _formatarValorMonetario(
        produto.preco3 > 0 ? produto.preco3 : produto.precoVenda,
      );
      _estoqueController.text = produto.estoque.toString();
      _quantidadeMinimaController.text = produto.quantidadeMinima.toString();
      _unidadeSelecionada = _normalizarUnidade(produto.unidade);
      _status = 'Editando produto: ${produto.nome}';
      _statusEhErro = false;
      _gerarSkuAutomatico = false;
    });
  }

  Future<void> _abrirPesquisaProduto() async {
    final produtosBase = widget.produtoRepository.listarTodos();
    final pesquisaController = TextEditingController();
    List<Produto> resultados = produtosBase;

    final produtoSelecionado = await showDialog<Produto>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pesquisar produto'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nome, SKU, marca, fornecedor...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        setDialogState(() {
                          resultados = produtosBase.where((produto) {
                            final campos = [
                              produto.nome,
                              produto.codigoInterno,
                              produto.categoria,
                              produto.subcategoria,
                              produto.marca,
                              produto.fornecedor,
                              produto.codigoBarras,
                            ].map((e) => e.toLowerCase());
                            return campos.any((campo) => campo.contains(termo));
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum produto encontrado.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final produto = resultados[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(produto.nome),
                                  subtitle: Text(
                                    'SKU: ${produto.codigoInterno} | Categoria: ${produto.categoria.isEmpty ? '-' : produto.categoria}',
                                  ),
                                  onTap: () => Navigator.pop(context, produto),
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
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );

    pesquisaController.dispose();

    if (produtoSelecionado != null) {
      _editarProdutoNoCabecalho(produtoSelecionado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margem1 = _margemCalculadaPorController(_preco1Controller);
    final margem2 = _margemCalculadaPorController(_preco2Controller);
    final margem3 = _margemCalculadaPorController(_preco3Controller);
    final markup1 = _markupCalculadoPorController(_preco1Controller);
    final markup2 = _markupCalculadoPorController(_preco2Controller);
    final markup3 = _markupCalculadoPorController(_preco3Controller);
    final semantic = theme.extension<AppSemanticColors>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Produtos')),
      body: Form(
        key: _formKey,
        autovalidateMode: _tentouSalvar
            ? AutovalidateMode.always
            : AutovalidateMode.disabled,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: RawScrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 10,
            radius: const Radius.circular(8),
            crossAxisMargin: 2,
            mainAxisMargin: 4,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(right: 10),
              children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 30,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cadastro de Produtos',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _produtoEmEdicaoId == null
                              ? 'Cadastre os dados do item com foto e precos.'
                              : 'Modo edicao ativo: revise e salve as alteracoes.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _abrirPesquisaProduto,
                icon: const Icon(Icons.search),
                label: const Text('Pesquisar produto'),
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionTitle(context, 'Identificacao', Icons.qr_code_2_outlined),
            TextFormField(
              controller: _codigoInternoController,
              enabled: !_gerarSkuAutomatico,
              validator: _validarSku,
              decoration: const InputDecoration(
                labelText: 'Codigo interno (SKU)',
                helperText: 'Use manual ou geracao automatica',
              ),
            ),
            CheckboxListTile(
              value: _gerarSkuAutomatico,
              onChanged: (value) {
                setState(() {
                  _gerarSkuAutomatico = value ?? true;
                  if (_gerarSkuAutomatico) {
                    _codigoInternoController.clear();
                  }
                });
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('Gerar SKU automaticamente'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importarFotoProduto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(_fotoPreviewPath() == null ? 'Importar foto' : 'Trocar foto'),
                  ),
                ),
                if (_fotoPreviewPath() != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _removerFotoProduto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover'),
                  ),
                ],
              ],
            ),
            if (_fotoPreviewPath() != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: Image.file(
                    File(_fotoPreviewPath()!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: Colors.grey.shade100,
                        child: const Text('Nao foi possivel carregar a imagem.'),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _nomeController,
              validator: _validarNome,
              decoration: const InputDecoration(
                labelText: 'Nome do produto',
                helperText: 'Padrao sugerido: Nome + Marca + Volume (ex: Tinta Coral 18L)',
              ),
            ),
            const SizedBox(height: 8),
            _buildSectionTitle(context, 'Classificacao e dados tecnicos', Icons.category_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _categoriaSelecionada,
                    validator: _validarCategoria,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    hint: const Text('Selecione'),
                    items: _categoriasMateriaisConstrucao.keys
                        .map(
                          (categoria) => DropdownMenuItem<String>(
                            value: categoria,
                            child: Text(categoria),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _categoriaSelecionada = value;
                        _subcategoriaSelecionada = null;
                        _subcategoriaLivreController.clear();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('subcategoria_${_categoriaSelecionada ?? 'vazio'}_${_subcategoriaSelecionada ?? 'vazio'}'),
                    initialValue: _subcategoriaSelecionada,
                    validator: _validarSubcategoria,
                    decoration: const InputDecoration(labelText: 'Subcategoria'),
                    hint: const Text('Selecione'),
                    items: (_categoriasMateriaisConstrucao[_categoriaSelecionada] ?? [])
                        .map(
                          (subcategoria) => DropdownMenuItem<String>(
                            value: subcategoria,
                            child: Text(subcategoria),
                          ),
                        )
                        .toList(),
                    onChanged: _categoriaSelecionada == null || _categoriaSelecionada == _categoriaOutros
                        ? null
                        : (value) {
                            setState(() {
                              _subcategoriaSelecionada = value;
                            });
                          },
                  ),
                ),
              ],
            ),
            if (_categoriaSelecionada == _categoriaOutros) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _subcategoriaLivreController,
                validator: _validarSubcategoria,
                decoration: const InputDecoration(
                  labelText: 'Subcategoria personalizada',
                  helperText: 'Digite a subcategoria para itens fora do padrao',
                ),
              ),
            ],
            const SizedBox(height: 8),
            _buildSectionTitle(context, 'Unidade e codigos', Icons.straighten_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unidadeSelecionada,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: const [
                      DropdownMenuItem(value: 'UN', child: Text('UN - Unidade')),
                      DropdownMenuItem(value: 'M', child: Text('M - Metro')),
                      DropdownMenuItem(value: 'M2', child: Text('M2 - Metro quadrado')),
                      DropdownMenuItem(value: 'M3', child: Text('M3 - Metro cubico')),
                      DropdownMenuItem(value: 'KG', child: Text('KG - Quilograma')),
                      DropdownMenuItem(value: 'SC', child: Text('SC - Saco')),
                      DropdownMenuItem(value: 'CX', child: Text('CX - Caixa')),
                      DropdownMenuItem(value: 'LT', child: Text('LT - Litro')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _unidadeSelecionada = _normalizarUnidade(value);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _codigoBarrasController,
                    decoration: const InputDecoration(labelText: 'Codigo de barras'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSectionTitle(context, 'Dados comerciais e tecnicos', Icons.storefront_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _marcaController,
                    decoration: const InputDecoration(labelText: 'Marca'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fabricanteController,
                    decoration: const InputDecoration(labelText: 'Fabricante'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fornecedorController,
                    decoration: const InputDecoration(labelText: 'Fornecedor'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _localizacaoController,
                    decoration: const InputDecoration(labelText: 'Localizacao no deposito'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ncmController,
                    decoration: const InputDecoration(labelText: 'NCM'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descricaoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descricao tecnica',
                helperText: 'Use para orientar o vendedor: beneficios, aplicacao e diferenciais.',
              ),
            ),
            const SizedBox(height: 8),
            _buildSectionTitle(context, 'Precos e margem', Icons.price_change_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _precoCustoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoCusto,
                    decoration: const InputDecoration(
                      labelText: 'Preco de custo',
                      helperText: 'Nao pode ser negativo',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _preco1Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'Preco 1'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _preco2Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'Preco 2'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _preco3Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'Preco 3'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preco 1 -> Markup: ${markup1.toStringAsFixed(2)}% | Margem: ${margem1.toStringAsFixed(2)}%\n'
                'Preco 2 -> Markup: ${markup2.toStringAsFixed(2)}% | Margem: ${margem2.toStringAsFixed(2)}%\n'
                'Preco 3 -> Markup: ${markup3.toStringAsFixed(2)}% | Margem: ${margem3.toStringAsFixed(2)}%',
              ),
            ),
            const SizedBox(height: 8),
            _buildSectionTitle(context, 'Estoque', Icons.warehouse_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _estoqueController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantidade em estoque'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _quantidadeMinimaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantidade minima'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _salvarProduto,
                    child: Text(_produtoEmEdicaoId == null ? 'Incluir' : 'Salvar edicao'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _limparFormularioComConfirmacao,
                    child: Text(_produtoEmEdicaoId == null ? 'Limpar' : 'Cancelar edicao'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _statusEhErro
                      ? semantic?.errorBg ?? const Color(0xFFFDECEC)
                      : semantic?.successBg ?? const Color(0xFFEAF8EF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _statusEhErro
                        ? semantic?.errorBorder ?? const Color(0xFFF1A3A3)
                        : semantic?.successBorder ?? const Color(0xFF8FD1A8),
                  ),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _statusEhErro
                        ? semantic?.errorFg ?? const Color(0xFF9B1C1C)
                        : semantic?.successFg ?? const Color(0xFF166534),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class RealInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final apenasNumeros = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (apenasNumeros.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final valorCentavos = int.parse(apenasNumeros);
    final valor = valorCentavos / 100;
    final formatador = NumberFormat('#,##0.00', 'pt_BR');
    final textoFormatado = formatador.format(valor);

    return TextEditingValue(
      text: textoFormatado,
      selection: TextSelection.collapsed(offset: textoFormatado.length),
    );
  }
}
