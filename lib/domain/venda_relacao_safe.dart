import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';

/// Acesso seguro a ToOne em vendas da API (entidade detached).
abstract final class VendaRelacaoSafe {
  VendaRelacaoSafe._();

  /// Nome/telefone vindos do JSON da LAN (ToOne nao vem hidratado no terminal).
  static final Expando<Cliente> _clienteSnapshot = Expando();

  static void aplicarSnapshotDoMap(Venda venda, Map<String, dynamic> m) {
    final nome = (m['nomeCliente'] ?? '').toString().trim();
    final tel = (m['clienteTelefone'] ?? '').toString().trim();
    final wa = (m['clienteWhatsapp'] ?? '').toString().trim();
    if (nome.isEmpty && tel.isEmpty && wa.isEmpty) return;
    _clienteSnapshot[venda] = Cliente(
      id: clienteId(venda),
      nomeRazao: nome.isEmpty ? 'Cliente' : nome,
      telefone: tel,
      whatsapp: wa,
    );
  }

  static void preencherMapaComCliente(Map<String, dynamic> m, Venda v) {
    Cliente? c;
    try {
      c = v.cliente.target;
    } catch (_) {}
    c ??= _clienteSnapshot[v];
    if (c == null) return;
    final nome = c.nomeRazao.trim();
    if (nome.isNotEmpty) m['nomeCliente'] = nome;
    final tel = c.telefone.trim();
    if (tel.isNotEmpty) m['clienteTelefone'] = tel;
    final wa = c.whatsapp.trim();
    if (wa.isNotEmpty) m['clienteWhatsapp'] = wa;
  }

  static Cliente? cliente(
    Venda venda, {
    dynamic clienteRepository,
  }) {
    try {
      final ligado = venda.cliente.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final snap = _clienteSnapshot[venda];
    if (snap != null) return snap;
    final id = clienteId(venda);
    if (id <= 0 || clienteRepository == null) return null;
    try {
      return clienteRepository.obterPorId(id) as Cliente?;
    } catch (_) {
      return null;
    }
  }

  static Vendedor? vendedor(
    Venda venda, {
    dynamic vendedorRepository,
  }) {
    try {
      final ligado = venda.vendedor.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = vendedorId(venda);
    if (id <= 0 || vendedorRepository == null) return null;
    try {
      return vendedorRepository.obterPorId(id) as Vendedor?;
    } catch (_) {
      return null;
    }
  }

  static String nomeCliente(
    Venda venda, {
    dynamic clienteRepository,
    String fallback = 'Sem cliente',
  }) {
    final c = cliente(venda, clienteRepository: clienteRepository);
    final n = c?.nomeRazao.trim() ?? '';
    if (n.isNotEmpty) return n;
    final id = clienteId(venda);
    if (id > 0) return 'Cliente #$id';
    return fallback;
  }

  static int clienteId(Venda venda) {
    try {
      return venda.cliente.targetId;
    } catch (_) {
      return 0;
    }
  }

  static int vendedorId(Venda venda) {
    try {
      return venda.vendedor.targetId;
    } catch (_) {
      return 0;
    }
  }

  static String nomeVendedor(
    Venda venda, {
    dynamic vendedorRepository,
    String fallback = 'Nao definido',
  }) {
    final v = vendedor(venda, vendedorRepository: vendedorRepository);
    if (v == null) return fallback;
    final apelido = v.apelido.trim();
    if (apelido.isNotEmpty) return apelido;
    final nome = v.nomeCompleto.trim();
    return nome.isEmpty ? fallback : nome;
  }
}
