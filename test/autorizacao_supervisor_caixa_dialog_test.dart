import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/caixa/autorizacao_supervisor_caixa_dialog.dart';

void main() {
  testWidgets('senha incorreta preserva a contagem do fechamento', (
    tester,
  ) async {
    final dinheiro = TextEditingController(text: '350,00');
    addTearDown(dinheiro.dispose);
    var negadas = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Fechamento de caixa'),
                        content: TextField(
                          controller: dinheiro,
                          decoration: const InputDecoration(
                            labelText: 'Dinheiro',
                          ),
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () {
                              popDialogoSomenteSeAutorizado(
                                dialogContext: dialogContext,
                                autorizar: () {
                                  return showDialog<bool>(
                                    context: dialogContext,
                                    barrierDismissible: false,
                                    builder: (_) => AutorizacaoSupervisorCaixaDialog(
                                      mensagem:
                                          'Divergencia acima de R\$ 100,00. '
                                          'Informe credenciais de supervisor/administrador.',
                                      validarCredenciais: (login, senha) async =>
                                          false,
                                      aoCredencialNegada: () async {
                                        negadas++;
                                      },
                                    ),
                                  ).then((v) => v == true);
                                },
                              );
                            },
                            child: const Text('Confirmar fechamento'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Fechar caixa'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fechar caixa'));
    await tester.pumpAndSettle();
    expect(dinheiro.text, '350,00');

    await tester.tap(find.text('Confirmar fechamento'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextField);
    expect(campos, findsNWidgets(3));
    await tester.enterText(campos.at(1), 'supervisor');
    await tester.enterText(campos.at(2), 'errada');
    await tester.tap(find.text('Autorizar'));
    await tester.pumpAndSettle();

    expect(negadas, 1);
    expect(
      find.text('Credenciais sem permissao de supervisor/financeiro.'),
      findsOneWidget,
    );
    expect(find.text('Fechamento de caixa'), findsOneWidget);
    expect(dinheiro.text, '350,00');

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(negadas, 1);
    expect(find.text('Fechamento de caixa'), findsOneWidget);
    expect(find.text('Autorizacao de supervisor'), findsNothing);
    expect(dinheiro.text, '350,00');
  });

  testWidgets('senha correta fecha o fechamento', (tester) async {
    final dinheiro = TextEditingController(text: '80,00');
    addTearDown(dinheiro.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Fechamento de caixa'),
                        content: TextField(controller: dinheiro),
                        actions: [
                          ElevatedButton(
                            onPressed: () {
                              popDialogoSomenteSeAutorizado(
                                dialogContext: dialogContext,
                                autorizar: () {
                                  return showDialog<bool>(
                                    context: dialogContext,
                                    barrierDismissible: false,
                                    builder: (_) => AutorizacaoSupervisorCaixaDialog(
                                      mensagem: 'Divergencia acima do limite.',
                                      validarCredenciais: (login, senha) async =>
                                          login == 'gerente' && senha == '123',
                                    ),
                                  ).then((v) => v == true);
                                },
                              );
                            },
                            child: const Text('Confirmar fechamento'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Fechar caixa'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fechar caixa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar fechamento'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextField);
    await tester.enterText(campos.at(1), 'gerente');
    await tester.enterText(campos.at(2), '123');
    await tester.tap(find.text('Autorizar'));
    await tester.pumpAndSettle();

    expect(find.text('Fechamento de caixa'), findsNothing);
    expect(find.text('Autorizacao de supervisor'), findsNothing);
    expect(dinheiro.text, '80,00');
  });

  testWidgets('login vazio nao fecha o dialogo nem registra negativa', (
    tester,
  ) async {
    var chamadas = 0;
    var negadas = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    builder: (_) => AutorizacaoSupervisorCaixaDialog(
                      mensagem: 'Divergencia acima do limite.',
                      validarCredenciais: (login, senha) async {
                        chamadas++;
                        return false;
                      },
                      aoCredencialNegada: () async {
                        negadas++;
                      },
                    ),
                  );
                },
                child: const Text('Abrir'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autorizar'));
    await tester.pumpAndSettle();

    expect(chamadas, 0);
    expect(negadas, 0);
    expect(find.text('Preencha login e senha.'), findsOneWidget);
    expect(find.text('Autorizacao de supervisor'), findsOneWidget);
  });
}
