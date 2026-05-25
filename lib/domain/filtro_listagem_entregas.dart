import '../model/venda.dart';

/// Parametros de filtro da aba Entregas (lista, kanban e contadores).
class FiltroListagemEntregas {
  const FiltroListagemEntregas({
    this.statusEntrega = 'todos',
    this.bairroTermo = '',
    this.inicio,
    this.fim,
    this.filtroDataMarcada = 'todos',
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
  final String filtroMotorista;
  final String filtroVendedor;
  final String numeroNota;
  final bool apenasAtrasadas;
  final bool apenasPendentesHoje;

  /// Copia sem recorte de resumo (para contadores da barra).
  FiltroListagemEntregas paraContagemResumo() {
    return FiltroListagemEntregas(
      statusEntrega: statusEntrega,
      bairroTermo: bairroTermo,
      inicio: inicio,
      fim: fim,
      filtroDataMarcada: filtroDataMarcada,
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
