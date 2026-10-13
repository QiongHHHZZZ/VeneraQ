import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';

void main() {
  testWidgets('ComicList stores mutable page data from unmodifiable results', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    const comic = Comic(
      'Cat Eye',
      '',
      'cat-eye',
      null,
      null,
      '',
      'webdav_library',
      null,
      null,
    );
    final oldListMode = appdata.settings['comicListDisplayMode'];
    final oldDisplayMode = appdata.settings['comicDisplayMode'];
    final oldBlockedWords = appdata.settings['blockedWords'];
    final oldFavoriteStatus = appdata.settings['showFavoriteStatusOnTile'];
    final oldHistoryStatus = appdata.settings['showHistoryStatusOnTile'];
    final oldUpdateStatus = appdata.settings['showUpdateStatusOnTile'];

    appdata.settings['comicListDisplayMode'] = 'paging';
    appdata.settings['comicDisplayMode'] = 'brief';
    appdata.settings['blockedWords'] = <String>[];
    appdata.settings['showFavoriteStatusOnTile'] = false;
    appdata.settings['showHistoryStatusOnTile'] = false;
    appdata.settings['showUpdateStatusOnTile'] = false;
    addTearDown(() {
      appdata.settings['comicListDisplayMode'] = oldListMode;
      appdata.settings['comicDisplayMode'] = oldDisplayMode;
      appdata.settings['blockedWords'] = oldBlockedWords;
      appdata.settings['showFavoriteStatusOnTile'] = oldFavoriteStatus;
      appdata.settings['showHistoryStatusOnTile'] = oldHistoryStatus;
      appdata.settings['showUpdateStatusOnTile'] = oldUpdateStatus;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: PageStorageBucket(),
            child: ComicList(
              key: key,
              enablePageStorage: true,
              loadPage: (_) async =>
                  Res(List<Comic>.unmodifiable([comic]), subData: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cat Eye'), findsOneWidget);
    expect(() => key.currentState!.remove(comic), returnsNormally);
    await tester.pump();
    expect(find.text('Cat Eye'), findsNothing);
  });
}
