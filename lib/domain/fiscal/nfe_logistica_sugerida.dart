import '../entrega_venda_helper.dart';
import '../../model/venda.dart';
import 'peso_carga_venda_estimador.dart';

/// Sugestao de transporte na NF-e conforme tipo de entrega da venda.
class NfeLogisticaSugerida {
  const NfeLogisticaSugerida({
    required this.modalidadeFrete,
    required this.volumes,
    required this.pesoBrutoKg,
    required this.placaVeiculo,
    required this.rotuloModalidade,
    required this.mensagem,
    required this.temTransporteLoja,
  });

  /// 0 CIF | 1 FOB | 9 sem ocorrencia de transporte.
  final int modalidadeFrete;
  final int volumes;
  final double pesoBrutoKg;
  final String placaVeiculo;
  final String rotuloModalidade;
  final String mensagem;
  final bool temTransporteLoja;

  static NfeLogisticaSugerida calcular(Venda venda) {
    EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(venda);

    final temFrete = venda.valorFrete > 0.009;
    final temCarreto = _vendaTemCarretoOuEntrega(venda);
    final temTransporte = temFrete || temCarreto;

    if (!temTransporte) {
      final est = PesoCargaVendaEstimador.estimar(venda);
      return NfeLogisticaSugerida(
        modalidadeFrete: 9,
        volumes: 1,
        pesoBrutoKg: est.pesoBrutoKg > 0 ? est.pesoBrutoKg : 1,
        placaVeiculo: '',
        rotuloModalidade: 'Sem ocorrencia de transporte (9)',
        mensagem:
            'Venda somente retirada na loja (leva agora). '
            'Modalidade 9 — sem transporte na nota. Volumes/peso minimos para o XML.',
        temTransporteLoja: false,
      );
    }

    final est = PesoCargaVendaEstimador.estimarItensComTransporte(venda);
    final placa = _extrairPlacaSugerida(venda);
    final partes = <String>[];
    if (temCarreto) partes.add('carreto/entrega');
    if (temFrete) {
      partes.add('frete R\$ ${venda.valorFrete.toStringAsFixed(2)}');
    }

    return NfeLogisticaSugerida(
      modalidadeFrete: 0,
      volumes: est.volumes,
      pesoBrutoKg: est.pesoBrutoKg,
      placaVeiculo: placa,
      rotuloModalidade: 'CIF — emitente (0)',
      mensagem:
          'Venda com ${partes.join(" · ")}. '
          'Peso/volumes calculados nos itens que saem no carreto.'
          '${placa.isNotEmpty ? " Placa sugerida: $placa." : ""}',
      temTransporteLoja: true,
    );
  }

  static bool _vendaTemCarretoOuEntrega(Venda venda) {
    if (venda.tipoEntrega == EntregaVendaHelper.tipoEntregaLoja) {
      return true;
    }
    if (venda.tipoEntrega == EntregaVendaHelper.tipoMisto) {
      return venda.itens.any(
        (i) =>
            EntregaVendaHelper.tipoEfetivoItem(i) ==
                EntregaVendaHelper.tipoEntregaLoja ||
            EntregaVendaHelper.itemEntraNaCargaEntrega(venda, i),
      );
    }
    return venda.itens.any(
      (i) => EntregaVendaHelper.itemEntraNaCargaEntrega(venda, i),
    );
  }

  static String _extrairPlacaSugerida(Venda venda) {
    final raw = venda.caminhaoEntrega.trim();
    if (raw.isEmpty) return '';
    final placa = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (placa.length >= 7) return placa;
    return '';
  }
}
