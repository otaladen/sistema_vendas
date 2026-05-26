import '../../config/fiscal_config.dart';
import '../../model/produto.dart';
import 'grupo_tributario_produto.dart';

/// Valor vazio no cadastro = usar regra automatica (loja ou grupo tributario).
const String kFiscalValorAutomatico = '';

/// Opcao de dropdown (codigo + rotulo).
class OpcaoFiscalCadastro {
  const OpcaoFiscalCadastro(this.codigo, this.rotulo);

  final String codigo;
  final String rotulo;
}

/// Listas e resolucao de campos fiscais opcionais por produto.
class ProdutoFiscalCatalog {
  ProdutoFiscalCatalog._();

  static const OpcaoFiscalCadastro opcaoAutomatica = OpcaoFiscalCadastro(
    kFiscalValorAutomatico,
    'Automatico (loja / grupo)',
  );

  static const List<OpcaoFiscalCadastro> icmsOrigens = [
    opcaoAutomatica,
    OpcaoFiscalCadastro('0', '0 — Nacional'),
    OpcaoFiscalCadastro('1', '1 — Importada direta'),
    OpcaoFiscalCadastro('2', '2 — Importada mercado interno'),
    OpcaoFiscalCadastro('3', '3 — Nacional conteudo import. > 40%'),
    OpcaoFiscalCadastro('4', '4 — Nacional processos basicos'),
    OpcaoFiscalCadastro('5', '5 — Nacional conteudo import. <= 40%'),
    OpcaoFiscalCadastro('6', '6 — Estrangeira import. direta sem similar'),
    OpcaoFiscalCadastro('7', '7 — Estrangeira mercado interno sem similar'),
    OpcaoFiscalCadastro('8', '8 — Nacional conteudo import. > 70%'),
  ];

  /// CST ICMS mais usados no varejo (Regime Normal).
  static const List<OpcaoFiscalCadastro> icmsCstVenda = [
    opcaoAutomatica,
    OpcaoFiscalCadastro('00', '00 — Tributada integralmente'),
    OpcaoFiscalCadastro('10', '10 — Tributada com ST'),
    OpcaoFiscalCadastro('20', '20 — Com reducao de base'),
    OpcaoFiscalCadastro('40', '40 — Isenta'),
    OpcaoFiscalCadastro('41', '41 — Nao tributada'),
    OpcaoFiscalCadastro('50', '50 — Suspensao'),
    OpcaoFiscalCadastro('60', '60 — ICMS cobrado anteriormente por ST'),
    OpcaoFiscalCadastro('70', '70 — Com reducao e ST'),
    OpcaoFiscalCadastro('90', '90 — Outras'),
  ];

  static const List<OpcaoFiscalCadastro> pisCofinsCst = [
    opcaoAutomatica,
    OpcaoFiscalCadastro('01', '01 — Operacao tributavel (basica)'),
    OpcaoFiscalCadastro('02', '02 — Tributavel aliquota diferenciada'),
    OpcaoFiscalCadastro('04', '04 — Monofasica revenda aliquota zero'),
    OpcaoFiscalCadastro('06', '06 — Aliquota zero'),
    OpcaoFiscalCadastro('07', '07 — Isenta'),
    OpcaoFiscalCadastro('08', '08 — Sem incidencia'),
    OpcaoFiscalCadastro('09', '09 — Suspensao'),
    OpcaoFiscalCadastro('49', '49 — Outras saidas'),
  ];

  static String resolverIcmsOrigem(Produto produto) {
    final v = produto.icmsOrigem.trim();
    if (v.length == 1 && RegExp(r'^[0-8]$').hasMatch(v)) {
      return v;
    }
    return FiscalConfig.icmsOrigemPadrao;
  }

  static String resolverIcmsSituacaoTributaria(
    Produto produto, {
    required String icmsPadraoLoja,
  }) {
    final cadastro = produto.icmsSituacaoTributaria.trim();
    if (cadastro.length == 2 && RegExp(r'^\d{2}$').hasMatch(cadastro)) {
      return cadastro;
    }
    final grupo = grupoTributarioProdutoDeString(produto.grupoTributario);
    switch (grupo) {
      case GrupoTributarioProduto.isento:
        return '40';
      case GrupoTributarioProduto.substituicaoTributaria:
        return '60';
      case GrupoTributarioProduto.tributado:
        return icmsPadraoLoja;
    }
  }

  static String resolverPisCofinsSituacaoTributaria(
    Produto produto, {
    required String pisCofinsPadraoLoja,
  }) {
    final cadastro = produto.pisCofinsSituacaoTributaria.trim();
    if (cadastro.length == 2 && RegExp(r'^\d{2}$').hasMatch(cadastro)) {
      return cadastro;
    }
    return pisCofinsPadraoLoja;
  }

  static String? validarCestParaGrupo({
    required String? cestDigitos,
    required String grupoTributarioCodigo,
  }) {
    final digits = (cestDigitos ?? '').replaceAll(RegExp(r'\D'), '');
    final grupo = grupoTributarioProdutoDeString(grupoTributarioCodigo);
    if (grupo == GrupoTributarioProduto.substituicaoTributaria) {
      if (digits.isEmpty) {
        return 'CEST obrigatorio para produtos com Substituicao Tributaria (7 digitos).';
      }
      if (digits.length != 7) {
        return 'CEST deve ter exatamente 7 digitos.';
      }
      return null;
    }
    if (digits.isEmpty) return null;
    if (digits.length != 7) {
      return 'CEST deve ter 7 digitos quando informado.';
    }
    return null;
  }
}
