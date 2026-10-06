import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/ui/widgets/cadastro_rapido_cliente_dialog.dart';
import 'package:sistema_vendas/ui/widgets/mascaras_cadastro_input.dart';

class _FakeClienteRepository {
  final Map<int, Cliente> _porId = {};
  var _proximoId = 1;

  Cliente? ultimoSalvo;

  int salvar(Cliente cliente) {
    final id = _proximoId++;
    final copia = Cliente(
      id: id,
      tipoPessoa: cliente.tipoPessoa,
      nomeRazao: cliente.nomeRazao,
      documento: cliente.documento,
      telefone: cliente.telefone,
      whatsapp: cliente.whatsapp,
      segmento: cliente.segmento,
      origemCadastro: cliente.origemCadastro,
      ativo: cliente.ativo,
      criadoEm: cliente.criadoEm,
      atualizadoEm: cliente.atualizadoEm,
    );
    _porId[id] = copia;
    ultimoSalvo = copia;
    return id;
  }

  Cliente? obterPorId(int id) => _porId[id];
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: SizedBox.shrink()),
    ),
  );
}

Future<void> _preencherCadastroMinimo(
  WidgetTester tester, {
  String? telefone,
}) async {
  final campos = find.byType(TextField);
  await tester.enterText(campos.at(0), '52998224725');
  await tester.pump();
  await tester.enterText(campos.at(1), 'Cliente Teste Telefone');
  await tester.pump();
  if (telefone != null) {
    await tester.enterText(campos.at(2), telefone);
    await tester.pump();
  }
}

void main() {
  testWidgets('modal exibe campo Telefone / WhatsApp', (tester) async {
    await _pumpHost(tester);
    final repo = _FakeClienteRepository();
    final hostContext = tester.element(find.byType(Scaffold));

    final dialogFuture = mostrarCadastroRapidoClienteDialog(
      hostContext,
      clienteRepository: repo,
    );
    await tester.pumpAndSettle();

    expect(find.text('Telefone / WhatsApp'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await dialogFuture, isNull);
  });

  testWidgets('salva cliente com telefone digitado (mascara e gravacao)', (
    tester,
  ) async {
    await _pumpHost(tester);
    final repo = _FakeClienteRepository();
    final hostContext = tester.element(find.byType(Scaffold));

    final dialogFuture = mostrarCadastroRapidoClienteDialog(
      hostContext,
      clienteRepository: repo,
    );
    await tester.pumpAndSettle();
    await _preencherCadastroMinimo(tester, telefone: '71999999999');

    final telefoneFormatado = TelefoneInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '71999999999'),
    );
    expect(telefoneFormatado.text, '(71) 99999-9999');

    await tester.tap(find.text('Salvar (Enter)'));
    await tester.pumpAndSettle();
    final salvo = await dialogFuture;

    expect(salvo, isNotNull);
    expect(salvo!.telefone, '71999999999');
    expect(salvo.nomeRazao, 'Cliente Teste Telefone');
    expect(repo.ultimoSalvo!.telefone, '71999999999');
  });

  testWidgets('salva cliente com telefone em branco', (tester) async {
    await _pumpHost(tester);
    final repo = _FakeClienteRepository();
    final hostContext = tester.element(find.byType(Scaffold));

    final dialogFuture = mostrarCadastroRapidoClienteDialog(
      hostContext,
      clienteRepository: repo,
    );
    await tester.pumpAndSettle();
    await _preencherCadastroMinimo(tester);

    await tester.tap(find.text('Salvar (Enter)'));
    await tester.pumpAndSettle();
    final salvo = await dialogFuture;

    expect(salvo, isNotNull);
    expect(salvo!.telefone, isEmpty);
    expect(repo.ultimoSalvo!.telefone, isEmpty);
  });
}
