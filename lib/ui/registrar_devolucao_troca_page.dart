import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/api/venda_api_repository.dart';
import '../services/configuracoes_service.dart';
import '../data/devolucao_fiscal_store.dart';
import '../data/vale_credito_service.dart';
import '../data/venda_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/troca_com_nota_pdv_intent.dart';
import '../domain/troca_diferenca_caixa.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/registro_devolucao.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../services/print_service.dart';
import '../services/venda_fiscal_service.dart';
import 'clientes_page.dart';
import 'fiscal/widgets/devolucao_fiscal_historico_panel.dart';
import 'shell/main_menu_deps.dart';
import 'troca_com_nota_pdv_navigation.dart';
import 'vales/vale_credito_comprovante_dialog.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/produto_busca_input.dart';

/// Fluxo de devolucao (estoque de volta) ou troca (devolucao + saida de produtos).
class RegistrarDevolucaoTrocaPage extends StatefulWidget {
  const RegistrarDevolucaoTrocaPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendaId,
    required this.usuarioAtual,
    required this.podeRegistrarSemSenha,
    this.usuarioLogado,
    this.vendedorRepository,
    this.configuracoesService,
    this.printService,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic produtoRepository;
  final int vendaId;
  final String usuarioAtual;
  final bool podeRegistrarSemSenha;
  final UsuarioSistema? usuarioLogado;
  final dynamic vendedorRepository;
  final ConfiguracoesService? configuracoesService;
  final PrintService? printService;

  @override
  State<RegistrarDevolucaoTrocaPage> createState() =>
      _RegistrarDevolucaoTrocaPageState();
}

class _LinhaTrocaEdit {
  _LinhaTrocaEdit({
    required this.produto,
    int quantidadeInicial = 1,
  })  : qtdController = TextEditingController(text: '$quantidadeInicial'),
        precoTipo = 'preco1';

  final Produto produto;
  final TextEditingController qtdController;
  String precoTipo;

  int get quantidade => int.tryParse(qtdController.text.trim()) ?? 0;

  void dispose() => qtdController.dispose();
}

class _RegistrarDevolucaoTrocaPageState extends State<RegistrarDevolucaoTrocaPage> {
  final _motivoController = TextEditingController();
  final _obsFinanceiraController = TextEditingController();
  late dynamic _usuarioRepository;
  final _currency = NumberFormat('#,##0.00', 'pt_BR');

  Venda? _venda;
  List<ItemVenda> _itens = const [];
  final Map<int, TextEditingController> _qtdDevolucaoPorItem = {};
  bool _modoTroca = false;
  final List<_LinhaTrocaEdit> _linhasTroca = [];
  bool _permitirVendaSemEstoque = true;
  bool _carregando = true;
  String? _erroCarregamento;
  bool _gerarVale = false;
  bool _vinculandoCliente = false;

  @override
  void initState() {
    super.initState();
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    final config = await ConfiguracoesService.global.carregarEfetiva();
    if (!mounted) return;
    setState(() {
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
    });
    await _recarregarVenda();
  }

  Future<void> _recarregarVenda() async {
    for (final c in _qtdDevolucaoPorItem.values) {
      c.dispose();
    }
    _qtdDevolucaoPorItem.clear();

    final repo = widget.vendaRepository;
    Venda? v = repo.obterPorId(widget.vendaId) as Venda?;
    List<ItemVenda> itens = const [];
    try {
      if (repo is VendaApiRepository) {
        await repo.carregarItensRemoto(widget.vendaId);
        v = repo.obterPorId(widget.vendaId) ?? v;
        itens = repo.listarItensPorVenda(widget.vendaId);
      } else {
        try {
          itens = v?.itens.toList() ?? const <ItemVenda>[];
        } catch (_) {
          itens = (repo.listarItensPorVenda(widget.vendaId) as List<ItemVenda>?) ??
              const [];
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _venda = null;
        _itens = const [];
        _carregando = false;
        _erroCarregamento = LanApiFeedback.mensagem(e);
      });
      return;
    }

    if (v == null) {
      if (!mounted) return;
      setState(() {
        _venda = null;
        _itens = const [];
        _carregando = false;
        _erroCarregamento = 'Venda nao encontrada.';
      });
      return;
    }
    for (final item in itens) {
      final maxD = item.quantidade - item.quantidadeDevolvida;
      _qtdDevolucaoPorItem[item.id] = TextEditingController(
        text: maxD > 0 ? '' : '0',
      );
    }
    if (!mounted) return;
    setState(() {
      _venda = v;
      _itens = itens;
      _carregando = false;
      _erroCarregamento = null;
    });
  }

  @override
  void dispose() {
    _motivoController.dispose();
    _obsFinanceiraController.dispose();
    for (final c in _qtdDevolucaoPorItem.values) {
      c.dispose();
    }
    for (final l in _linhasTroca) {
      l.dispose();
    }
    super.dispose();
  }

  String _formatarMoeda(double v) => 'R\$ ${_currency.format(v)}';

  double _precoProdutoTipo(Produto p, String tipo) {
    switch (tipo) {
      case 'preco2':
        return p.preco2 > 0 ? p.preco2 : p.precoVenda;
      case 'preco3':
        return p.preco3 > 0 ? p.preco3 : p.precoVenda;
      case 'preco1':
      default:
        return p.preco1 > 0 ? p.preco1 : p.precoVenda;
    }
  }

  int _parseQtd(String t) {
    final n = int.tryParse(t.trim());
    return n == null || n < 0 ? 0 : n;
  }

  int _maxDevolvivel(ItemVenda item) =>
      item.quantidade - item.quantidadeDevolvida;

  bool _quantidadeAcimaDoMax(ItemVenda item) {
    final ctl = _qtdDevolucaoPorItem[item.id];
    if (ctl == null) return false;
    return _parseQtd(ctl.text) > _maxDevolvivel(item);
  }

  List<ItemVenda> get _itensComQuantidadeInvalida =>
      _itens.where(_quantidadeAcimaDoMax).toList();

  bool get _podeFluxoTrocaComNotaNoPdv {
    final u = widget.usuarioLogado;
    return u != null &&
        widget.vendedorRepository != null &&
        widget.configuracoesService != null &&
        widget.printService != null &&
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv);
  }

  List<LinhaDevolucaoEntradaInput> _entradasPreenchidasFromUi() {
    final entradas = <LinhaDevolucaoEntradaInput>[];
    for (final item in _itens) {
      final ctl = _qtdDevolucaoPorItem[item.id];
      if (ctl == null) continue;
      final q = _parseQtd(ctl.text);
      if (q <= 0 || q > _maxDevolvivel(item)) continue;
      entradas.add(
        LinhaDevolucaoEntradaInput(itemVendaId: item.id, quantidade: q),
      );
    }
    return entradas;
  }

  double _creditoSugeridoAtual() => _valorTotalDevolvido();

  /// Valor de referencia do que o cliente devolve (preco da venda original).
  double _valorTotalDevolvido() {
    final entradas = _entradasPreenchidasFromUi();
    return creditoDevolucaoReaisDeEntradas(
      entradas: entradas
          .map((e) => (itemVendaId: e.itemVendaId, quantidade: e.quantidade))
          .toList(),
      precoUnitarioDoItem: (id) {
        final item = _itens.firstWhere((i) => i.id == id);
        return item.precoUnitario;
      },
    );
  }

  /// Valor dos produtos que o cliente leva na troca (tabela escolhida no PDV).
  double _valorTotalSaidaTroca() {
    var total = 0.0;
    for (final linha in _linhasTroca) {
      final q = linha.quantidade;
      if (q <= 0) continue;
      total += q * _precoProdutoTipo(linha.produto, linha.precoTipo);
    }
    return total;
  }

  /// Positivo = cliente deve pagar; negativo = loja devolve ao cliente.
  double _diferencaTroca() => _valorTotalSaidaTroca() - _valorTotalDevolvido();

  static const double _epsValorTroca = 0.009;

  /// Sem vale, o credito da devolucao so existe se o cliente comprar agora.
  Widget _buildOpcaoVale(BuildContext context) {
    final tema = Theme.of(context);
    final v = _venda;
    final cliente = v == null ? null : _clienteDaVenda(v);
    final credito = _creditoSugeridoAtual();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: _gerarVale,
            onChanged: (x) => setState(() => _gerarVale = x),
            title: const Text('Gerar vale de credito'),
            subtitle: Text(
              'O cliente leva ${_formatarMoeda(credito)} em vale e gasta '
              'depois, em qualquer compra. Sem o vale, o credito so vale '
              'se ele comprar agora.',
              style: tema.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
          if (_gerarVale)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    cliente == null
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                    size: 20,
                    color: cliente == null
                        ? tema.colorScheme.tertiary
                        : tema.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cliente == null
                          ? 'Venda sem cliente. O vale sai so pelo codigo '
                              'impresso: quem apresentar o codigo usa. '
                              'Vincule um cliente para poder recuperar o vale '
                              'se o cliente perder o papel.'
                          : 'Vale sai no nome de ${cliente.rotuloExibicao()} '
                              'e tambem pelo codigo.',
                      style: tema.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                  if (cliente == null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed:
                          _vinculandoCliente ? null : _vincularClienteNaVenda,
                      child: const Text('Vincular'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumoValoresTroca(BuildContext context) {
    final tema = Theme.of(context);
    final devolvido = _valorTotalDevolvido();
    final saida = _valorTotalSaidaTroca();
    final diff = _diferencaTroca();
    final valoresBatem = diff.abs() <= _epsValorTroca && saida > _epsValorTroca;

    Color corDiff;
    IconData iconeDiff;
    String tituloDiff;
    String orientacao;

    if (saida <= _epsValorTroca && devolvido <= _epsValorTroca) {
      corDiff = tema.colorScheme.outline;
      iconeDiff = Icons.info_outline;
      tituloDiff = 'Informe as quantidades';
      orientacao =
          'Preencha o que volta e adicione os produtos da troca para conferir os valores.';
    } else if (valoresBatem) {
      corDiff = tema.colorScheme.primary;
      iconeDiff = Icons.check_circle_outline;
      tituloDiff = 'Valores conferem';
      orientacao =
          'Credito da devolucao e valor da troca estao iguais. '
          'Nao ha diferenca a receber no caixa.';
    } else if (diff > _epsValorTroca) {
      corDiff = tema.colorScheme.tertiary;
      iconeDiff = Icons.payments_outlined;
      tituloDiff = 'Cliente paga a diferenca';
      orientacao =
          'O que o cliente leva custa mais do que o devolvido. '
          'Ao registrar, o sistema pergunta se envia '
          '${_formatarMoeda(diff)} para o caixa receber '
          '(sem baixar estoque de novo). '
          'Se precisar de nota dos produtos novos, use Devolucao + PDV.';
    } else {
      corDiff = tema.colorScheme.secondary;
      iconeDiff = Icons.savings_outlined;
      tituloDiff = 'Loja devolve ao cliente';
      orientacao =
          'O devolvido vale mais do que a troca. '
          'Devolva ${_formatarMoeda(-diff)} ao cliente (dinheiro/PIX) '
          'e registre na observacao financeira.';
    }

    Widget linhaValor(String rotulo, double valor, {bool destaque = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                rotulo,
                style: destaque
                    ? tema.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                    : tema.textTheme.bodyMedium,
              ),
            ),
            Text(
              _formatarMoeda(valor),
              style: destaque
                  ? tema.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )
                  : tema.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Conferencia de valores',
              style: tema.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            linhaValor('Devolvido (credito na troca)', devolvido),
            linhaValor('Produtos da troca (saida)', saida),
            const Divider(height: 20),
            linhaValor(
              'Diferenca (saida − devolvido)',
              diff.abs() <= _epsValorTroca ? 0 : diff,
              destaque: true,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconeDiff, size: 22, color: corDiff),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloDiff,
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: corDiff,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        orientacao,
                        style: tema.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TrocaComNotaPdvIntent? _montarIntentTrocaComNota({
    required Venda v,
    required double credito,
  }) {
    final clienteId = v.cliente.targetId;
    if (clienteId <= 0) return null;
    final vend = v.vendedor.target;
    final ref = v.numeroOrcamento > 0 ? '${v.numeroOrcamento}' : 'id ${v.id}';
    final obsFin = _obsFinanceiraController.text.trim();
    return TrocaComNotaPdvIntent(
      vendaOrigemId: v.id,
      clienteId: clienteId,
      creditoDevolucaoReais: credito,
      numeroVendaOrigem: v.numeroOrcamento,
      vendedorId: vend?.id,
      observacao: obsFin.isEmpty
          ? 'Troca com nota apos devolucao da venda $ref'
          : obsFin,
    );
  }

  Cliente? _clienteDaVenda(Venda venda) {
    // Entidade detached (API): .target pode lancar; preferir targetId + repo.
    try {
      final ligado = venda.cliente.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = venda.cliente.targetId;
    if (id == 0) return null;
    try {
      return widget.clienteRepository.obterPorId(id) as Cliente?;
    } catch (_) {
      return null;
    }
  }

  /// Amarra um cliente a venda ja finalizada para o vale ficar nominal.
  Future<void> _vincularClienteNaVenda() async {
    final v = _venda;
    if (v == null || _vinculandoCliente) return;
    final c = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientesPage(
          clienteRepository: widget.clienteRepository,
          vendaRepository: widget.vendaRepository,
          vendedorRepository: widget.vendedorRepository,
          retornarClienteAoSalvar: true,
        ),
      ),
    );
    if (!mounted || c == null) return;
    setState(() => _vinculandoCliente = true);
    try {
      final repo = widget.vendaRepository;
      if (repo is VendaApiRepository) {
        await repo.vincularClienteVendaFinalizadaRemoto(v.id, c.id);
      } else {
        repo.vincularClienteVendaFinalizada(v.id, c.id);
      }
      await _recarregarVenda();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanApiFeedback.mensagem(e))),
      );
    } finally {
      if (mounted) setState(() => _vinculandoCliente = false);
    }
  }

  Future<void> _emitirValeDaDevolucao({
    required Venda v,
    required int registroId,
    required double credito,
    required String registradoPor,
  }) async {
    final servico = ValeCreditoService.deVendaRepository(widget.vendaRepository);
    if (!servico.disponivel) {
      await _avisarValeNaoSaiu(
        'Sem conexao com o servidor para gerar o vale. '
        'A devolucao foi registrada; gere o vale pelo PC servidor.',
      );
      return;
    }
    try {
      final vale = await servico.emitir(
        valor: credito,
        emitidoPor: registradoPor,
        vendaOrigemId: v.id,
        registroDevolucaoId: registroId,
        clienteId: _clienteDaVenda(v)?.id ?? 0,
        numeroVendaOrigem: v.numeroOrcamento,
        observacao: _obsFinanceiraController.text.trim(),
      );
      if (!mounted) return;
      await mostrarComprovanteVale(context, vale: vale);
    } catch (e) {
      await _avisarValeNaoSaiu(
        'A devolucao foi registrada, mas o vale nao pode ser gerado: '
        '${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  Future<void> _avisarValeNaoSaiu(String motivo) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vale nao gerado'),
        content: Text(motivo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  /// A devolucao ja foi gravada quando isso aparece: o aviso precisa
  /// sobreviver ao fechamento da tela, entao vai em dialogo, nao snackbar.
  Future<void> _avisarPdvNaoAbriu(String motivo) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Devolucao registrada, mas o PDV nao abriu'),
        content: Text(motivo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _oferecerEnvioDiferencaAoCaixa({
    required Venda vendaOrigem,
    required int registroId,
  }) async {
    final diff = TrocaDiferencaCaixa.diferenca(
      valorSaida: _valorTotalSaidaTroca(),
      valorDevolvido: _valorTotalDevolvido(),
    );
    if (TrocaDiferencaCaixa.lojaDevolve(diff)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Devolva ao cliente'),
          content: Text(
            'A troca ficou ${_formatarMoeda(-diff)} a favor do cliente. '
            'Pague em dinheiro ou PIX e anote na observacao. '
            'Isso nao sai automaticamente da gaveta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    if (!TrocaDiferencaCaixa.clientePaga(diff)) return;

    if (!mounted) return;
    var meio = 'dinheiro';
    var parcelas = 1;
    final escolha = await showDialog<({String meio, int parcelas})>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: const Text('Enviar diferenca ao caixa?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O cliente deve ${_formatarMoeda(diff)}. '
                      'O orcamento vai para a fila do Caixa, sem baixar estoque de novo.',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: meio,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'dinheiro',
                          child: Text('Dinheiro (cupom)'),
                        ),
                        DropdownMenuItem(
                          value: 'pix',
                          child: Text('PIX (NFC-e)'),
                        ),
                        DropdownMenuItem(
                          value: 'cartao_debito',
                          child: Text('Cartao de debito (NFC-e)'),
                        ),
                        DropdownMenuItem(
                          value: 'cartao_credito',
                          child: Text('Cartao de credito (NFC-e)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setD(() {
                          meio = v;
                          if (v != 'cartao_credito') parcelas = 1;
                        });
                      },
                    ),
                    if (meio == 'cartao_credito') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: parcelas,
                        decoration: const InputDecoration(
                          labelText: 'Parcelas',
                          isDense: true,
                        ),
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(value: i, child: Text('${i}x')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setD(() => parcelas = v);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      TrocaDiferencaCaixa.geraNfce(meio)
                          ? 'No caixa, ao finalizar, a NFC-e sai da diferenca '
                              '(${_formatarMoeda(diff)}), nao dos produtos da troca. '
                              'Para nota dos itens novos, use Devolucao + PDV.'
                          : 'Dinheiro: o caixa imprime cupom. Se mudar para cartao ou PIX la, a NFC-e e emitida.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Agora nao'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, (meio: meio, parcelas: parcelas)),
                  child: const Text('Enviar ao caixa'),
                ),
              ],
            );
          },
        );
      },
    );
    if (escolha == null || !mounted) return;

    try {
      final repo = widget.vendaRepository;
      late final int numero;
      late final bool reutilizado;
      if (repo is VendaApiRepository) {
        final r = await repo.registrarOrcamentoComplementoTrocaRemoto(
          vendaOrigemId: vendaOrigem.id,
          registroDevolucaoId: registroId,
          valor: diff,
          formaPagamento: escolha.meio,
          quantidadeParcelas: escolha.parcelas,
        );
        numero = r.numeroOrcamento;
        reutilizado = r.reutilizado;
      } else if (repo is VendaRepository) {
        final r = repo.registrarOrcamentoComplementoTroca(
          vendaOrigemId: vendaOrigem.id,
          registroDevolucaoId: registroId,
          valor: diff,
          formaPagamento: escolha.meio,
          quantidadeParcelas: escolha.parcelas,
        );
        numero = r.numeroOrcamento;
        reutilizado = r.reutilizado;
      } else {
        throw StateError('Repositorio de vendas indisponivel.');
      }
      if (!mounted) return;
      final nfce = TrocaDiferencaCaixa.geraNfce(escolha.meio);
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Na fila do caixa'),
          content: Text(
            reutilizado
                ? 'O orcamento #$numero ja estava no caixa. Abra o Caixa e receba.'
                : nfce
                    ? 'Orcamento #$numero de ${_formatarMoeda(diff)} foi para o Caixa. '
                        'Ao finalizar no cartao/PIX, a NFC-e da diferenca e emitida normalmente.'
                    : 'Orcamento #$numero de ${_formatarMoeda(diff)} foi para o Caixa. '
                        'Abra a aba Caixa e receba.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Nao enviou ao caixa'),
          content: Text(
            'A troca foi registrada, mas o orcamento da diferenca nao foi criado: '
            '${LanApiFeedback.mensagem(e)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _abrirPdvTrocaComNota({
    required Venda v,
    required double credito,
  }) async {
    if (!_podeFluxoTrocaComNotaNoPdv) {
      await _avisarPdvNaoAbriu(
        'Abra pela Listagem de vendas com um usuario que tenha acesso ao PDV.',
      );
      return;
    }
    final intent = _montarIntentTrocaComNota(v: v, credito: credito);
    if (intent == null) {
      await _avisarPdvNaoAbriu(
        'Esta venda nao tem cliente cadastrado. Vincule o cliente na venda '
        'para abrir o PDV com o credito da devolucao.',
      );
      return;
    }
    await abrirPdvTrocaComNota(
      context,
      intent: intent,
      produtoRepository: widget.produtoRepository,
      clienteRepository: widget.clienteRepository,
      vendaRepository: widget.vendaRepository,
      vendedorRepository: widget.vendedorRepository!,
      configuracoesService: widget.configuracoesService!,
      printService: widget.printService!,
      usuarioLogado: widget.usuarioLogado!,
    );
  }

  Future<(bool ok, String usuario)> _autorizar() async {
    if (widget.podeRegistrarSemSenha) {
      return (true, widget.usuarioAtual);
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorizacao'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Usuario com permissao (admin, financeiro ou manutencao de caixa).',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loginController,
                decoration: const InputDecoration(labelText: 'Login'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: senhaController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      loginController.dispose();
      senhaController.dispose();
      return (false, '');
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final u = await _usuarioRepository.autenticar(login, senha) as UsuarioSistema?;
    final autorizado =
        u != null && UsuarioPermissaoHelper.podeCancelarVendas(u);
    if (!autorizado) return (false, '');
    return (true, u.login);
  }

  Future<void> _confirmar({bool abrirPdvApos = false}) async {
    final v = _venda;
    if (v == null) return;
    if (abrirPdvApos && _modoTroca) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para troca com nota, use o modo Devolucao (nao Troca) e depois o PDV.',
          ),
        ),
      );
      return;
    }
    final motivo = _motivoController.text.trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o motivo.')),
      );
      return;
    }

    final entradas = <LinhaDevolucaoEntradaInput>[];
    for (final item in _itens) {
      final ctl = _qtdDevolucaoPorItem[item.id];
      if (ctl == null) continue;
      final q = _parseQtd(ctl.text);
      if (q <= 0) continue;
      final maxD = item.quantidade - item.quantidadeDevolvida;
      if (q > maxD) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Quantidade invalida para "${item.nomeProduto}" (max. $maxD).',
            ),
          ),
        );
        return;
      }
      entradas.add(
        LinhaDevolucaoEntradaInput(itemVendaId: item.id, quantidade: q),
      );
    }
    if (entradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe quantidade em ao menos um item devolvido.'),
        ),
      );
      return;
    }

    final saidas = <LinhaTrocaSaidaInput>[];
    if (_modoTroca) {
      for (final linha in _linhasTroca) {
        if (linha.quantidade <= 0) continue;
        final pu = _precoProdutoTipo(linha.produto, linha.precoTipo);
        final custo = linha.produto.precoCusto;
        saidas.add(
          LinhaTrocaSaidaInput(
            produtoId: linha.produto.id,
            quantidade: linha.quantidade,
            precoUnitario: pu,
            precoTipo: linha.precoTipo,
            precoCustoUnitario: custo,
          ),
        );
      }
      if (saidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Em troca, adicione ao menos um produto de saida.'),
          ),
        );
        return;
      }
    }

    final auth = await _autorizar();
    if (!mounted || !auth.$1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operacao nao autorizada.')),
        );
      }
      return;
    }

    final VendaFiscalService? fiscalSvc;
    if (widget.vendaRepository is VendaRepository) {
      fiscalSvc = VendaFiscalService(
        vendaRepository: widget.vendaRepository as VendaRepository,
        clienteRepository: widget.clienteRepository,
      );
    } else {
      fiscalSvc = null;
      final exigeFiscal =
          v.nfceAutorizadaAtiva || v.nfe55Autorizada;
      if (exigeFiscal) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Devolucao com NFC-e/NF-e autorizada ainda exige o PC servidor '
              '(SEFAZ). Vendas sem documento fiscal podem ser devolvidas neste terminal.',
            ),
          ),
        );
        return;
      }
    }

    VendaFiscalOperacaoResultado? fiscalRes;
    if (fiscalSvc != null && fiscalSvc.vendaExigeNfeDevolucao(v)) {
      final confirmaFiscal = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Devolucao fiscal'),
          content: Text(
            _modoTroca
                ? 'Esta venda possui NFC-e/NF-e autorizada.\n\n'
                    'Sera emitida NF-e de devolucao (finalidade 4) na SEFAZ '
                    'para os itens devolvidos.\n\n'
                    'Os produtos da troca (saida) exigem nova venda/NFC-e '
                    'separada.'
                : 'Esta venda possui NFC-e/NF-e autorizada.\n\n'
                    'Sera emitida NF-e de devolucao (finalidade 4) na SEFAZ '
                    'referenciando a nota original, antes de dar entrada no estoque.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Emitir e continuar'),
            ),
          ],
        ),
      );
      if (confirmaFiscal != true || !mounted) return;

      final itensFiscais = <({ItemVenda item, int quantidade})>[];
      for (final e in entradas) {
        final item = _itens.firstWhere((i) => i.id == e.itemVendaId);
        itensFiscais.add((item: item, quantidade: e.quantidade));
      }

      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Emitindo NF-e de devolucao na SEFAZ...')),
            ],
          ),
        ),
      );

      fiscalRes = await fiscalSvc.emitirNfeDevolucaoVenda(
        venda: v,
        itensDevolvidos: itensFiscais,
        motivo: motivo,
        registroDevolucaoId: 0,
      );

      if (mounted) Navigator.of(context).pop();

      if (!fiscalRes.sucesso) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fiscalRes.mensagem.isNotEmpty
                  ? fiscalRes.mensagem
                  : 'Falha na devolucao fiscal.',
            ),
          ),
        );
        return;
      }
    }

    int registroId;
    try {
      final repo = widget.vendaRepository;
      if (repo is VendaApiRepository) {
        registroId = await repo.registrarDevolucaoOuTrocaRemoto(
          vendaOrigemId: v.id,
          tipo: _modoTroca ? 'troca' : 'devolucao',
          motivo: motivo,
          observacaoFinanceira: _obsFinanceiraController.text,
          registradoPor: auth.$2,
          entradas: entradas,
          saidasTroca: saidas,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      } else {
        registroId = repo.registrarDevolucaoOuTroca(
          vendaOrigemId: v.id,
          tipo: _modoTroca ? 'troca' : 'devolucao',
          motivo: motivo,
          observacaoFinanceira: _obsFinanceiraController.text,
          registradoPor: auth.$2,
          entradas: entradas,
          saidasTroca: saidas,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanApiFeedback.mensagem(e))),
      );
      return;
    }

    if (fiscalRes != null &&
        fiscalRes.sucesso &&
        fiscalRes.referenciaDevolucao.isNotEmpty &&
        fiscalSvc != null) {
      fiscalSvc.salvarDevolucaoFiscalLocal(
        registroDevolucaoId: registroId,
        vendaId: v.id,
        referenciaFocus: fiscalRes.referenciaDevolucao,
        chaveNfe: fiscalRes.chaveDevolucao,
        numero: fiscalRes.numeroDevolucao,
        serie: fiscalRes.serieDevolucao,
        urlDanfe: fiscalRes.urlDanfeDevolucao,
        urlXml: fiscalRes.urlXmlDevolucao,
        statusFocus: fiscalRes.statusFocusDevolucao,
        motivo: motivo,
      );
    }

    if (!mounted) return;
    if (fiscalRes != null && fiscalRes.sucesso) {
      await mostrarDialogoDevolucaoFiscalSucesso(context, resultado: fiscalRes);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fiscalRes != null && fiscalRes.nfeDevolucaoAutorizada
              ? 'Registro salvo. NF-e de devolucao autorizada.'
              : 'Registro salvo com sucesso.',
        ),
      ),
    );

    final credito = creditoDevolucaoReaisDeEntradas(
      entradas: entradas
          .map((e) => (itemVendaId: e.itemVendaId, quantidade: e.quantidade))
          .toList(),
      precoUnitarioDoItem: (id) {
        final item = _itens.firstWhere((i) => i.id == id);
        return item.precoUnitario;
      },
    );

    if (!abrirPdvApos && !_modoTroca && _gerarVale && credito > 0.004) {
      await _emitirValeDaDevolucao(
        v: v,
        registroId: registroId,
        credito: credito,
        registradoPor: auth.$2,
      );
    }

    if (abrirPdvApos && credito > 0.004) {
      await _abrirPdvTrocaComNota(v: v, credito: credito);
    } else if (abrirPdvApos && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum credito de devolucao para o PDV.')),
      );
    }

    if (_modoTroca && mounted) {
      await _oferecerEnvioDiferencaAoCaixa(
        vendaOrigem: v,
        registroId: registroId,
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _abrirBuscaProdutoTroca() async {
    final busca = TextEditingController();
    List<Produto> resultados = widget.produtoRepository.pesquisarPadraoPdv(
      '',
      limite: 50,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            void pesquisar() {
              resultados = widget.produtoRepository.pesquisarPadraoPdv(
                busca.text,
                limite: 50,
              );
              setD(() {});
            }

            return AlertDialog(
              title: const Text('Produto na troca'),
              content: SizedBox(
                width: 520,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: busca,
                      autofocus: true,
                      decoration: produtoBuscaInputDecoration(isDense: true),
                      onChanged: (_) => pesquisar(),
                      onSubmitted: (_) => pesquisar(),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final p = resultados[i];
                          return ListTile(
                            title: Text(p.nome),
                            subtitle: Text(
                              _formatarMoeda(
                                _precoProdutoTipo(p, 'preco1'),
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _linhasTroca.add(
                                  _LinhaTrocaEdit(produto: p),
                                );
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
    busca.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erroCarregamento != null || _venda == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Devolucao / troca')),
        body: Center(child: Text(_erroCarregamento ?? 'Erro')),
      );
    }

    final v = _venda!;
    final registros = widget.vendaRepository
            .listarRegistrosDevolucaoPorVenda(v.id)
        as List<RegistroDevolucao>;
    final Map<int, DevolucaoFiscalRegistro> fiscaisMap;
    if (widget.vendaRepository is VendaRepository) {
      final fiscalSvc = VendaFiscalService(
        vendaRepository: widget.vendaRepository as VendaRepository,
        clienteRepository: widget.clienteRepository,
      );
      fiscaisMap = mapaFiscalPorRegistro(fiscalSvc, registros);
    } else {
      fiscaisMap = const {};
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devolucao / troca'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            v.numeroOrcamento > 0
                ? 'Venda ${v.numeroOrcamento} (id ${v.id})'
                : 'Venda ${v.id}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          DevolucaoFiscalAvisoBanner(venda: v),
          if (registros.isNotEmpty) ...[
            const SizedBox(height: 12),
            DevolucaoFiscalHistoricoPanel(
              registros: registros,
              fiscaisPorRegistro: fiscaisMap,
            ),
          ],
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Devolucao')),
              ButtonSegment(value: true, label: Text('Troca')),
            ],
            selected: {_modoTroca},
            onSelectionChanged: (s) {
              setState(() => _modoTroca = s.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _modoTroca
                ? 'Itens voltam ao estoque; em seguida os produtos da troca saem do estoque.'
                : 'Apenas entrada de mercadoria devolvida no estoque.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_modoTroca) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.errorContainer.withValues(
                    alpha: 0.45,
                  ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Troca com nota fiscal nos produtos novos: use o modo Devolucao '
                  '(nao adicione saida aqui) e depois Registro + PDV + Caixa.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                ),
              ),
            ),
          ],
          if (!_modoTroca) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.tertiaryContainer.withValues(
                    alpha: 0.4,
                  ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Troca com nota (produtos novos)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1) Informe as quantidades devolvidas abaixo.\n'
                      '2) Registre a devolucao (e NF-e de devolucao, se houver).\n'
                      '3) Abra o PDV com o mesmo cliente e credito sugerido '
                      '${_formatarMoeda(_creditoSugeridoAtual())}.\n'
                      '4) Inclua os produtos novos, F10 ao caixa e emita a nota.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Itens da venda (quantidade a devolver)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._itens.map((ItemVenda item) {
            final maxD = item.quantidade - item.quantidadeDevolvida;
            final ctl = _qtdDevolucaoPorItem[item.id]!;
            final qDev = _parseQtd(ctl.text);
            final subDev = qDev * item.precoUnitario;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nomeProduto,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Vendido: ${item.quantidade} · Ja devolvido: ${item.quantidadeDevolvida} · Max: $maxD',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'Unit. ${_formatarMoeda(item.precoUnitario)}'
                          '${qDev > 0 ? ' · Subtotal devolvido: ${_formatarMoeda(subDev)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: qDev > 0 ? FontWeight.w600 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: ctl,
                      enabled: maxD > 0,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Qtd',
                        isDense: true,
                        errorText: qDev > maxD ? 'Max $maxD' : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_modoTroca) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Produtos da troca (saida)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _abrirBuscaProdutoTroca,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_linhasTroca.isEmpty)
              Text(
                'Nenhum produto adicionado.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ..._linhasTroca.asMap().entries.map((e) {
                final i = e.key;
                final linha = e.value;
                final unit = _precoProdutoTipo(linha.produto, linha.precoTipo);
                final qSaida = linha.quantidade;
                final subSaida = qSaida * unit;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(linha.produto.nome),
                    subtitle: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 88,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Qtd',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            controller: linha.qtdController,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        DropdownButton<String>(
                          value: linha.precoTipo,
                          items: const [
                            DropdownMenuItem(
                              value: 'preco1',
                              child: Text('Preco 1'),
                            ),
                            DropdownMenuItem(
                              value: 'preco2',
                              child: Text('Preco 2'),
                            ),
                            DropdownMenuItem(
                              value: 'preco3',
                              child: Text('Preco 3'),
                            ),
                          ],
                          onChanged: (nv) {
                            if (nv == null) return;
                            setState(() => linha.precoTipo = nv);
                          },
                        ),
                        Text('Unit. ${_formatarMoeda(unit)}'),
                        if (qSaida > 0)
                          Text(
                            'Subtotal: ${_formatarMoeda(subSaida)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() {
                          _linhasTroca.removeAt(i).dispose();
                        });
                      },
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            _buildResumoValoresTroca(context),
          ],
          if (!_modoTroca && _valorTotalDevolvido() > _epsValorTroca) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Valor devolvido (referencia)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      _formatarMoeda(_valorTotalDevolvido()),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _motivoController,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatorio)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsFinanceiraController,
            decoration: InputDecoration(
              labelText: 'Observacao financeira (opcional)',
              hintText: _modoTroca && _diferencaTroca().abs() > _epsValorTroca
                  ? (_diferencaTroca() > 0
                      ? 'Ex.: Complemento ${_formatarMoeda(_diferencaTroca())} enviado ao caixa'
                      : 'Ex.: Devolvido ${_formatarMoeda(-_diferencaTroca())} em dinheiro ao cliente')
                  : 'Ex.: R\$ devolvido em dinheiro, cliente pagou diferenca...',
            ),
            maxLines: 2,
          ),
          if (!_modoTroca && _creditoSugeridoAtual() > 0.004) ...[
            const SizedBox(height: 16),
            _buildOpcaoVale(context),
          ],
          if (_itensComQuantidadeInvalida.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quantidade acima do que ainda pode voltar em '
                    '${_itensComQuantidadeInvalida.map((i) => i.nomeProduto).join(', ')}. '
                    'Ajuste para continuar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _itensComQuantidadeInvalida.isEmpty
                ? () => _confirmar()
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Registrar'),
          ),
          if (!_modoTroca && _podeFluxoTrocaComNotaNoPdv) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _creditoSugeridoAtual() > 0.004 &&
                      _itensComQuantidadeInvalida.isEmpty
                  ? () => _confirmar(abrirPdvApos: true)
                  : null,
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Registrar devolucao e abrir PDV'),
            ),
          ],
        ],
      ),
    );
  }
}
