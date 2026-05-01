import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
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
    'Telhas e Cobertura': [
      'Telha Ceramica',
      'Telha Fibrocimento',
      'Telha Metalica',
      'Telha PVC',
      'Cumeeira',
      'Rufos e Calhas',
      'Manta Termica',
      'Parafuso para Telha',
    ],
    'Estrutural e Alvenaria': [
      'Tijolo',
      'Bloco de Concreto',
      'Canaleta',
      'Areia',
      'Brita',
      'Pedra',
      'Aco para Construcao',
      'Vergalhao',
    ],
    'Tintas e Acessorios': ['Tinta Acrilica', 'Tinta Esmalte', 'Selador', 'Verniz', 'Rolo e Pincel'],
    'Hidraulica': [
      'Tubos e Conexoes',
      'Registros',
      'Torneiras',
      'Caixa d\'agua',
      'Sifoes e Valvulas',
      'Bombas',
      'Irrigacao',
      'Acessorios para Banheiro',
    ],
    'Eletrica': [
      'Fios e Cabos',
      'Disjuntores',
      'Tomadas e Interruptores',
      'Quadro de Distribuicao',
      'Iluminacao',
      'Eletroduto',
      'Canaleta',
      'Luminaria LED',
    ],
    'Ferragens': [
      'Parafusos e Buchas',
      'Pregos',
      'Dobradiças',
      'Fechaduras',
      'Correntes e Cabos de Aco',
      'Abraçadeiras',
      'Chapas e Cantoneiras',
      'Fixadores',
    ],
    'Madeiras e Chapas': ['Compensado', 'MDF', 'OSB', 'Vigas e Ripas', 'Portas e Batentes'],
    'Pisos e Revestimentos': ['Piso Ceramico', 'Porcelanato', 'Revestimento de Parede', 'Rodape', 'Pastilha'],
    'Loucas e Metais': [
      'Vaso Sanitario',
      'Lavatório',
      'Cuba',
      'Torneira',
      'Chuveiro',
      'Misturador',
      'Assento Sanitario',
    ],
    'Impermeabilizacao e Quimicos': [
      'Impermeabilizante',
      'Vedante',
      'Silicone',
      'Espuma Expansiva',
      'Aditivo para Concreto',
      'Desmoldante',
    ],
    'Ferramentas': ['Manuais', 'Eletricas', 'Medicao', 'EPIs', 'Acessorios de Corte'],
    'Jardinagem e Externo': [
      'Mangueira',
      'Grama Sintetica',
      'Ferramentas de Jardim',
      'Vaso e Cachepot',
      'Pedrisco Decorativo',
    ],
    'Forros e Divisorias': [
      'Forro PVC',
      'Forro Gesso',
      'Perfil para Drywall',
      'Chapa Drywall',
      'Acessorios Drywall',
    ],
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
  final _custoMedioController = TextEditingController();
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
    _custoMedioController.dispose();
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
      _custoMedioController,
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
    const conectores = {
      'de',
      'da',
      'do',
      'das',
      'dos',
      'e',
      'em',
      'com',
      'para',
      'por',
    };
    const siglas = {
      'pvc',
      'uv',
      'led',
      'mdf',
      'osb',
      'ac',
      'cp',
      'kg',
      'g',
      'mg',
      'mm',
      'cm',
      'm',
      'm2',
      'm3',
      'l',
      'lt',
      'ml',
      'w',
      'v',
      'a',
      'un',
      'cx',
      'sc',
    };

    final tokens = texto.split(' ').where((parte) => parte.isNotEmpty).toList();
    final normalizados = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final tokenOriginal = tokens[i];
      final token = tokenOriginal.toLowerCase();
      if (siglas.contains(token)) {
        normalizados.add(token.toUpperCase());
        continue;
      }
      if (token.contains('/')) {
        final partes = token.split('/');
        final frac = partes
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .join('/');
        normalizados.add(frac);
        continue;
      }
      if (i > 0 && conectores.contains(token)) {
        normalizados.add(token);
        continue;
      }
      final inicial = token[0].toUpperCase();
      final restante = token.length > 1 ? token.substring(1).toLowerCase() : '';
      normalizados.add('$inicial$restante');
    }
    return normalizados.join(' ');
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
      _custoMedioController.clear();
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

  Future<void> _excluirProdutoEmEdicao() async {
    final produtoId = _produtoEmEdicaoId;
    if (produtoId == null) {
      _definirStatus('Selecione um produto para excluir.', erro: true);
      return;
    }
    final produto = widget.produtoRepository.obterPorId(produtoId);
    if (produto == null) {
      _definirStatus('Produto nao encontrado para exclusao.', erro: true);
      _resetarFormulario();
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir produto'),
          content: Text(
            'Deseja realmente excluir o produto "${produto.nome}"?\n'
            'Essa acao nao pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) return;

    final removido = widget.produtoRepository.remover(produtoId);
    if (!removido) {
      _definirStatus('Nao foi possivel excluir o produto.', erro: true);
      return;
    }
    if (produto.fotoPath.trim().isNotEmpty) {
      await _produtoImagemService.removerImagemProduto(produto.fotoPath);
    }
    _resetarFormulario();
    _definirStatus('Produto excluido com sucesso.', erro: false);
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
    var valor = texto.trim();
    if (valor.isEmpty) {
      return null;
    }
    valor = valor
        .replaceAll('\u00A0', '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp('r\$', caseSensitive: false), '');
    if (valor.isEmpty) {
      return null;
    }
    // Export Python/Paradox costuma usar ponto decimal (12.5, 0.99). Antes removiamos TODOS os pontos
    // pensando em milhar BR — isso quebrava esses valores e gerava fallback 0,01 em massa.
    final direto = double.tryParse(valor);
    if (direto != null) {
      return direto;
    }
    final limpo = valor.replaceAll(RegExp(r'[^\d.,+\-eE]'), '');
    if (limpo.isEmpty) {
      return null;
    }
    final ultVirg = limpo.lastIndexOf(',');
    final ultPonto = limpo.lastIndexOf('.');
    if (ultVirg > ultPonto) {
      final br = limpo.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(br);
    }
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  /// Quando [PrecoVenda] vem vazio no CSV (comum no TabEst), o sistema antigo as vezes
  /// guardava valores em [Obs] como texto, ex.: `MARCA 60,00 PDEDIDO 58,00`.
  /// Retorna o primeiro valor monetario plausivel encontrado da esquerda para a direita.
  double? _extrairPrecoVendaDeTextoLivre(String texto) {
    final raw = texto.trim();
    if (raw.isEmpty) {
      return null;
    }
    final re = RegExp(
      r'\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2}',
    );
    for (final m in re.allMatches(raw)) {
      final s = m.group(0);
      if (s == null) {
        continue;
      }
      final v = _parseValorMonetario(s);
      if (v != null && v > 0 && v < 1e7) {
        return v;
      }
    }
    // Ex.: "MARCA 60 PDEDIDO" sem centavos escritos
    final soNumeros = RegExp(r'\b(\d{2,6})\b');
    for (final m in soNumeros.allMatches(raw)) {
      final s = m.group(1);
      if (s == null) {
        continue;
      }
      final v = double.tryParse(s);
      if (v != null && v >= 10 && v <= 999999) {
        return v;
      }
    }
    return null;
  }

  /// Colunas que nao devem ser escolhidas pela heuristica de "preco de venda".
  Set<int> _indicesExcluidosHeuristicaPreco(List<String> headers) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    final ex = <int>{};
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k == 'codigo' ||
          k == 'codinterno' ||
          k == 'codex' ||
          k == 'controle' ||
          k == 'produto' ||
          k == 'nome' ||
          k.contains('quantidade') ||
          k == 'estoque' ||
          k.contains('estminimo') ||
          k.contains('fabricante') ||
          k == 'unidade' ||
          k.startsWith('lk') ||
          k == 'lucro' ||
          k == 'comissao' ||
          k.contains('ncm') ||
          k.contains('barras') ||
          k.contains('descricao') ||
          k.contains('observ') ||
          k.contains('peso') ||
          k.contains('icms') ||
          k.contains('ipi') ||
          k.contains('iva') ||
          k.contains('cst') ||
          k.contains('basecalculo') ||
          k.contains('ean') ||
          k.contains('modulo') ||
          k.contains('armazen') ||
          k.contains('embal') ||
          k.contains('previs') ||
          k.contains('data') ||
          k == 'moeda' ||
          k.contains('pf') ||
          k.contains('ippt') ||
          k.contains('iat')) {
        ex.add(i);
      }
    }
    return ex;
  }

  /// Evita escolher coluna errada (peso, imposto) como "preco de venda" na heuristica.
  bool _cabecalhoPermiteHeuristicaPrecoVenda(String rawHeader) {
    final k = _chaveCabecalhoCsv(rawHeader);
    if (k.contains('custo')) {
      return false;
    }
    if (k.contains('peso')) {
      return false;
    }
    if (k.contains('icms') || k.contains('ipi') || k.contains('iva') || k.contains('cst')) {
      return false;
    }
    if (k.contains('basecalculo') || k.contains('ean') || k.startsWith('lk')) {
      return false;
    }
    if (k.contains('quantidade') || k == 'moeda') {
      return false;
    }
    return k.contains('preco') ||
        k.contains('venda') ||
        k.contains('valor') ||
        k.startsWith('vr');
  }

  int _contarPrecoValidoAmostra(List<List<String>> linhas, int col, int maxLinhas) {
    var n = 0;
    final lim = math.min(linhas.length - 1, maxLinhas);
    for (var r = 1; r <= lim; r++) {
      final row = linhas[r];
      if (col >= row.length) continue;
      final v = _parseValorMonetario(row[col].trim());
      if (v != null && v > 0 && v <= 1e7) {
        n++;
      }
    }
    return n;
  }

  /// Se a coluna encontrada por nome vier vazia nos dados, escolhe a coluna
  /// numerica com mais precos validos na amostra (ex.: CSV desalinhado).
  int _refinarIndicePrecoVenda(
    List<List<String>> linhas,
    List<String> headers,
    int indiceSugerido,
    Set<int> excluir,
  ) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    if (indiceSugerido >= 0 && indiceSugerido < keys.length) {
      final k = keys[indiceSugerido];
      // TabEst: PrecoVenda costuma estar certo no nome mas raro nas linhas; nao trocar por
      // outra coluna "mais preenchida" (ICMS, peso, flags 0/1) senao vira 0,01 em massa.
      if (k == 'precovenda' ||
          k == 'valorvenda' ||
          k == 'valor_venda' ||
          k == 'vrvenda' ||
          k == 'vr_venda') {
        return indiceSugerido;
      }
    }

    final amostra = math.max(1, linhas.length - 1);
    final limite = math.max(40, (amostra * 0.12).round());
    final hitsSug = _contarPrecoValidoAmostra(linhas, indiceSugerido, 500);
    if (hitsSug >= limite) {
      return indiceSugerido;
    }
    var bestJ = indiceSugerido;
    var bestHits = hitsSug;
    final ncol = linhas.first.length;
    for (var j = 0; j < ncol; j++) {
      if (excluir.contains(j)) {
        continue;
      }
      if (j != indiceSugerido && !_cabecalhoPermiteHeuristicaPrecoVenda(headers[j])) {
        continue;
      }
      final h = _contarPrecoValidoAmostra(linhas, j, 500);
      if (h > bestHits) {
        bestHits = h;
        bestJ = j;
      }
    }
    return bestJ;
  }

  /// Cabecalhos TabEst / exportacoes: prioriza igualdade exata, depois nomes com "venda".
  int? _indiceColunaPrecoVenda(List<String> headers) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    const exatas = <String>[
      'precovenda',
      'valorvenda',
      'valor_venda',
      'vrvenda',
      'vr_venda',
      'preco1',
      'preco2',
      'preco3',
    ];
    for (final e in exatas) {
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == e) {
          return i;
        }
      }
    }
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k.contains('custo')) {
        continue;
      }
      if (k == 'precovenda' || k == 'valorvenda') {
        return i;
      }
      if (k.contains('venda') && (k.contains('preco') || k.contains('valor') || k.startsWith('vr'))) {
        return i;
      }
    }
    return null;
  }

  String _resumoTiposErroImportacaoCsv(List<String> erros) {
    var nPreco = 0;
    var nCodigo = 0;
    var nNome = 0;
    var nOutro = 0;
    for (final e in erros) {
      if (e.contains('preco invalido')) {
        nPreco++;
      } else if (e.contains('codigo vazio')) {
        nCodigo++;
      } else if (e.contains('nome/descricao vazio')) {
        nNome++;
      } else {
        nOutro++;
      }
    }
    final p = <String>[
      if (nPreco > 0) 'preco invalido: $nPreco',
      if (nCodigo > 0) 'codigo vazio: $nCodigo',
      if (nNome > 0) 'nome vazio: $nNome',
      if (nOutro > 0) 'outros: $nOutro',
    ];
    return p.isEmpty ? '' : 'Resumo: ${p.join(' | ')}.';
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

  String? _validarCustoMedio(String? value) {
    final texto = (value ?? '').trim();
    if (texto.isEmpty) {
      return null;
    }
    final v = _parseValorMonetario(texto);
    if (v == null) {
      return 'Custo medio invalido.';
    }
    if (v < 0) {
      return 'Custo medio nao pode ser negativo.';
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
    final custoMedioVal = _custoMedioController.text.trim().isEmpty
        ? 0.0
        : (_parseValorMonetario(_custoMedioController.text) ?? 0.0);
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
      custoMedio: custoMedioVal < 0 ? 0.0 : custoMedioVal,
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
      _custoMedioController.text = produto.custoMedio > 0
          ? _formatarValorMonetario(produto.custoMedio)
          : '';
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

  List<Produto> _produtosOrdenadosPorCadastro() {
    final produtos = widget.produtoRepository.listarTodos();
    produtos.sort((a, b) => a.id.compareTo(b.id));
    return produtos;
  }

  int _indiceProdutoAtual(List<Produto> produtos) {
    final atualId = _produtoEmEdicaoId;
    if (atualId == null) return -1;
    return produtos.indexWhere((p) => p.id == atualId);
  }

  void _abrirProdutoPorIndice(int indice) {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indexValido = indice.clamp(0, produtos.length - 1);
    _editarProdutoNoCabecalho(produtos[indexValido]);
  }

  void _irParaPrimeiroProduto() {
    _abrirProdutoPorIndice(0);
  }

  void _irParaUltimoProduto() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    _abrirProdutoPorIndice(produtos.length - 1);
  }

  void _irParaProdutoAnterior() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indiceAtual = _indiceProdutoAtual(produtos);
    if (indiceAtual <= 0) {
      _abrirProdutoPorIndice(0);
      return;
    }
    _abrirProdutoPorIndice(indiceAtual - 1);
  }

  void _irParaProximoProduto() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indiceAtual = _indiceProdutoAtual(produtos);
    if (indiceAtual < 0) {
      _abrirProdutoPorIndice(0);
      return;
    }
    if (indiceAtual >= produtos.length - 1) {
      _abrirProdutoPorIndice(produtos.length - 1);
      return;
    }
    _abrirProdutoPorIndice(indiceAtual + 1);
  }

  String _lerTextoArquivoUtf8OuLatin1(List<int> bytes) {
    var slice = bytes;
    if (slice.length >= 3 &&
        slice[0] == 0xEF &&
        slice[1] == 0xBB &&
        slice[2] == 0xBF) {
      slice = slice.sublist(3);
    }
    try {
      return utf8.decode(slice, allowMalformed: false);
    } catch (_) {
      return latin1.decode(slice, allowInvalid: true);
    }
  }

  String _detectarSeparadorCsv(String primeiraLinha) {
    final pv = ';'.allMatches(primeiraLinha).length;
    final pc = ','.allMatches(primeiraLinha).length;
    return pv >= pc ? ';' : ',';
  }

  List<String> _dividirLinhaCsv(String linha, String sep) {
    return linha
        .split(sep)
        .map((c) => c.trim().replaceAll('"', ''))
        .toList();
  }

  /// Normaliza cabecalho para casar CSV do Paradox (TabEst1) e exportacoes genericas.
  String _chaveCabecalhoCsv(String raw) {
    var s = raw.toLowerCase().trim().replaceAll('\ufeff', '');
    const acentos = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    for (final e in acentos.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'[\s_\.\-]'), '');
  }

  int? _indiceColunaPorAliases(List<String> headers, List<String> aliases) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.isEmpty) continue;
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == a) {
          return i;
        }
      }
    }
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.length < 5) {
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].contains(a)) {
          return i;
        }
      }
    }
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.length < 2) {
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == a) {
          return i;
        }
      }
    }
    return null;
  }

  int _parseQuantidadeCsv(String texto) {
    final t = texto.trim();
    if (t.isEmpty) {
      return 0;
    }
    final semMilhar = t.replaceAll('.', '').replaceAll(',', '.');
    final d = double.tryParse(semMilhar);
    if (d == null) {
      return int.tryParse(t.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;
    }
    final arred = d.round();
    return arred < 0 ? 0 : arred;
  }

  Produto? _produtoPorCodigoInterno(String codigo) {
    final alvo = codigo.trim().toLowerCase();
    if (alvo.isEmpty) return null;
    for (final p in widget.produtoRepository.listarTodos()) {
      if (p.codigoInterno.trim().toLowerCase() == alvo) {
        return p;
      }
    }
    return null;
  }

  Future<void> _importarProdutosCsv() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (!mounted) return;
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _definirStatus('Arquivo CSV vazio ou nao foi possivel ler.', erro: true);
      return;
    }
    final texto = _lerTextoArquivoUtf8OuLatin1(bytes);
    final textoN = texto.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    List<List<String>> linhas;
    var leituraCsv = 'CSV padrao (delimitador automatico, aspas suportadas)';
    try {
      final raw = Csv(dynamicTyping: false).decode(textoN);
      linhas = raw
          .map((row) => row.map((e) => e.toString().trim()).toList())
          .toList();
    } catch (_) {
      leituraCsv = 'CSV simples (fallback)';
      final linhasBrutas = textoN
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (linhasBrutas.length < 2) {
        _definirStatus('CSV precisa ter cabecalho e ao menos uma linha de dados.', erro: true);
        return;
      }
      final sep = _detectarSeparadorCsv(linhasBrutas.first);
      linhas = linhasBrutas.map((l) => _dividirLinhaCsv(l, sep)).toList();
    }

    if (linhas.length < 2) {
      _definirStatus('CSV precisa ter cabecalho e ao menos uma linha de dados.', erro: true);
      return;
    }
    final headers = linhas.first;
    final maxCols = headers.length;
    for (var i = 1; i < linhas.length; i++) {
      while (linhas[i].length < maxCols) {
        linhas[i].add('');
      }
    }

    final idxCodigo = _indiceColunaPorAliases(headers, [
      'codigo',
      'codigo interno',
      'codigo_interno',
      'sku',
      'ref',
      'cod',
    ]);
    final idxCodInterno = _indiceColunaPorAliases(headers, [
      'codinterno',
      'codigo_interno',
      'cod_interno',
      'codigointerno',
    ]);
    final idxCodEx = _indiceColunaPorAliases(headers, [
      'codex',
      'cod_ex',
      'cod ex',
    ]);
    var idxNome = _indiceColunaPorAliases(headers, [
      'nome',
      'produto',
      'item',
      'mercadoria',
    ]);
    final idxDescricao = _indiceColunaPorAliases(headers, [
      'descricao tecnica',
      'descricao_tecnica',
      'observacao',
      'observacoes',
      'obs',
      'complemento',
    ]);
    final idxObsCol = _indiceColunaPorAliases(headers, [
      'obs',
      'observacoes',
      'observacao',
    ]);
    idxNome ??= _indiceColunaPorAliases(headers, [
      'descricao',
      'descrição',
      'desc',
    ]);
    var idxPreco = _indiceColunaPrecoVenda(headers) ??
        _indiceColunaPorAliases(headers, [
          'precovenda',
          'preco venda',
          'preco_venda',
          'valor venda',
          'valorvenda',
          'vr venda',
          'vrvenda',
          'preco unitario',
          'preco_unitario',
          'preco1',
          'preco2',
          'preco3',
        ]);
    final idxPreco1 = _indiceColunaPorAliases(headers, ['preco1', 'preco_1']);
    final idxPreco2 = _indiceColunaPorAliases(headers, ['preco2', 'preco_2']);
    final idxPreco3 = _indiceColunaPorAliases(headers, ['preco3', 'preco_3']);
    final idxPrecoCusto = _indiceColunaPorAliases(headers, [
      'precocusto',
      'preco custo',
      'preco_custo',
    ]);
    final idxCustoMedio = _indiceColunaPorAliases(headers, [
      'customedio',
      'custo medio',
      'custo_medio',
      'cust_medio',
      'mediocusto',
    ]);
    final idxEstoque = _indiceColunaPorAliases(headers, [
      'quantidade',
      'estoque',
      'qtd',
      'saldo',
    ]);
    final idxEstMinimo = _indiceColunaPorAliases(headers, [
      'estminimo',
      'estoque minimo',
      'estoque_minimo',
      'quantidade minima',
      'qtd minima',
    ]);
    final idxFabricante = _indiceColunaPorAliases(headers, [
      'fabricante',
      'marca',
    ]);
    final idxUnidade = _indiceColunaPorAliases(headers, [
      'unidade',
      'und',
      'um',
    ]);

    if (idxCodigo == null && idxCodInterno == null && idxCodEx == null) {
      _definirStatus(
        'CSV sem coluna de codigo. Inclua Codigo, CodInterno ou CodEx (ex.: export TabEst1).',
        erro: true,
      );
      return;
    }
    if (idxNome == null) {
      _definirStatus(
        'CSV sem coluna de nome/descricao. Inclua: Nome, Produto ou Descricao.',
        erro: true,
      );
      return;
    }
    if (idxPreco == null) {
      _definirStatus(
        'CSV sem coluna de preco de venda. Inclua: PrecoVenda, Preco venda, Valor venda ou Preco1.',
        erro: true,
      );
      return;
    }

    final exclHeur = _indicesExcluidosHeuristicaPreco(headers);
    void excluirCol(int? i) {
      if (i != null) {
        exclHeur.add(i);
      }
    }

    excluirCol(idxCodigo);
    excluirCol(idxCodInterno);
    excluirCol(idxCodEx);
    excluirCol(idxNome);
    excluirCol(idxDescricao);
    excluirCol(idxEstoque);
    excluirCol(idxEstMinimo);
    excluirCol(idxPrecoCusto);
    excluirCol(idxCustoMedio);
    final idxPrecoRefinado = _refinarIndicePrecoVenda(
      linhas,
      headers,
      idxPreco,
      exclHeur,
    );

    var atualizarExistentes = true;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              title: const Text('Importar produtos (CSV)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arquivo: ${file.name}'),
                    Text(leituraCsv),
                    Text('Colunas no cabecalho: ${linhas.first.length}'),
                    Text('Linhas de dados: ${linhas.length - 1}'),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Atualizar produto se o codigo ja existir'),
                      value: atualizarExistentes,
                      onChanged: (v) {
                        setSt(() => atualizarExistentes = v ?? true);
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Paradox TabEst1: Codigo, CodInterno ou CodEx, Produto, PrecoVenda, Quantidade, '
                      'PrecoCusto, CustoMedio, EstMinimo, Fabricante, Unidade, Obs (opcionais).\n'
                      'Categoria fixa: Outros / Importacao CSV. PrecoVenda do CSV = apenas A Prazo (preco1); '
                      'a Vista e Atacado ficam 0 em produtos novos ou mantidos na atualizacao.\n'
                      'Quantidade negativa ou decimal: arredonda e nao deixa estoque < 0.\n'
                      'PrecoVenda vazio ou "000": tenta PrecoCusto; depois valores em Obs/descricao '
                      '(ex.: 60,00 no texto); se ainda zero, grava venda R\$ 0,01.',
                      style: TextStyle(fontSize: 12.5),
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
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Importar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmar != true || !mounted) return;

    var inseridos = 0;
    var atualizados = 0;
    var ignorados = 0;
    var precosExtraidosDeTexto = 0;
    final erros = <String>[];

    for (var r = 1; r < linhas.length; r++) {
      final row = linhas[r];
      var codigo = idxCodigo != null && idxCodigo < row.length
          ? row[idxCodigo].trim()
          : '';
      if (codigo.isEmpty &&
          idxCodInterno != null &&
          idxCodInterno < row.length) {
        codigo = row[idxCodInterno].trim();
      }
      if (codigo.isEmpty && idxCodEx != null && idxCodEx < row.length) {
        codigo = row[idxCodEx].trim();
      }
      final nome = row[idxNome].trim();
      final descExtra = idxDescricao != null && idxDescricao < row.length
          ? row[idxDescricao].trim()
          : '';
      var precoTxt = row[idxPrecoRefinado].trim();
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        for (final j in [idxPreco1, idxPreco2, idxPreco3]) {
          if (j == null || j >= row.length) continue;
          final t = row[j].trim();
          if (t.isNotEmpty && (_parseValorMonetario(t) ?? 0) > 0) {
            precoTxt = t;
            break;
          }
        }
      }
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        if (idxPrecoCusto != null && idxPrecoCusto < row.length) {
          final t = row[idxPrecoCusto].trim();
          if (t.isNotEmpty && (_parseValorMonetario(t) ?? 0) > 0) {
            precoTxt = t;
          }
        }
      }
      var precoVeioDeTextoLivre = false;
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        final obsCell = idxObsCol != null && idxObsCol < row.length
            ? row[idxObsCol].trim()
            : '';
        double? doTexto;
        if (obsCell.isNotEmpty) {
          doTexto = _extrairPrecoVendaDeTextoLivre(obsCell);
        }
        doTexto ??= _extrairPrecoVendaDeTextoLivre(descExtra);
        if (doTexto != null && doTexto > 0) {
          precoTxt = doTexto.toString();
          precoVeioDeTextoLivre = true;
        }
      }
      final estoqueTxt = idxEstoque != null && idxEstoque < row.length
          ? row[idxEstoque].trim()
          : '';
      final custoTxt = idxPrecoCusto != null && idxPrecoCusto < row.length
          ? row[idxPrecoCusto].trim()
          : '';
      final custoMedioTxt = idxCustoMedio != null && idxCustoMedio < row.length
          ? row[idxCustoMedio].trim()
          : '';
      final estMinTxt = idxEstMinimo != null && idxEstMinimo < row.length
          ? row[idxEstMinimo].trim()
          : '';
      final fabricanteTxt = idxFabricante != null && idxFabricante < row.length
          ? row[idxFabricante].trim()
          : '';
      final unidadeTxt = idxUnidade != null && idxUnidade < row.length
          ? row[idxUnidade].trim()
          : '';

      if (codigo.isEmpty && nome.isEmpty) {
        ignorados++;
        continue;
      }
      if (codigo.isEmpty) {
        erros.add('Linha ${r + 1}: codigo vazio.');
        continue;
      }
      if (nome.isEmpty) {
        erros.add('Linha ${r + 1}: nome/descricao vazio.');
        continue;
      }
      // Paradox/TabEst: PrecoVenda "000" ou 0 e comum; usa custo e, se ainda zero, 0.01 (sistema exige venda > 0).
      var preco = _parseValorMonetario(precoTxt);
      if (preco == null || preco <= 0) {
        final pc = _parseValorMonetario(custoTxt);
        if (pc != null && pc > 0) {
          preco = pc;
        }
      }
      if (preco == null || preco <= 0) {
        preco = 0.01;
      } else if (precoVeioDeTextoLivre) {
        precosExtraidosDeTexto++;
      }
      final estoque = _parseQuantidadeCsv(estoqueTxt);
      final precoCustoVal = _parseValorMonetario(custoTxt) ?? 0;
      final precoCusto = precoCustoVal < 0 ? 0.0 : precoCustoVal;
      final qtdMin = _parseQuantidadeCsv(estMinTxt);
      final descricao = descExtra.isEmpty ? '' : descExtra;
      final existente = _produtoPorCodigoInterno(codigo);
      double custoMedioVal;
      if (custoMedioTxt.isNotEmpty) {
        custoMedioVal = _parseValorMonetario(custoMedioTxt) ?? 0;
        if (custoMedioVal < 0) {
          custoMedioVal = 0;
        }
      } else {
        custoMedioVal = existente?.custoMedio ?? 0;
      }

      if (existente != null && !atualizarExistentes) {
        ignorados++;
        continue;
      }

      // Import antigo copiava PrecoVenda para preco2/preco3: se os tres eram iguais, zera vista/atacado na reimportacao.
      var preco2Imp = existente?.preco2 ?? 0;
      var preco3Imp = existente?.preco3 ?? 0;
      if (existente != null) {
        final p1a = existente.preco1;
        if (p1a > 0 &&
            (existente.preco2 - p1a).abs() < 0.0001 &&
            (existente.preco3 - p1a).abs() < 0.0001) {
          preco2Imp = 0;
          preco3Imp = 0;
        }
      }

      final produto = Produto(
        id: existente?.id ?? 0,
        codigoInterno: codigo,
        nome: _normalizarNomeProduto(nome),
        descricao: descricao,
        unidade: _normalizarUnidade(unidadeTxt.isEmpty ? 'UN' : unidadeTxt),
        categoria: _categoriaOutros,
        subcategoria: 'Importacao CSV',
        marca: '',
        fornecedor: '',
        fabricante: fabricanteTxt,
        codigoBarras: '',
        fotoPath: existente?.fotoPath ?? '',
        localizacao: '',
        ncm: '',
        estoque: estoque,
        quantidadeMinima: qtdMin > 0
            ? qtdMin
            : (existente?.quantidadeMinima ?? 0),
        precoCusto: precoCusto,
        custoMedio: custoMedioVal,
        // PrecoVenda do TabEst1 = "a prazo" no sistema antigo -> so preco1 e precoVenda (como no salvar manual).
        preco1: preco,
        preco2: preco2Imp,
        preco3: preco3Imp,
        precoVenda: preco,
        criadoEm: existente?.criadoEm,
      );
      widget.produtoRepository.salvar(produto);
      if (existente != null) {
        atualizados++;
      } else {
        inseridos++;
      }
    }

    if (!mounted) return;
    final buf = StringBuffer()
      ..write('Importacao CSV: $inseridos novos, $atualizados atualizados');
    if (precosExtraidosDeTexto > 0) {
      buf.write(
        '; preco de venda obtido do texto Obs/descricao em $precosExtraidosDeTexto linha(s)',
      );
    }
    if (ignorados > 0) {
      buf.write(', $ignorados ignorados');
    }
    if (erros.isNotEmpty) {
      buf.write('. ${erros.length} erro(s). ');
      buf.write(_resumoTiposErroImportacaoCsv(erros));
    }
    _definirStatus(buf.toString(), erro: erros.isNotEmpty);
    if (erros.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          final preview = erros.take(25).join('\n');
          final resumo = _resumoTiposErroImportacaoCsv(erros);
          return AlertDialog(
            title: const Text('Erros na importacao'),
            content: SingleChildScrollView(
              child: SelectableText(
                erros.length > 25
                    ? '$resumo\n\n$preview\n... e mais ${erros.length - 25} linha(s).'
                    : '$resumo\n\n$preview',
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
    }
  }

  Future<void> _abrirPesquisaProduto() async {
    final pesquisaController = TextEditingController();
    List<Produto> resultados = widget.produtoRepository.pesquisar(
      '',
      limite: 80,
    );

    final produtoSelecionado = await showDialog<Produto>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pesquisar produto'),
              content: SizedBox(
                width: 760,
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
                        setDialogState(() {
                          resultados = widget.produtoRepository.pesquisar(
                            value,
                            limite: 80,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 220,
                        maxHeight: MediaQuery.of(context).size.height * 0.58,
                      ),
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum produto encontrado.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final produto = resultados[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  title: Text(produto.nome),
                                  subtitle: Text(
                                    'SKU: ${produto.codigoInterno} | Categoria: ${produto.categoria.isEmpty ? '-' : produto.categoria}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  titleTextStyle: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
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
      appBar: AppBar(
        title: const Text('Cadastro de Produtos'),
        actions: [
          IconButton(
            tooltip: 'Importar produtos (CSV)',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _importarProdutosCsv,
          ),
        ],
      ),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaPrimeiroProduto,
                    child: const Text('|< Primeiro'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaProdutoAnterior,
                    child: const Text('< Anterior'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaProximoProduto,
                    child: const Text('Proximo >'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaUltimoProduto,
                    child: const Text('Ultimo >|'),
                  ),
                ),
              ],
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
                    controller: _custoMedioController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarCustoMedio,
                    decoration: const InputDecoration(
                      labelText: 'Custo medio',
                      helperText: 'Opcional (ex.: CustoMedio do sistema antigo)',
                    ),
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
                    controller: _preco1Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'A Prazo'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _preco2Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'À Vista'),
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
                    controller: _preco3Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [RealInputFormatter()],
                    validator: _validarPrecoTabela,
                    decoration: const InputDecoration(labelText: 'Atacado'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'A Prazo -> Markup: ${markup1.toStringAsFixed(2)}% | Margem: ${margem1.toStringAsFixed(2)}%\n'
                'À Vista -> Markup: ${markup2.toStringAsFixed(2)}% | Margem: ${margem2.toStringAsFixed(2)}%\n'
                'Atacado -> Markup: ${markup3.toStringAsFixed(2)}% | Margem: ${margem3.toStringAsFixed(2)}%',
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
            if (_produtoEmEdicaoId != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _excluirProdutoEmEdicao,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir produto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
