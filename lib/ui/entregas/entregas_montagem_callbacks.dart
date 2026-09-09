import '../../model/venda.dart';
import 'romaneio_relatorios.dart';

/// Acoes da tela de entregas usadas pelo painel de montagem (delegacao do estado pai).
class EntregasMontagemCallbacks {
  const EntregasMontagemCallbacks({
    required this.atualizarChecklist,
    required this.atualizarStatus,
    required this.liberarSaida,
    required this.forcarSaidaRomaneio,
    required this.emitirRelatorio,
    required this.trocarParada,
    required this.trocarParadaMotorista,
    required this.editarMotoristaGrupo,
    required this.abrirDetalheItens,
    required this.abrirNavegacao,
    required this.recarregar,
    required this.confirmarAgrupamento,
    required this.removerAgrupamento,
    required this.editarMotoristaPedido,
    required this.definirMotoristaEmLote,
    required this.confirmarBuscarNaLoja,
  });

  final Future<bool> Function(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) atualizarChecklist;

  final Future<bool> Function(
    Venda venda,
    String novoStatus, {
    bool mostrarSnackSucesso,
  }) atualizarStatus;

  /// Checklist Separado+Carregado+Saiu + status `saiu_entrega` (+ estoque).
  final Future<bool> Function(
    Venda venda, {
    bool mostrarSnackSucesso,
    bool forcarSaidaRomaneio,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) liberarSaida;

  /// Destrava romaneio antigo ignorando reserva/conferencia de estoque.
  final Future<bool> Function(Venda venda) forcarSaidaRomaneio;

  final Future<void> Function({
    required RelatorioEntregaTipo tipo,
    String? motorista,
    List<Venda>? viagem,
    required bool salvarPdf,
  }) emitirRelatorio;

  final Future<void> Function(
    int grupoId,
    List<Venda> ordenadas,
    int indiceA,
    int indiceB,
  ) trocarParada;

  final Future<void> Function(
    String motorista,
    List<Venda> ordenadas,
    int indiceA,
    int indiceB,
  ) trocarParadaMotorista;

  final Future<void> Function(int grupoId, String motoristaAtual)
      editarMotoristaGrupo;

  final void Function(Venda venda) abrirDetalheItens;
  final void Function(Venda venda) abrirNavegacao;
  final Future<void> Function() recarregar;

  /// Agrupa pedidos selecionados (carreto finalizado; clientes podem ser diferentes).
  final Future<void> Function(Set<int> vendaIds) confirmarAgrupamento;

  /// Remove agrupamento das vendas selecionadas.
  final Future<void> Function(Set<int> vendaIds) removerAgrupamento;

  /// Um pedido avulso (fora de grupo).
  final Future<void> Function(Venda venda) editarMotoristaPedido;

  /// Mesmo motorista em varios pedidos (ids da lista visivel).
  final Future<void> Function(Set<int> vendaIds) definirMotoristaEmLote;

  /// Patio confirma itens que o motorista pediu para buscar nesta loja.
  final Future<void> Function(int vendaId, List<int> itemIds)
      confirmarBuscarNaLoja;
}
