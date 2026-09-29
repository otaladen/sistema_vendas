import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/widgets/seletor_categoria_produto.dart';

void main() {
  testWidgets('navega por setor e seleciona subcategoria', (tester) async {
    SelecaoCategoriaProduto? escolhido;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                escolhido = await showSeletorCategoriaProduto(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('OBRA BRUTA'), findsOneWidget);
    expect(find.text('Cimento e Argamassas'), findsOneWidget);

    await tester.tap(find.text('Cimento e Argamassas'));
    await tester.pumpAndSettle();

    expect(find.text('Argamassa Colante'), findsOneWidget);
    await tester.tap(find.text('Argamassa Colante'));
    await tester.pumpAndSettle();

    expect(escolhido?.categoria, 'Cimento e Argamassas');
    expect(escolhido?.subcategoria, 'Argamassa Colante');
  });

  testWidgets('busca encontra subcategoria de outro setor', (tester) async {
    SelecaoCategoriaProduto? escolhido;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                escolhido = await showSeletorCategoriaProduto(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'porcelanato');
    await tester.pumpAndSettle();

    expect(find.textContaining('Pisos e Revestimentos'), findsOneWidget);
    await tester.tap(find.text('Porcelanato'));
    await tester.pumpAndSettle();

    expect(escolhido?.categoria, 'Pisos e Revestimentos');
    expect(escolhido?.subcategoria, 'Porcelanato');
  });
}
