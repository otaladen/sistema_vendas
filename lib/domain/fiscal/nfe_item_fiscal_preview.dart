import '../../config/fiscal_config.dart';
import '../entregas/romaneio_carga_merge.dart';
import '../produto_nome_exibicao.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../services/fiscal_service.dart';
import 'grupo_tributario_produto.dart';
import 'nfe_cfop_resolver.dart';
import 'nfe_fiscal_helpers.dart';

/// Linha da grade de conferencia fiscal (pre-emissao NF-e).
class NfeItemFiscalPreview {
  const NfeItemFiscalPreview({
    required this.numero,
    required this.produtoId,
    required this.codigo,
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
    required this.ncm,
    required this.cest,
    required this.grupoRotulo,
    required this.cfop,
    required this.icmsCst,
    required this.pisCofinsCst,
    required this.gtin,
    required this.alertas,
    required this.bloqueiaEmissao,
  });

  final int numero;
  final int produtoId;
  final String codigo;
  final String descricao;
  final int quantidade;
  final double valorUnitario;
  final String ncm;
  final String cest;
  final String grupoRotulo;
  final String cfop;
  final String icmsCst;
  final String pisCofinsCst;
  final String gtin;
  final List<String> alertas;
  final bool bloqueiaEmissao;

  double get subtotal => quantidade * valorUnitario;
}

abstract final class NfeItemFiscalPreviewBuilder {
  NfeItemFiscalPreviewBuilder._();

  static List<NfeItemFiscalPreview> fromVenda(
    Venda venda, {
    required bool consumidorFinal,
    required String ufDestinatario,
    List<ItemVenda>? itens,
    Produto? Function(int produtoId)? resolverProduto,
  }) {
    final linhas = <NfeItemFiscalPreview>[];
    var numero = 1;
    final uf = ufDestinatario.trim().toUpperCase();
    final interestadual =
        uf.isNotEmpty && uf != FiscalConfig.ufEmitente.toUpperCase();
    final listaItens =
        itens ?? RomaneioCargaMerge.itensDaVendaSafe(venda);

    for (final item in listaItens) {
      if (item.quantidade <= 0) continue;
      Produto? produto;
      try {
        produto = item.produto.target;
      } catch (_) {
        produto = null;
      }
      var pid = 0;
      try {
        pid = item.produto.targetId;
      } catch (_) {
        pid = 0;
      }
      if (produto == null && pid > 0 && resolverProduto != null) {
        try {
          produto = resolverProduto(pid);
        } catch (_) {
          produto = null;
        }
      }
      if (produto == null) {
        linhas.add(
          NfeItemFiscalPreview(
            numero: numero++,
            produtoId: 0,
            codigo: '-',
            descricao: item.nomeProduto,
            quantidade: item.quantidade,
            valorUnitario: item.precoUnitario,
            ncm: '',
            cest: '',
            grupoRotulo: '-',
            cfop: '-',
            icmsCst: '-',
            pisCofinsCst: '-',
            gtin: '-',
            alertas: const ['Produto nao vinculado ao item da venda.'],
            bloqueiaEmissao: true,
          ),
        );
        continue;
      }

      final grupo = grupoTributarioProdutoDeString(produto.grupoTributario);
      final ncm = FiscalService.normalizarNcm(produto.ncm);
      final cest = FiscalService.normalizarCest(produto.cest);
      final alertas = <String>[];

      var bloqueia = false;
      if (ncm.length != 8 || ncm.replaceAll('0', '').isEmpty) {
        alertas.add('NCM invalido ou ausente (8 digitos).');
        bloqueia = true;
      }
      if (grupo == GrupoTributarioProduto.substituicaoTributaria &&
          cest.length != 7) {
        alertas.add('CEST obrigatorio para ST (7 digitos).');
        bloqueia = true;
      }
      if (interestadual && grupo == GrupoTributarioProduto.substituicaoTributaria) {
        alertas.add('Operacao interestadual com ST (CFOP ${FiscalConfig.cfopInterestadualSt}).');
      }
      if (interestadual && !consumidorFinal) {
        alertas.add('Venda interestadual para contribuinte.');
      }

      final cfop = NfeCfopResolver.resolver(
        produto: produto,
        ufDestinatario: uf,
        consumidorFinal: consumidorFinal,
      );

      linhas.add(
        NfeItemFiscalPreview(
          numero: numero++,
          produtoId: produto.id,
          codigo: produto.codigoInterno.trim().isEmpty
              ? 'ID-${produto.id}'
              : produto.codigoInterno.trim(),
          descricao: ProdutoNomeExibicao.paraImpressao(produto),
          quantidade: item.quantidade,
          valorUnitario: item.precoUnitario,
          ncm: ncm,
          cest: cest,
          grupoRotulo: grupo.rotulo,
          cfop: cfop,
          icmsCst: NfeFiscalHelpers.icmsCstProduto(produto),
          pisCofinsCst: NfeFiscalHelpers.pisCofinsCstProduto(produto),
          gtin: NfeFiscalHelpers.codigoGtinProduto(produto),
          alertas: alertas,
          bloqueiaEmissao: bloqueia,
        ),
      );
    }
    return linhas;
  }
}
