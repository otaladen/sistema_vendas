import '../../data/cliente_repository.dart';
import '../../data/conferencia_carga_repository.dart';
import '../../data/conta_pagar_repository.dart';
import '../../data/fornecedor_repository.dart';
import '../../data/funcionario_repository.dart';
import '../../data/inventario_repository.dart';
import '../../data/kit_orcamento_repository.dart';
import '../../data/lista_compra_repository.dart';
import '../../data/mensagem_interna_repository.dart';
import '../../data/motorista_repository.dart';
import '../../data/movimento_estoque_repository.dart';
import '../../data/nfe_entrada_repository.dart';
import '../../data/objectbox.dart';
import '../../data/obrigacao_mensal_fixa_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/promocao_repository.dart';
import '../../data/recado_loja_repository.dart';
import '../../data/usuario_repository.dart';
import '../../data/vale_credito_repository.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';

/// Dependencias injetadas no LanApiServer (todos os repos ObjectBox do servidor).
class LanApiDeps {
  LanApiDeps({
    required this.objectBox,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.fornecedorRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.kitOrcamentoRepository,
    required this.promocaoRepository,
    required this.contaPagarRepository,
    required this.obrigacaoMensalFixaRepository,
    required this.listaCompraRepository,
    required this.inventarioRepository,
    required this.movimentoEstoqueRepository,
    required this.conferenciaCargaRepository,
    required this.nfeEntradaRepository,
    required this.usuarioRepository,
    required this.recadoLojaRepository,
    required this.mensagemInternaRepository,
    required this.valeCreditoRepository,
    required this.notificar,
    required this.notificarEvento,
    this.syncToken = '',
  });

  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final FornecedorRepository fornecedorRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final KitOrcamentoRepository kitOrcamentoRepository;
  final PromocaoRepository promocaoRepository;
  final ContaPagarRepository contaPagarRepository;
  final ObrigacaoMensalFixaRepository obrigacaoMensalFixaRepository;
  final ListaCompraRepository listaCompraRepository;
  final InventarioRepository inventarioRepository;
  final MovimentoEstoqueRepository movimentoEstoqueRepository;
  final ConferenciaCargaRepository conferenciaCargaRepository;
  final NfeEntradaRepository nfeEntradaRepository;
  final UsuarioRepository usuarioRepository;
  final RecadoLojaRepository recadoLojaRepository;
  final MensagemInternaRepository mensagemInternaRepository;
  final ValeCreditoRepository valeCreditoRepository;
  final String syncToken;
  final void Function(String entity, {List<int>? ids}) notificar;
  final void Function(String type, Map<String, dynamic> payload) notificarEvento;

  factory LanApiDeps.fromObjectBox(
    ObjectBox objectBox, {
    required String syncToken,
    required void Function(String entity, {List<int>? ids}) notificar,
    required void Function(String type, Map<String, dynamic> payload)
        notificarEvento,
  }) {
    final produto = ProdutoRepository(objectBox);
    final venda = VendaRepository(
      objectBox,
      onAposEscrita: produto.atualizarCacheAposMovimentoEstoque,
    );
    return LanApiDeps(
      objectBox: objectBox,
      produtoRepository: produto,
      clienteRepository: ClienteRepository(objectBox),
      fornecedorRepository: FornecedorRepository(objectBox),
      vendaRepository: venda,
      vendedorRepository: VendedorRepository(objectBox),
      funcionarioRepository: FuncionarioRepository(objectBox),
      motoristaRepository: MotoristaRepository(objectBox),
      kitOrcamentoRepository: KitOrcamentoRepository(objectBox),
      promocaoRepository: PromocaoRepository(objectBox),
      contaPagarRepository: ContaPagarRepository(objectBox),
      obrigacaoMensalFixaRepository: ObrigacaoMensalFixaRepository(objectBox),
      listaCompraRepository: ListaCompraRepository(objectBox),
      inventarioRepository: InventarioRepository(objectBox, produto),
      movimentoEstoqueRepository: MovimentoEstoqueRepository(objectBox),
      conferenciaCargaRepository: ConferenciaCargaRepository(objectBox),
      nfeEntradaRepository: NfeEntradaRepository(objectBox),
      usuarioRepository: UsuarioRepository(),
      recadoLojaRepository: RecadoLojaRepository(objectBox),
      mensagemInternaRepository: MensagemInternaRepository(
        storeDirectoryPath: objectBox.storeDirectoryPath,
      ),
      valeCreditoRepository: ValeCreditoRepository(objectBox),
      syncToken: syncToken,
      notificar: notificar,
      notificarEvento: notificarEvento,
    );
  }
}
