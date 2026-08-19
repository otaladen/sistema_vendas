import '../model/venda.dart';
import 'entrega_nao_entregue.dart';

/// Status local da baixa do motorista (fila no aparelho).
abstract final class EntregaBaixaSyncStatus {
  static const aguardando = 'aguardando_sync';
  static const sincronizada = 'sincronizada';
}

/// Registro local de baixa POD ainda nao confirmada pelo PC servidor.
class EntregaBaixaPendente {
  const EntregaBaixaPendente({
    required this.vendaId,
    required this.recebidoPor,
    required this.usuarioLogin,
    this.fotoPathLocal = '',
    this.fotoPathServidor = '',
    this.statusAnterior = '',
    this.numeroOrcamento = 0,
    this.clienteNome = '',
    this.enderecoEntrega = '',
    this.motoristaEntrega = '',
    this.cargaSeparada = false,
    this.cargaCarregada = false,
    this.cargaSaiu = false,
    this.dataEntregaMarcadaIso = '',
    this.tipo = EntregaMotoristaAcao.entregue,
    this.motivoCodigo = '',
    this.motivoDetalhe = '',
    this.retornouParaLoja = false,
    required this.criadoEmIso,
  });

  final int vendaId;
  final String recebidoPor;
  final String usuarioLogin;
  final String fotoPathLocal;
  final String fotoPathServidor;
  final String statusAnterior;
  final int numeroOrcamento;
  final String clienteNome;
  final String enderecoEntrega;
  final String motoristaEntrega;
  final bool cargaSeparada;
  final bool cargaCarregada;
  final bool cargaSaiu;
  final String dataEntregaMarcadaIso;
  final String tipo;
  final String motivoCodigo;
  final String motivoDetalhe;
  final bool retornouParaLoja;
  final String criadoEmIso;

  bool get ehNaoEntregue => tipo == EntregaMotoristaAcao.naoEntregue;

  EntregaBaixaPendente copyWith({
    String? fotoPathServidor,
  }) {
    return EntregaBaixaPendente(
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: fotoPathLocal,
      fotoPathServidor: fotoPathServidor ?? this.fotoPathServidor,
      statusAnterior: statusAnterior,
      numeroOrcamento: numeroOrcamento,
      clienteNome: clienteNome,
      enderecoEntrega: enderecoEntrega,
      motoristaEntrega: motoristaEntrega,
      cargaSeparada: cargaSeparada,
      cargaCarregada: cargaCarregada,
      cargaSaiu: cargaSaiu,
      dataEntregaMarcadaIso: dataEntregaMarcadaIso,
      tipo: tipo,
      motivoCodigo: motivoCodigo,
      motivoDetalhe: motivoDetalhe,
      retornouParaLoja: retornouParaLoja,
      criadoEmIso: criadoEmIso,
    );
  }

  /// Venda minima para o card do motorista se o cache da API ainda nao hidratou.
  Venda paraVendaStub() {
    final v = Venda(
      id: vendaId,
      numeroOrcamento: numeroOrcamento,
      enderecoEntrega: enderecoEntrega,
      motoristaEntrega: motoristaEntrega,
      statusEntrega: statusAnterior.isEmpty ? 'saiu_entrega' : statusAnterior,
      cargaSeparada: cargaSeparada,
      cargaCarregada: cargaCarregada,
      cargaSaiu: cargaSaiu,
      podRecebidoPor: recebidoPor,
      podFotoPath: fotoPathLocal,
      podFotoPathServidor: fotoPathServidor,
    );
    if (ehNaoEntregue) {
      v.statusEntrega = 'reagendada';
    }
    final dt = DateTime.tryParse(dataEntregaMarcadaIso);
    if (dt != null) v.dataEntregaMarcada = dt.toUtc();
    return v;
  }

  Map<String, dynamic> toMap() => {
        'vendaId': vendaId,
        'recebidoPor': recebidoPor,
        'usuarioLogin': usuarioLogin,
        'fotoPathLocal': fotoPathLocal,
        'fotoPathServidor': fotoPathServidor,
        'statusAnterior': statusAnterior,
        'numeroOrcamento': numeroOrcamento,
        'clienteNome': clienteNome,
        'enderecoEntrega': enderecoEntrega,
        'motoristaEntrega': motoristaEntrega,
        'cargaSeparada': cargaSeparada,
        'cargaCarregada': cargaCarregada,
        'cargaSaiu': cargaSaiu,
        'dataEntregaMarcadaIso': dataEntregaMarcadaIso,
        'tipo': tipo,
        'motivoCodigo': motivoCodigo,
        'motivoDetalhe': motivoDetalhe,
        'retornouParaLoja': retornouParaLoja,
        'criadoEmIso': criadoEmIso,
      };

  factory EntregaBaixaPendente.fromMap(Map<String, dynamic> m) {
    return EntregaBaixaPendente(
      vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
      recebidoPor: (m['recebidoPor'] ?? '').toString(),
      usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
      fotoPathLocal: (m['fotoPathLocal'] ?? '').toString(),
      fotoPathServidor: (m['fotoPathServidor'] ?? '').toString(),
      statusAnterior: (m['statusAnterior'] ?? '').toString(),
      numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
      clienteNome: (m['clienteNome'] ?? '').toString(),
      enderecoEntrega: (m['enderecoEntrega'] ?? '').toString(),
      motoristaEntrega: (m['motoristaEntrega'] ?? '').toString(),
      cargaSeparada: m['cargaSeparada'] == true,
      cargaCarregada: m['cargaCarregada'] == true,
      cargaSaiu: m['cargaSaiu'] == true,
      dataEntregaMarcadaIso: (m['dataEntregaMarcadaIso'] ?? '').toString(),
      tipo: (m['tipo'] ?? EntregaMotoristaAcao.entregue).toString(),
      motivoCodigo: (m['motivoCodigo'] ?? '').toString(),
      motivoDetalhe: (m['motivoDetalhe'] ?? '').toString(),
      retornouParaLoja: m['retornouParaLoja'] == true,
      criadoEmIso: (m['criadoEmIso'] ?? '').toString(),
    );
  }

  static EntregaBaixaPendente deVenda({
    required Venda venda,
    required String recebidoPor,
    required String usuarioLogin,
    required String fotoPathLocal,
    required String fotoPathServidor,
    required String clienteNome,
  }) {
    return EntregaBaixaPendente(
      vendaId: venda.id,
      recebidoPor: recebidoPor.trim(),
      usuarioLogin: usuarioLogin.trim(),
      fotoPathLocal: fotoPathLocal.trim(),
      fotoPathServidor: fotoPathServidor.trim(),
      statusAnterior: venda.statusEntrega,
      numeroOrcamento: venda.numeroOrcamento,
      clienteNome: clienteNome.trim(),
      enderecoEntrega: venda.enderecoEntrega,
      motoristaEntrega: venda.motoristaEntrega,
      cargaSeparada: venda.cargaSeparada,
      cargaCarregada: venda.cargaCarregada,
      cargaSaiu: venda.cargaSaiu,
      dataEntregaMarcadaIso:
          venda.dataEntregaMarcada?.toUtc().toIso8601String() ?? '',
      tipo: EntregaMotoristaAcao.entregue,
      criadoEmIso: DateTime.now().toUtc().toIso8601String(),
    );
  }

  static EntregaBaixaPendente deNaoEntregue({
    required Venda venda,
    required String usuarioLogin,
    required String motivoCodigo,
    String motivoDetalhe = '',
    required String clienteNome,
    bool retornouParaLoja = false,
  }) {
    return EntregaBaixaPendente(
      vendaId: venda.id,
      recebidoPor: '',
      usuarioLogin: usuarioLogin.trim(),
      statusAnterior: venda.statusEntrega,
      numeroOrcamento: venda.numeroOrcamento,
      clienteNome: clienteNome.trim(),
      enderecoEntrega: venda.enderecoEntrega,
      motoristaEntrega: venda.motoristaEntrega,
      cargaSeparada: venda.cargaSeparada,
      cargaCarregada: venda.cargaCarregada,
      cargaSaiu: venda.cargaSaiu,
      dataEntregaMarcadaIso:
          venda.dataEntregaMarcada?.toUtc().toIso8601String() ?? '',
      tipo: EntregaMotoristaAcao.naoEntregue,
      motivoCodigo: motivoCodigo.trim(),
      motivoDetalhe: motivoDetalhe.trim(),
      retornouParaLoja: retornouParaLoja,
      criadoEmIso: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

/// Operacoes puras da fila (dedupe por venda).
abstract final class EntregaBaixaFila {
  static List<EntregaBaixaPendente> upsert(
    List<EntregaBaixaPendente> atual,
    EntregaBaixaPendente item,
  ) {
    if (item.vendaId <= 0) {
      return List<EntregaBaixaPendente>.from(atual);
    }
    if (item.ehNaoEntregue) {
      if (item.motivoCodigo.trim().isEmpty) {
        return List<EntregaBaixaPendente>.from(atual);
      }
    } else if (item.recebidoPor.trim().isEmpty) {
      return List<EntregaBaixaPendente>.from(atual);
    }
    final out = atual.where((e) => e.vendaId != item.vendaId).toList();
    out.add(item);
    out.sort((a, b) => a.criadoEmIso.compareTo(b.criadoEmIso));
    return out;
  }

  static List<EntregaBaixaPendente> remover(
    List<EntregaBaixaPendente> atual,
    int vendaId,
  ) {
    return atual.where((e) => e.vendaId != vendaId).toList();
  }

  static bool contem(List<EntregaBaixaPendente> atual, int vendaId) =>
      atual.any((e) => e.vendaId == vendaId);
}
