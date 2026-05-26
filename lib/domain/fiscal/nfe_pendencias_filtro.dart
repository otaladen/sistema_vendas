import '../entrega_venda_helper.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'cliente_fiscal_helper.dart';
import 'nfe_pendencias_service.dart';

/// Filtros operacionais da fila de pendencias NF-e.
class NfePendenciasFiltro {
  const NfePendenciasFiltro({
    this.somenteCnpj = false,
    this.somenteComEntrega = false,
    this.valorMinimo = 0,
  });

  final bool somenteCnpj;
  final bool somenteComEntrega;
  final double valorMinimo;

  bool get ativo =>
      somenteCnpj || somenteComEntrega || valorMinimo > 0.009;

  NfePendenciasFiltro copyWith({
    bool? somenteCnpj,
    bool? somenteComEntrega,
    double? valorMinimo,
  }) {
    return NfePendenciasFiltro(
      somenteCnpj: somenteCnpj ?? this.somenteCnpj,
      somenteComEntrega: somenteComEntrega ?? this.somenteComEntrega,
      valorMinimo: valorMinimo ?? this.valorMinimo,
    );
  }

  static bool vendaComEntregaOuCarreto(Venda venda) {
    if (venda.valorFrete > 0.009) return true;
    if (venda.tipoEntrega == EntregaVendaHelper.tipoEntregaLoja) {
      return true;
    }
    if (venda.tipoEntrega == EntregaVendaHelper.tipoMisto) {
      return venda.itens.any(
        (i) =>
            EntregaVendaHelper.tipoEfetivoItem(i) ==
            EntregaVendaHelper.tipoEntregaLoja,
      );
    }
    return venda.itens.any(
      (i) => EntregaVendaHelper.itemEntraNaCargaEntrega(venda, i),
    );
  }

  bool aceita(NfePendenciaVenda pendencia) {
    final venda = pendencia.venda;
    final cliente = venda.cliente.target;
    if (somenteCnpj && !_clienteCnpj(cliente)) return false;
    if (somenteComEntrega && !vendaComEntregaOuCarreto(venda)) return false;
    if (valorMinimo > 0.009 && venda.total < valorMinimo) return false;
    return true;
  }

  static bool _clienteCnpj(Cliente? cliente) =>
      ClienteFiscalHelper.clienteExigeNfe55(cliente);

  List<NfePendenciaVenda> aplicar(List<NfePendenciaVenda> lista) {
    if (!ativo) return lista;
    return lista.where(aceita).toList();
  }
}
