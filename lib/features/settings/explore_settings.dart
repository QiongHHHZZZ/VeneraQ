import 'package:flutter/material.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/translations.dart';

/// Picker for which pages a source's network favorites show.
///
/// It keeps its entry point beside the network-favorites list in the sidebar, so
/// it is not a settings row any more.
Widget setFavoritesPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.favoriteData != null) {
      pages[c.favoriteData!.key] = c.favoriteData!.title;
    }
  }
  return MultiPagesFilter(
    title: "Network Favorite Pages".tl,
    preference: DiscoveryPreferences.favoritePages,
    pages: pages,
  );
}
