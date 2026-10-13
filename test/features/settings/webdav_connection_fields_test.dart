import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/settings.dart';
import 'package:venera_next/foundation/translations.dart';

void main() {
  testWidgets('WebDavConnectionFields binds all connection controllers', (
    tester,
  ) async {
    await AppTranslation.init();
    final controllers = WebDavConnectionControllers(
      url: 'https://example.com/dav',
      user: 'user',
      password: 'pass',
      remotePath: '/manga/',
    );
    addTearDown(controllers.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebDavConnectionFields(
            controllers: controllers,
            remotePathHint: '/default/',
          ),
        ),
      ),
    );

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(4));
    expect(fields[0].controller, same(controllers.url));
    expect(fields[1].controller, same(controllers.user));
    expect(fields[2].controller, same(controllers.password));
    expect(fields[2].obscureText, isTrue);
    expect(fields[3].controller, same(controllers.remotePath));
    expect(fields[3].decoration?.hintText, '/default/');

    await tester.enterText(find.byType(TextField).first, 'https://new.example');
    expect(controllers.url.text, 'https://new.example');
  });
}
