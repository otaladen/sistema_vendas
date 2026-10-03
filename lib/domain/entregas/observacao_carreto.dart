import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';

/// Observacoes do carreto digitadas no PDV/fechamento.
///
/// Gravadas em [Venda.observacaoEntrega], que tambem recebe o historico do
/// patio/entregas (`[dd/MM/yyyy HH:mm] STATUS por ...`) e o legado
/// `Motorista: ...`. Edicao e impressao enxergam so o texto digitado; o
/// historico e preservado ao regravar.
abstract final class ObservacaoCarreto {
  static const String tituloImpressao = 'OBSERVAÇÕES DO CARRETO';

  static const int limiteCaracteres = 500;

  /// Frases comuns inseridas com um toque no modal.
  static const List<String> sugestoesRapidas = [
    'Ligar para o cliente antes de sair',
    'Rua estreita: só caminhão pequeno',
    'Descarregar na calçada',
    'Descarregar dentro da obra',
    'Precisa de ajudante na descarga',
    'Subir escada / andar superior',
    'Entregar somente pela manhã',
    'Entregar somente à tarde',
    'Conferir material com o cliente',
  ];

  static final RegExp _linhaMotoristaLegado = RegExp(
    r'^Motorista\s*:',
    caseSensitive: false,
  );

  /// Linhas digitadas na venda (sem historico do patio nem `Motorista:`).
  static List<String> linhasDigitadas(String observacaoGravada) =>
      EntregaVendaHelper.observacaoEntregaParaCliente(
        observacaoGravada,
      ).where((l) => !_linhaMotoristaLegado.hasMatch(l)).toList();

  /// Texto exibido no campo do modal.
  static String textoEditavel(String observacaoGravada) =>
      linhasDigitadas(observacaoGravada).join('\n');

  /// Remove linhas vazias e espacos nas pontas de cada linha.
  static String normalizar(String texto) => texto
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');

  /// Valor para gravar em [Venda.observacaoEntrega] apos editar no modal:
  /// texto digitado primeiro, historico interno preservado abaixo.
  static String mesclar(String observacaoGravada, String textoDigitado) {
    final digitado = normalizar(textoDigitado);
    if (digitado == textoEditavel(observacaoGravada)) {
      return observacaoGravada;
    }
    final historico = <String>[];
    for (final raw in observacaoGravada.split('\n')) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (_linhaMotoristaLegado.hasMatch(t)) {
        historico.add(t);
        continue;
      }
      final log = EntregaVendaHelper.trechoLogObservacaoEntrega(t);
      if (log != null) historico.add(log);
    }
    return [if (digitado.isNotEmpty) digitado, ...historico].join('\n');
  }

  /// Linhas em caixa alta para o bloco impresso.
  static List<String> linhasImpressao(Venda venda) => linhasDigitadas(
    venda.observacaoEntrega,
  ).map((l) => l.toUpperCase()).toList();

  /// Cupom/comprovante da venda: so quando o bloco de entrega tambem sai
  /// (carreto definido; cotacao sem endereco nao imprime).
  static List<String> linhasImpressaoComprovante(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    if (!EntregaVendaHelper.vendaDeveImprimirBlocoEntrega(
      venda,
      itens: itens,
    )) {
      return const [];
    }
    return linhasImpressao(venda);
  }

  /// Historico interno (patio/entregas), sem `Motorista:` legado.
  static List<String> linhasHistoricoInterno(Venda venda) {
    final out = <String>[];
    for (final raw in venda.observacaoEntrega.split('\n')) {
      final log = EntregaVendaHelper.trechoLogObservacaoEntrega(raw);
      if (log != null) out.add(log);
    }
    return out;
  }
}
