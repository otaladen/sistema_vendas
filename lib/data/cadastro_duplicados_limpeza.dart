import '../model/cliente.dart';
import '../model/funcionario.dart';
import '../model/kit_orcamento.dart';
import '../model/motorista.dart';
import '../model/promocao.dart';
import '../model/vendedor.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';
import 'usuario_repository.dart';

/// Resultado da limpeza de cadastros duplicados (sync LAN).
class CadastroDuplicadosLimpezaResultado {
  const CadastroDuplicadosLimpezaResultado({
    required this.vendedoresDesativados,
    required this.motoristasDesativados,
    required this.clientesDesativados,
    required this.funcionariosDesativados,
    required this.kitsDesativados,
    required this.promocoesDesativadas,
  });

  final int vendedoresDesativados;
  final int motoristasDesativados;
  final int clientesDesativados;
  final int funcionariosDesativados;
  final int kitsDesativados;
  final int promocoesDesativadas;

  bool get houveLimpeza =>
      vendedoresDesativados > 0 ||
      motoristasDesativados > 0 ||
      clientesDesativados > 0 ||
      funcionariosDesativados > 0 ||
      kitsDesativados > 0 ||
      promocoesDesativadas > 0;

  @override
  String toString() =>
      'vendedores=$vendedoresDesativados motoristas=$motoristasDesativados '
      'clientes=$clientesDesativados funcionarios=$funcionariosDesativados '
      'kits=$kitsDesativados promocoes=$promocoesDesativadas';
}

/// Une copias do mesmo cadastro geradas por sync sem remap/merge.
class CadastroDuplicadosLimpeza {
  CadastroDuplicadosLimpeza._();

  static Future<CadastroDuplicadosLimpezaResultado> executar(
    ObjectBox db,
  ) async {
    final v = _limparVendedores(db);
    final m = _limparMotoristas(db);
    final c = _limparClientes(db);
    final f = _limparFuncionarios(db);
    final k = _limparKits(db);
    final p = _limparPromocoes(db);
    await _alinharUsuariosVendedor(v.mapaRemap);

    return CadastroDuplicadosLimpezaResultado(
      vendedoresDesativados: v.desativados,
      motoristasDesativados: m.desativados,
      clientesDesativados: c.desativados,
      funcionariosDesativados: f.desativados,
      kitsDesativados: k.desativados,
      promocoesDesativadas: p.desativados,
    );
  }

  static String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  static ({int desativados, Map<int, int> mapaRemap}) _limparVendedores(
    ObjectBox db,
  ) {
    final grupos = <String, List<Vendedor>>{};
    for (final v in db.vendedorBox.getAll()) {
      final codigo = v.codigoInterno.trim().toLowerCase();
      final chave = codigo.isNotEmpty
          ? 'c:$codigo'
          : 'n:${v.nomeCompleto.trim().toLowerCase()}';
      if (chave == 'c:' || chave == 'n:') continue;
      (grupos[chave] ??= []).add(v);
    }

    var desativados = 0;
    final mapaRemap = <int, int>{};
    for (final lista in grupos.values) {
      if (lista.length < 2) continue;
      final canonico = _escolherVendedorCanonico(db, lista);
      for (final dup in lista) {
        if (dup.id == canonico.id) continue;
        mapaRemap[dup.id] = canonico.id;
        _reatribuirVendedor(db, de: dup.id, para: canonico);
        if (dup.ativo) {
          dup.ativo = false;
          if (!dup.nomeCompleto.toLowerCase().contains('(duplicado)')) {
            dup.nomeCompleto = '${dup.nomeCompleto.trim()} (duplicado)';
          }
          db.vendedorBox.put(dup);
          notificarAlteracaoParaRede(entidade: 'vendedor', entidadeId: dup.id);
          desativados++;
        }
      }
    }
    return (desativados: desativados, mapaRemap: mapaRemap);
  }

  static ({int desativados}) _limparMotoristas(ObjectBox db) {
    final grupos = <String, List<Motorista>>{};
    for (final m in db.motoristaBox.getAll()) {
      final chave = m.nome.trim().toLowerCase();
      if (chave.isEmpty) continue;
      (grupos[chave] ??= []).add(m);
    }

    var desativados = 0;
    for (final lista in grupos.values) {
      if (lista.length < 2) continue;
      final ordenada = [...lista]..sort((a, b) {
          if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
          return a.id.compareTo(b.id);
        });
      final canonico = ordenada.first;
      for (final dup in lista) {
        if (dup.id == canonico.id) continue;
        for (final f in db.funcionarioBox.getAll()) {
          if (f.motoristaId == dup.id) {
            f.motoristaId = canonico.id;
            db.funcionarioBox.put(f);
          }
        }
        if (dup.ativo) {
          dup.ativo = false;
          if (!dup.nome.toLowerCase().contains('(duplicado)')) {
            dup.nome = '${dup.nome.trim()} (duplicado)';
          }
          db.motoristaBox.put(dup);
          notificarAlteracaoParaRede(entidade: 'motorista', entidadeId: dup.id);
          desativados++;
        }
      }
    }
    return (desativados: desativados);
  }

  static ({int desativados}) _limparClientes(ObjectBox db) {
    final porDoc = <String, List<Cliente>>{};
    final porCodigo = <String, List<Cliente>>{};
    for (final c in db.clienteBox.getAll()) {
      final doc = _digitos(c.documento);
      if (doc.length >= 11) {
        (porDoc[doc] ??= []).add(c);
      }
      final codigo = c.codigoInterno.trim().toLowerCase();
      if (codigo.isNotEmpty) {
        (porCodigo[codigo] ??= []).add(c);
      }
    }

    var desativados = 0;
    final jaProcessados = <int>{};

    void processarGrupo(List<Cliente> lista) {
      final unicos = <int, Cliente>{};
      for (final c in lista) {
        unicos[c.id] = c;
      }
      final grupo = unicos.values.toList();
      if (grupo.length < 2) return;
      final canonico = _escolherClienteCanonico(db, grupo);
      for (final dup in grupo) {
        if (dup.id == canonico.id) continue;
        if (jaProcessados.contains(dup.id)) continue;
        jaProcessados.add(dup.id);
        _reatribuirCliente(db, de: dup.id, para: canonico);
        if (dup.ativo) {
          dup.ativo = false;
          if (!dup.nomeRazao.toLowerCase().contains('(duplicado)')) {
            dup.nomeRazao = '${dup.nomeRazao.trim()} (duplicado)';
          }
          db.clienteBox.put(dup);
          notificarAlteracaoParaRede(entidade: 'cliente', entidadeId: dup.id);
          desativados++;
        }
      }
    }

    for (final g in porDoc.values) {
      processarGrupo(g);
    }
    for (final g in porCodigo.values) {
      processarGrupo(g);
    }
    return (desativados: desativados);
  }

  static ({int desativados}) _limparFuncionarios(ObjectBox db) {
    final porCodigo = <String, List<Funcionario>>{};
    final porCpf = <String, List<Funcionario>>{};
    for (final f in db.funcionarioBox.getAll()) {
      final codigo = f.codigoInterno.trim().toLowerCase();
      if (codigo.isNotEmpty) (porCodigo[codigo] ??= []).add(f);
      final cpf = _digitos(f.cpf);
      if (cpf.length == 11) (porCpf[cpf] ??= []).add(f);
    }

    var desativados = 0;
    final ja = <int>{};

    void processar(List<Funcionario> lista) {
      final mapa = <int, Funcionario>{for (final f in lista) f.id: f};
      final grupo = mapa.values.toList();
      if (grupo.length < 2) return;
      final ordenada = [...grupo]..sort((a, b) {
          if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
          return a.id.compareTo(b.id);
        });
      final canonico = ordenada.first;
      for (final dup in grupo) {
        if (dup.id == canonico.id || ja.contains(dup.id)) continue;
        ja.add(dup.id);
        for (final l in db.lancamentoFuncionarioBox.getAll()) {
          if (l.funcionario.targetId == dup.id) {
            l.funcionario.target = canonico;
            db.lancamentoFuncionarioBox.put(l);
          }
        }
        for (final fe in db.fechamentoRhFuncionarioBox.getAll()) {
          if (fe.funcionarioId == dup.id) {
            fe.funcionarioId = canonico.id;
            db.fechamentoRhFuncionarioBox.put(fe);
          }
        }
        if (dup.ativo) {
          dup.ativo = false;
          if (!dup.nomeCompleto.toLowerCase().contains('(duplicado)')) {
            dup.nomeCompleto = '${dup.nomeCompleto.trim()} (duplicado)';
          }
          db.funcionarioBox.put(dup);
          notificarAlteracaoParaRede(
            entidade: 'funcionario',
            entidadeId: dup.id,
          );
          desativados++;
        }
      }
    }

    for (final g in porCodigo.values) {
      processar(g);
    }
    for (final g in porCpf.values) {
      processar(g);
    }
    return (desativados: desativados);
  }

  static ({int desativados}) _limparKits(ObjectBox db) {
    final grupos = <String, List<KitOrcamento>>{};
    for (final k in db.kitOrcamentoBox.getAll()) {
      final chave = k.nome.trim().toLowerCase();
      if (chave.isEmpty) continue;
      (grupos[chave] ??= []).add(k);
    }
    var desativados = 0;
    for (final lista in grupos.values) {
      if (lista.length < 2) continue;
      final ordenada = [...lista]..sort((a, b) {
          if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
          return a.id.compareTo(b.id);
        });
      final canonico = ordenada.first;
      for (final dup in lista) {
        if (dup.id == canonico.id) continue;
        for (final it in db.kitOrcamentoItemBox.getAll()) {
          if (it.kit.targetId == dup.id) {
            it.kit.targetId = canonico.id;
            db.kitOrcamentoItemBox.put(it);
          }
        }
        if (dup.ativo) {
          dup.ativo = false;
          if (!dup.nome.toLowerCase().contains('(duplicado)')) {
            dup.nome = '${dup.nome.trim()} (duplicado)';
          }
          db.kitOrcamentoBox.put(dup);
          notificarAlteracaoParaRede(
            entidade: 'kit_orcamento',
            entidadeId: dup.id,
          );
          desativados++;
        }
      }
    }
    return (desativados: desativados);
  }

  static ({int desativados}) _limparPromocoes(ObjectBox db) {
    final grupos = <String, List<Promocao>>{};
    for (final p in db.promocaoBox.getAll()) {
      final chave = p.nome.trim().toLowerCase();
      if (chave.isEmpty) continue;
      (grupos[chave] ??= []).add(p);
    }
    var desativados = 0;
    for (final lista in grupos.values) {
      if (lista.length < 2) continue;
      final ordenada = [...lista]..sort((a, b) {
          if (a.ativa != b.ativa) return a.ativa ? -1 : 1;
          return a.id.compareTo(b.id);
        });
      final canonico = ordenada.first;
      for (final dup in lista) {
        if (dup.id == canonico.id) continue;
        for (final it in db.promocaoItemBox.getAll()) {
          if (it.promocao.targetId == dup.id) {
            it.promocao.targetId = canonico.id;
            db.promocaoItemBox.put(it);
          }
        }
        for (final c in db.promocaoComboItemBox.getAll()) {
          if (c.promocao.targetId == dup.id) {
            c.promocao.targetId = canonico.id;
            db.promocaoComboItemBox.put(c);
          }
        }
        if (dup.ativa) {
          dup.ativa = false;
          if (!dup.nome.toLowerCase().contains('(duplicado)')) {
            dup.nome = '${dup.nome.trim()} (duplicado)';
          }
          db.promocaoBox.put(dup);
          notificarAlteracaoParaRede(entidade: 'promocao', entidadeId: dup.id);
          desativados++;
        }
      }
    }
    return (desativados: desativados);
  }

  static Vendedor _escolherVendedorCanonico(ObjectBox db, List<Vendedor> lista) {
    int vendasDe(int id) {
      var n = 0;
      for (final v in db.vendaBox.getAll()) {
        if (v.vendedor.targetId == id) n++;
      }
      return n;
    }

    final ordenada = [...lista];
    ordenada.sort((a, b) {
      final va = vendasDe(a.id);
      final vb = vendasDe(b.id);
      if (va != vb) return vb.compareTo(va);
      if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return ordenada.first;
  }

  static Cliente _escolherClienteCanonico(ObjectBox db, List<Cliente> lista) {
    int vendasDe(int id) {
      var n = 0;
      for (final v in db.vendaBox.getAll()) {
        if (v.cliente.targetId == id) n++;
      }
      return n;
    }

    final ordenada = [...lista];
    ordenada.sort((a, b) {
      final va = vendasDe(a.id);
      final vb = vendasDe(b.id);
      if (va != vb) return vb.compareTo(va);
      if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return ordenada.first;
  }

  static void _reatribuirVendedor(
    ObjectBox db, {
    required int de,
    required Vendedor para,
  }) {
    for (final v in db.vendaBox.getAll()) {
      if (v.vendedor.targetId == de) {
        v.vendedor.target = para;
        db.vendaBox.put(v);
      }
    }
    for (final f in db.funcionarioBox.getAll()) {
      if (f.vendedorId == de) {
        f.vendedorId = para.id;
        db.funcionarioBox.put(f);
      }
    }
    for (final c in db.clienteBox.getAll()) {
      if (c.vendedorResponsavelId == de) {
        c.vendedorResponsavelId = para.id;
        db.clienteBox.put(c);
      }
    }
  }

  static void _reatribuirCliente(
    ObjectBox db, {
    required int de,
    required Cliente para,
  }) {
    for (final v in db.vendaBox.getAll()) {
      if (v.cliente.targetId == de) {
        v.cliente.target = para;
        db.vendaBox.put(v);
      }
    }
    for (final t in db.tituloReceberBox.getAll()) {
      if (t.cliente.targetId == de) {
        t.cliente.target = para;
        db.tituloReceberBox.put(t);
      }
    }
  }

  static Future<void> _alinharUsuariosVendedor(Map<int, int> mapaRemap) async {
    if (mapaRemap.isEmpty) return;
    try {
      final repo = UsuarioRepository();
      final todos = await repo.listarTodos();
      for (final u in todos) {
        final novo = mapaRemap[u.vendedorId];
        if (novo == null || novo == u.vendedorId) continue;
        await repo.salvar(
          u.copyWith(vendedorId: novo),
          anterior: u,
          resumoExtra: 'Limpeza duplicados vendedorId',
        );
      }
    } catch (_) {}
  }
}
