// Gera docs/guia-tela-entregas.pdf — guia operacional da tela Entregas.
// Uso: dart run tool/gerar_guia_entregas_pdf.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Font> _carregarFonte(String url) async {
  final r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) {
    throw StateError('Falha ao baixar fonte: $url (${r.statusCode})');
  }
  return pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(r.bodyBytes)));
}

Future<void> main() async {
  final font = await _carregarFonte(
    'https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf',
  );
  final fontBold = await _carregarFonte(
    'https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Bold.ttf',
  );

  pw.TextStyle titulo([double size = 18]) => pw.TextStyle(
        font: fontBold,
        fontSize: size,
        fontWeight: pw.FontWeight.bold,
      );

  pw.TextStyle subtitulo([double size = 13]) => pw.TextStyle(
        font: fontBold,
        fontSize: size,
        fontWeight: pw.FontWeight.bold,
      );

  pw.TextStyle corpo([double size = 10.5]) => pw.TextStyle(
        font: font,
        fontSize: size,
        lineSpacing: 1.35,
      );

  pw.Widget espaco([double h = 8]) => pw.SizedBox(height: h);

  pw.Widget paragrafo(String texto) => pw.Text(texto, style: corpo());

  pw.Widget bullet(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8, bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('• ', style: corpo()),
            pw.Expanded(child: pw.Text(texto, style: corpo())),
          ],
        ),
      );

  pw.Widget secao(String tituloSecao, List<pw.Widget> filhos) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tituloSecao, style: subtitulo()),
          espaco(6),
          ...filhos,
          espaco(14),
        ],
      );

  final doc = pw.Document(
    title: 'Guia da tela Entregas',
    author: 'Sistema Vendas',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text('Guia da tela Entregas', style: titulo(22)),
        pw.Text(
          'Passo a passo para quem cuida das entregas na loja',
          style: corpo(11).copyWith(
            color: PdfColors.grey700,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        espaco(16),
        secao('O que é essa tela?', [
          paragrafo(
            'A tela Entregas é a lista de pedidos que a loja precisa levar até '
            'a casa do cliente. Aqui você organiza o carro, acompanha se já saiu, '
            'se chegou e quem recebeu a mercadoria.',
          ),
        ]),
        secao('Antes de começar', [
          bullet('Abra o sistema e faça login.'),
          bullet('Menu principal → Entregas.'),
          bullet(
            'Se não conseguir mudar status, peça permissão de '
            '"gerenciar entregas" ao gerente.',
          ),
          bullet(
            'Se a loja usa dois PCs na rede: o PC principal deve ter a '
            'sincronização ligada (Configurações → Rede).',
          ),
        ]),
        secao('As 3 abas', [
          bullet(
            'Montagem — montar o carro do dia: motorista, rota, romaneio, '
            'o que vai no caminhão.',
          ),
          bullet(
            'Lista — ver todos os pedidos, agrupados por bairro ou motorista.',
          ),
          bullet(
            'Kanban — arrastar cartões entre colunas (organizar visualmente).',
          ),
          paragrafo('Dica: de manhã use Montagem. Durante o dia use Lista ou Kanban.'),
        ]),
        secao('Palavras importantes', [
          bullet('Pendente — ainda não organizou / falta preparar.'),
          bullet('Roteirizada — já tem motorista e ordem; pronta para sair.'),
          bullet('Saiu para entrega — o carro já foi com a mercadoria.'),
          bullet('Entregue — o cliente recebeu.'),
          bullet('Complemento pendente — faltou algo; volta outra viagem.'),
          bullet('Carga 0/3 a 3/3 — checklist: Separado → Carregado → Saiu.'),
          bullet('POD — prova de entrega: quem recebeu (+ foto opcional).'),
        ]),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text('Rotina do dia', style: titulo(18)),
        espaco(12),
        secao('1. De manhã — preparar', [
          bullet('Entregas → aba Montagem.'),
          bullet('Selecione o dia de hoje no planejamento.'),
          bullet('Escolha o motorista.'),
          bullet('Confira paradas, carga consolidada e imprima romaneio se precisar.'),
          bullet('Coloque motorista em todo pedido que vai sair.'),
        ]),
        secao('2. Na expedição — separar e carregar', [
          bullet('Abra cada pedido (clique no card).'),
          bullet('Marque o checklist de carga em ordem:'),
          bullet('   Separado — produtos juntados.'),
          bullet('   Carregado — no carro.'),
          bullet('   Saiu — carro saiu da loja de verdade.'),
          paragrafo(
            'Regra: só marque Entregue quando a carga estiver 3/3 '
            '(Separado + Carregado + Saiu).',
          ),
        ]),
        secao('3. Quando o carro sai', [
          bullet('Mude o status para Saiu para entrega (Lista ou Kanban).'),
          bullet(
            'Motorista no celular: Modo motorista → vê só as entregas dele → '
            'Navegar → Entregue + POD.',
          ),
          paragrafo(
            'Na loja: deixe Roteirizado + checklist até Saiu antes do carro ir.',
          ),
        ]),
        secao('4. Quando o cliente recebe (POD)', [
          bullet('Ao marcar Entregue, aparece a janela de prova de entrega.'),
          bullet('Recebido por — OBRIGATÓRIO (nome de quem pegou).'),
          bullet('Foto — opcional, mas recomendada.'),
          bullet('Confirme. Aparece selo POD ok na lista.'),
          bullet('Para ver ou corrigir: Ver itens → painel POD → Alterar.'),
        ]),
        secao('5. Se faltou produto (complemento)', [
          bullet('1ª viagem: registre Complemento pendente (o que faltou).'),
          bullet('2ª viagem: marque Entregue → sistema pede POD do complemento.'),
        ]),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text('Kanban e Lista', style: titulo(18)),
        espaco(12),
        secao('Kanban — 4 colunas (esquerda → direita)', [
          bullet('Pendentes hoje'),
          bullet('Roteirizadas'),
          bullet('Saiu para entrega'),
          bullet('Entregue'),
          paragrafo('Arraste o card para a coluna certa. O sistema valida os passos.'),
        ]),
        secao('Lista — atalhos úteis', [
          bullet('Chips Atrasadas / Pendentes hoje — filtro rápido.'),
          bullet('Botão atualizar (↻) — recarrega a lista.'),
          bullet('Navegar — abre mapa; Ver itens — produtos e POD; Histórico — o que mudou.'),
        ]),
        secao('Checklist antes de ir embora', [
          bullet('Pedidos de hoje com motorista definido.'),
          bullet('Carga 3/3 nos que já saíram.'),
          bullet('Entregues com POD (nome de quem recebeu).'),
          bullet('Complementos anotados.'),
          bullet('Rede/sync ok, se usar dois PCs.'),
        ]),
        secao('O que NÃO fazer', [
          bullet('Entregue sem checklist 3/3 — bloqueado e estoque errado.'),
          bullet('Saiu antes do carro sair de verdade.'),
          bullet('Deixar Recebido por em branco — é obrigatório.'),
          bullet('Apagar dados no PC servidor da rede.'),
        ]),
        secao('Se der problema', [
          bullet('Não muda status → peça permissão ao gerente.'),
          bullet('Foto não aparece no outro PC → verifique Rede/sync e PC servidor.'),
          bullet('Motorista não vê entrega → nome no pedido = motorista do usuário.'),
          bullet('Pedido sumiu → limpe filtros e atualize a lista.'),
        ]),
        espaco(8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: PdfColors.blue200),
          ),
          child: pw.Text(
            'Resumo: Organize na Montagem → Separado / Carregado / Saiu → '
            'carro sai → Entregue com nome de quem recebeu (POD) → pronto.',
            style: corpo(11).copyWith(fontWeight: pw.FontWeight.bold),
          ),
        ),
        espaco(20),
        pw.Text(
          'Sistema Vendas — ${DateTime.now().day.toString().padLeft(2, '0')}/'
          '${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
          style: corpo(9).copyWith(color: PdfColors.grey600),
        ),
      ],
    ),
  );

  final dir = Directory('docs');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final out = File('docs/guia-tela-entregas.pdf');
  await out.writeAsBytes(await doc.save());

  // ignore: avoid_print
  print('PDF gerado: ${out.absolute.path}');
}
