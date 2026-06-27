import '../model/venda.dart';

/// Parametros de filtro da aba Entregas (lista, kanban e contadores).
class FiltroListagemEntregas {
  const FiltroListagemEntregas({
    this.statusEntrega = 'todos',
    this.bairroTermo = '',
    this.inicio,
    this.fim,
    this.filtroDataMarcada = 'todos',
    this.dataMarcadaInicio,
    this.dataMarcadaFim,
    this.dataMarcadaFiltradaNoBanco = false,
    this.filtroMotorista = 'todos',
    this.filtroVendedor = 'todos',
    this.numeroNota = '',
    this.apenasAtrasadas = false,
    this.apenasPendentesHoje = false,
  });

  final String statusEntrega;
  final String bairroTermo;
  final DateTime? inicio;
  final DateTime? fim;
  final String filtroDataMarcada;
  /// Inicio/fim do dia (local) para filtro indexado em [Venda.dataEntregaMarcada].
  final DateTime? dataMarcadaInicio;
  final DateTime? dataMarcadaFim;
  final bool dataMarcadaFiltradaNoBanco;
  final String filtroMotorista;
  final String filtroVendedor;
  final String numeroNota;
  final bool apenasAtrasadas;
  final bool apenasPendentesHoje;

  /// Copia sem recorte de resumo (para contadores da barra e mapa de dias).
  FiltroListagemEntregas paraContagemResumo() {
    return FiltroListagemEntregas(
      statusEntrega: statusEntrega,
      bairroTermo: bairroTermo,
      inicio: inicio,
      fim: fim,
      filtroDataMarcada: 'todos',
      filtroMotorista: filtroMotorista,
      filtroVendedor: filtroVendedor,
      numeroNota: numeroNota,
    );
  }
}

/// Resultado de uma carga da aba Entregas (lista + contadores).
class ResultadoListagemEntregas {
  const ResultadoListagemEntregas({
    required this.entregas,
    required this.atrasadas,
    required this.pendentesHoje,
  });

  final List<Venda> entregas;
  final int atrasadas;
  final int pendentesHoje;
}
