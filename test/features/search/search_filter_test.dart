import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/search/search.dart';

void main() {
  group('applySearchLanguageFilter', () {
    test('keeps query unchanged when setting is none', () {
      expect(
        applySearchLanguageFilter('tag', sourceKey: 'nhentai', setting: 'none'),
        'tag',
      );
    });

    test('adds language filter for supported sources', () {
      expect(
        applySearchLanguageFilter(
          'tag',
          sourceKey: 'nhentai',
          setting: 'chinese',
        ),
        'tag language:chinese',
      );
    });

    test('does not add language filter for unsupported sources', () {
      expect(
        applySearchLanguageFilter(
          'tag',
          sourceKey: 'example',
          setting: 'chinese',
        ),
        'tag',
      );
    });

    test('does not duplicate existing language filter', () {
      expect(
        applySearchLanguageFilter(
          'tag language:english',
          sourceKey: 'ehentai',
          setting: 'chinese',
        ),
        'tag language:english',
      );
    });
  });
}
