import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/models.dart';
import 'package:venera_next/features/comic_widgets/comic_tile.dart';
import 'package:venera_next/foundation/appdata.dart';

void main() {
  const description = '第二部 - 第100话：重新开始 - Page 23';
  const comic = Comic(
    'Book',
    '',
    'book',
    '',
    [],
    '',
    'missing-source',
    null,
    null,
  );

  setUp(() {
    configureComicWidgets(
      tileStateResolver: (_) => const ComicTileState(
        isFavorite: true,
        hasNewUpdate: true,
        historyPage: 23,
        historyMaxPage: 50,
        historyDescription: description,
      ),
    );
  });
  tearDown(configureComicWidgets);

  for (final dark in [false, true]) {
    for (final scale in [1.0, 3.0]) {
      testWidgets(
        'progress remains readable with dark=$dark and text scale=$scale',
        (tester) async {
          final oldMode = appdata.settings['comicDisplayMode'];
          appdata.settings['comicDisplayMode'] = 'brief';
          addTearDown(() => appdata.settings['comicDisplayMode'] = oldMode);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(
                    body: Wrap(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 180,
                          child: ComicTile(
                            comic: comic,
                            displayMode: ComicTileDisplayMode.gallery,
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          height: 240,
                          child: ComicTile(comic: comic),
                        ),
                        SizedBox(
                          width: 375,
                          height: 220,
                          child: ComicTile(
                            comic: comic,
                            displayMode: ComicTileDisplayMode.detailed,
                          ),
                        ),
                        SimpleComicTile(comic: comic),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(find.text(description), findsNWidgets(4));
            expect(find.byTooltip(description), findsNWidgets(4));
            expect(find.bySemanticsLabel(description), findsNWidgets(4));
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('disabling history badges hides progress', (tester) async {
    configureComicWidgets(tileStateResolver: (_) => const ComicTileState());
    await tester.pumpWidget(
      const MaterialApp(home: SimpleComicTile(comic: comic)),
    );
    expect(find.text(description), findsNothing);
  });
}
