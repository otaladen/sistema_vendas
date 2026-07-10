import 'dart:math' as math;

import '../data/app_config_repository.dart';
import '../data/produto_repository.dart';
import '../model/produto.dart';
import 'obra_calculadora.dart';
import 'pdv_estoque_semaforo_util.dart';
import 'produto_embalagem.dart';

class PdvObraCalculadoraLinhaInsercao {
  const PdvObraCalculadoraLinhaInsercao({
    required this.produto,
    required this.quantidade,
    required this.material,
    this.substitutoAplicado = false,
    this.produtoOriginalNome,
  });

  final Produto produto;
  final double quantidade;
  final ObraCalculadoraMaterialCalculado material;
  final bool substitutoAplicado;
  final String? produtoOriginalNome;
}

class PdvObraCalculadoraMontagem {
  const PdvObraCalculadoraMontagem({
    required this.linhas,
    required this.resultado,
    this.errosConfig = const [],
    this.avisos = const [],
  });

  final List<PdvObraCalculadoraLinhaInsercao> linhas;
  final ObraCalculadoraResultado resultado;
  final List<String> errosConfig;
  final List<String> avisos;

  bool get podeInserir => linhas.isNotEmpty && errosConfig.isEmpty;
}

abstract final class PdvObraCalculadoraInsercaoUtil {
  PdvObraCalculadoraInsercaoUtil._();

  static PdvObraCalculadoraMontagem montar({
    required ObraCalculadoraResultado resultado,
    required EmpresaConfig config,
    required ProdutoRepository produtoRepository,
  }) {
    final erros = <String>[];
    final avisos = <String>[ObraCalculadora.avisoEstimativa];
    final linhas = <PdvObraCalculadoraLinhaInsercao>[];

    for (final mat in resultado.materiais) {
      final id = _produtoId(config, mat.papel);
      if (id <= 0) {
        if (mat.papel == ObraMaterialPapel.ferro) continue;
        erros.add(_rotuloPapel(mat.papel));
        continue;
      }
      final p = produtoRepository.obterPorId(id);
      if (p == null || !p.ativo) {
        erros.add('${_rotuloPapel(mat.papel)} (produto #$id inativo ou removido)');
        continue;
      }

      final resolvido = _resolverProduto(
        produto: p,
        config: config,
        produtoRepository: produtoRepository,
        avisos: avisos,
      );

      final q = _quantidadeParaProduto(resolvido.produto, mat);
      if (q <= 0) continue;
      if ((mat.papel == ObraMaterialPapel.areia ||
              mat.papel == ObraMaterialPapel.brita) &&
          q > mat.quantidade + 0.001) {
        avisos.add(
          '${mat.rotulo}: calculado ${mat.quantidade.toStringAsFixed(2)} m³ · '
          'venda ${q.toStringAsFixed(2).replaceAll('.', ',')} m³',
        );
      }
      linhas.add(
        PdvObraCalculadoraLinhaInsercao(
          produto: resolvido.produto,
          quantidade: q,
          material: mat,
          substitutoAplicado: resolvido.substituto,
          produtoOriginalNome:
              resolvido.substituto ? resolvido.nomeOriginal : null,
        ),
      );
    }

    return PdvObraCalculadoraMontagem(
      linhas: linhas,
      resultado: resultado,
      errosConfig: erros,
      avisos: avisos,
    );
  }

  static ({Produto produto, bool substituto, String nomeOriginal}) _resolverProduto({
    required Produto produto,
    required EmpresaConfig config,
    required ProdutoRepository produtoRepository,
    required List<String> avisos,
  }) {
    if (!config.obraCalcUsarSubstitutoEstoqueZero) {
      return (produto: produto, substituto: false, nomeOriginal: produto.nome);
    }
    if (PdvEstoqueSemaforoUtil.nivelDe(produto) !=
        PdvEstoqueSemaforoNivel.vermelho) {
      return (produto: produto, substituto: false, nomeOriginal: produto.nome);
    }

    final subs = produtoRepository.listarSubstitutosCadastrados(produto.id);
    Produto? escolhido;
    for (final s in subs) {
      if (PdvEstoqueSemaforoUtil.nivelDe(s) !=
          PdvEstoqueSemaforoNivel.vermelho) {
        escolhido = s;
        break;
      }
    }
    escolhido ??= subs.isNotEmpty ? subs.first : null;
    if (escolhido != null && escolhido.id != produto.id) {
      avisos.add('${produto.nome} → ${escolhido.nome} (substituto)');
      return (
        produto: escolhido,
        substituto: true,
        nomeOriginal: produto.nome,
      );
    }
    return (produto: produto, substituto: false, nomeOriginal: produto.nome);
  }

  static double m2PorCaixaDoProduto(Produto produto) {
    final f = produto.quantidadePorEmbalagem;
    if (f > 0.01) return f;
    return 1.44;
  }

  static int _produtoId(EmpresaConfig c, ObraMaterialPapel papel) =>
      switch (papel) {
        ObraMaterialPapel.tijolo => c.obraCalcTijoloProdutoId,
        ObraMaterialPapel.cimento => c.obraCalcCimentoProdutoId,
        ObraMaterialPapel.areia => c.obraCalcAreiaProdutoId,
        ObraMaterialPapel.pisoRevestimento => c.obraCalcPisoProdutoId,
        ObraMaterialPapel.brita => c.obraCalcBritaProdutoId,
        ObraMaterialPapel.telha => c.obraCalcTelhaProdutoId,
        ObraMaterialPapel.ferro => c.obraCalcFerroProdutoId,
      };

  static String _rotuloPapel(ObraMaterialPapel p) => switch (p) {
        ObraMaterialPapel.tijolo => 'Tijolo nao configurado',
        ObraMaterialPapel.cimento => 'Cimento nao configurado',
        ObraMaterialPapel.areia => 'Areia nao configurada',
        ObraMaterialPapel.pisoRevestimento => 'Piso/revestimento nao configurado',
        ObraMaterialPapel.brita => 'Brita nao configurada',
        ObraMaterialPapel.telha => 'Telha nao configurada',
        ObraMaterialPapel.ferro => 'Ferro nao configurado',
      };

  /// Passo de venda em m³ (ex.: 0,50). Usa fator do produto quando != 1.
  static double passoM3Venda(
    Produto produto, {
    double passoPadrao = 0.50,
  }) {
    final f = produto.quantidadePorEmbalagem;
    if (f > 0.01 && (f - 1).abs() > 0.001) return f;
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    if (u == 'M3' || u == 'M') return passoPadrao;
    if (f > 0.01) return f;
    return passoPadrao;
  }

  /// Arredonda volume para cima ao multiplo do passo (0,24 → 0,50).
  static double arredondarVolumeM3ParaVenda(
    double volumeM3,
    Produto produto, {
    double passoPadrao = 0.50,
  }) {
    if (volumeM3 <= 0) return 0;
    final passo = passoM3Venda(produto, passoPadrao: passoPadrao);
    if (passo <= 0) return volumeM3;
    final multiplos = (volumeM3 / passo).ceil();
    return (multiplos * passo * 100).roundToDouble() / 100;
  }

  static double _quantidadeVolumeGranular(
    Produto produto,
    double volumeM3, {
    double passoPadrao = 0.50,
  }) {
    if (volumeM3 <= 0) return 0;
    final passo = passoM3Venda(produto, passoPadrao: passoPadrao);
    final m3Venda = arredondarVolumeM3ParaVenda(
      volumeM3,
      produto,
      passoPadrao: passoPadrao,
    );
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);

    if (u == 'M3' || u == 'M') {
      return m3Venda;
    }
    // UN/CX etc.: cada unidade equivale a [passo] m³.
    if (passo <= 0) return volumeM3.ceilToDouble();
    return math.max(1, (m3Venda / passo).ceilToDouble());
  }

  static double _quantidadeParaProduto(
    Produto produto,
    ObraCalculadoraMaterialCalculado mat,
  ) {
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    switch (mat.papel) {
      case ObraMaterialPapel.tijolo:
      case ObraMaterialPapel.telha:
        return mat.quantidade.ceilToDouble();
      case ObraMaterialPapel.cimento:
        if (u == 'SC' || u == 'UN') {
          return mat.quantidade.ceilToDouble();
        }
        return mat.quantidade;
      case ObraMaterialPapel.areia:
      case ObraMaterialPapel.brita:
        return _quantidadeVolumeGranular(produto, mat.quantidade);
      case ObraMaterialPapel.ferro:
        if (u == 'KG' || produto.permiteQuantidadeFracionada) {
          return mat.quantidade;
        }
        return mat.quantidade.ceilToDouble();
      case ObraMaterialPapel.pisoRevestimento:
        return mat.quantidade.ceilToDouble();
    }
  }
}
