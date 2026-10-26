import 'dart:math' as math;
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/image.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_locale.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/extensions.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'rating.dart';

typedef ComicPageBuilder =
    Widget Function({
      required String id,
      required String sourceKey,
      String? cover,
      String? title,
      int? heroID,
    });

typedef AddComicFavoriteHandler =
    Future<void> Function(BuildContext context, List<Comic> comics);
typedef ComicTileStateResolver = ComicTileState Function(Comic comic);
typedef ComicTileImageProviderResolver = ImageProvider? Function(Comic comic);
typedef ComicWidgetListenerRegistrar = void Function(VoidCallback listener);
typedef ComicFavoriteDisplayStateResolver =
    ComicFavoriteDisplayState Function();

class ComicTileState {
  const ComicTileState({this.chapterCount, this.unreadChapters});

  /// Chapters reported by the last update check, when known.
  final int? chapterCount;

  /// Chapters past the reader's last position, when both values are known.
  final int? unreadChapters;
}

class ComicFavoriteDisplayState {
  const ComicFavoriteDisplayState({
    this.isGallery = false,
  });

  final bool isGallery;
}

ComicPageBuilder? _comicPageBuilder;

AddComicFavoriteHandler? _addComicFavoriteHandler;
ComicTileStateResolver? _comicTileStateResolver;
ComicTileImageProviderResolver? _comicTileImageProviderResolver;
ComicWidgetListenerRegistrar? _addComicWidgetStateListener;
ComicWidgetListenerRegistrar? _removeComicWidgetStateListener;
ComicFavoriteDisplayStateResolver? _comicFavoriteDisplayStateResolver;

void configureComicWidgets({
  ComicPageBuilder? comicPageBuilder,
  AddComicFavoriteHandler? addFavorite,
  ComicTileStateResolver? tileStateResolver,
  ComicTileImageProviderResolver? tileImageProviderResolver,
  ComicWidgetListenerRegistrar? addStateListener,
  ComicWidgetListenerRegistrar? removeStateListener,
  ComicFavoriteDisplayStateResolver? favoriteDisplayStateResolver,
}) {
  _comicPageBuilder = comicPageBuilder;
  _addComicFavoriteHandler = addFavorite;
  _comicTileStateResolver = tileStateResolver;
  _comicTileImageProviderResolver = tileImageProviderResolver;
  _addComicWidgetStateListener = addStateListener;
  _removeComicWidgetStateListener = removeStateListener;
  _comicFavoriteDisplayStateResolver = favoriteDisplayStateResolver;
}

void addComicWidgetStateListener(VoidCallback listener) {
  _addComicWidgetStateListener?.call(listener);
}

void removeComicWidgetStateListener(VoidCallback listener) {
  _removeComicWidgetStateListener?.call(listener);
}

ComicFavoriteDisplayState comicFavoriteDisplayState() {
  return _comicFavoriteDisplayStateResolver?.call() ??
      const ComicFavoriteDisplayState();
}

Widget _buildComicPage({
  required String id,
  required String sourceKey,
  String? cover,
  String? title,
  int? heroID,
}) {
  final builder =
      _comicPageBuilder ??
      (throw StateError("Comic page builder is not configured."));
  return builder(
    id: id,
    sourceKey: sourceKey,
    cover: cover,
    title: title,
    heroID: heroID,
  );
}

void _openComicPage({
  BuildContext? context,
  required String id,
  required String sourceKey,
  String? cover,
  String? title,
  int? heroID,
}) {
  final targetContext =
      context ?? appNavigation.mainNavigatorKey?.currentContext;
  targetContext?.to(
    () => _buildComicPage(
      id: id,
      sourceKey: sourceKey,
      cover: cover,
      title: title,
      heroID: heroID,
    ),
  );
}

Future<void> _addComicToFavorites(BuildContext context, List<Comic> comics) {
  final handler =
      _addComicFavoriteHandler ??
      (throw StateError("Add comic favorite handler is not configured."));
  return handler(context, comics);
}

ImageProvider? _findImageProvider(Comic comic) {
  return _comicTileImageProviderResolver?.call(comic);
}

ComicTileState _tileState(Comic comic) {
  return _comicTileStateResolver?.call(comic) ?? const ComicTileState();
}

/// Chapters past the reader's position, drawn like the small square count
/// badge in the library: tight padding and square corners.
///
/// The fill uses the theme's primary container rather than a derived colour:
/// with the default blue seed the plain primary tone reads as grey in dark
/// mode, which made the count easy to miss. Container/onContainer keep the
/// intended accent contrast in both brightnesses.
///
/// [radius] rounds the pill used by the compact list row, where the count sits
/// beside the title instead of on the cover.
Widget _buildUnreadBadge(
  BuildContext context,
  int count, {
  double size = 24,
  double radius = 0,
}) {
  final scheme = context.colorScheme;
  return Container(
    height: size,
    constraints: BoxConstraints(minWidth: size),
    padding: EdgeInsets.symmetric(horizontal: size * 0.14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(
      count > 999 ? '999+' : '$count',
      style: TextStyle(
        color: scheme.onPrimaryContainer,
        fontSize: size * 0.5,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

enum ComicTileDisplayMode { detailed, gallery, compact }

class ComicTile extends StatelessWidget {
  const ComicTile({
    super.key,
    required this.comic,
    this.enableLongPressed = true,
    this.badge,
    this.menuOptions,
    this.onTap,
    this.onLongPressed,
    this.onBlocked,
    this.heroID,
    this.displayMode,
  });

  final Comic comic;

  final bool enableLongPressed;

  final String? badge;

  final List<MenuEntry>? menuOptions;

  final VoidCallback? onTap;

  final VoidCallback? onLongPressed;

  final VoidCallback? onBlocked;

  final int? heroID;

  final ComicTileDisplayMode? displayMode;

  void _onTap() {
    if (onTap != null) {
      onTap!();
      return;
    }
    _openComicPage(
      id: comic.id,
      sourceKey: comic.sourceKey,
      cover: comic.cover,
      title: comic.title,
      heroID: heroID,
    );
  }

  void _onLongPressed(BuildContext context) {
    if (onLongPressed != null) {
      onLongPressed!();
      return;
    }
    onLongPress(context);
  }

  void onLongPress(BuildContext context) {
    var renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var location = renderBox.localToGlobal(
      Offset((size.width - 242) / 2, size.height / 2),
    );
    showMenu(location, context);
  }

  void onSecondaryTap(TapDownDetails details, BuildContext context) {
    showMenu(details.globalPosition, context);
  }

  void showMenu(Offset location, BuildContext context) {
    ContextMenuRegion.of(context).show(context, location, [
      MenuEntry(
        icon: Icons.chrome_reader_mode_outlined,
        text: 'Details'.tl,
        onClick: () {
          _openComicPage(
            id: comic.id,
            sourceKey: comic.sourceKey,
            cover: comic.cover,
            title: comic.title,
          );
        },
      ),
      MenuEntry(
        icon: Icons.copy,
        text: 'Copy Title'.tl,
        onClick: () {
          Clipboard.setData(ClipboardData(text: comic.title));
          appNavigation.rootContext.showMessage(message: 'Title copied'.tl);
        },
      ),
      MenuEntry(
        icon: Icons.stars_outlined,
        text: 'Add to favorites'.tl,
        onClick: () {
          _addComicToFavorites(context, [comic]);
        },
      ),
      ...?menuOptions,
    ]);
  }

  @override
  Widget build(BuildContext context) => ContextMenuRegion(
    identity: comic,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final type = switch (displayMode) {
      ComicTileDisplayMode.detailed => 'detailed',
      ComicTileDisplayMode.gallery => 'gallery',
      ComicTileDisplayMode.compact => 'compact',
      null => GlobalPreferenceStore(
        appdata.settings,
      ).read(DiscoveryPreferences.comicDisplayMode),
    };

    final state = _tileState(comic);
    final unread = state.unreadChapters;

    // The compact row keeps the unread count inside itself, on the right, so it
    // does not use the cover overlay the other layouts share.
    if (type == 'compact') {
      return _buildCompactMode(context, unread);
    }

    Widget child = switch (type) {
      'detailed' => _buildDetailedMode(context),
      'gallery' => _buildGalleryMode(context),
      _ => _buildBriefMode(context),
    };

    // Only the unread count is drawn on the cover. The favorite bookmark and the
    // reading-progress badge used to sit here too, but they covered artwork
    // without telling the reader anything they act on from this screen.
    if (unread == null || unread <= 0) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = type == 'gallery' && constraints.maxWidth < 88;
        final badgeSize = compact ? 18.0 : 24.0;
        // Keep the badge clear of the cover's rounded corner. At the old 6px
        // inset it straddled the curve, so the badge looked like it was falling
        // off the artwork on gallery tiles.
        final inset = compact ? 6.0 : 10.0;
        return Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: type == 'detailed' ? 16 : inset,
              top: type == 'detailed' ? 8 : inset,
              right: type == 'detailed' ? 16 : inset,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUnreadBadge(
                      context,
                      unread,
                      size: badgeSize,
                      // Slightly rounded, matching the cover-corner badge in
                      // the reference library rather than a sharp square.
                      radius: badgeSize * 0.25,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildImage(BuildContext context) {
    var image = _findImageProvider(comic);
    if (image == null) {
      return const SizedBox();
    }
    return AnimatedImage(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  Widget _buildDetailedMode(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constrains) {
        final height = constrains.maxHeight - 16;

        Widget image = Container(
          width: height * 0.68,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: context.colorScheme.outlineVariant,
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return ClickInkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
            child: Row(
              children: [
                image,
                SizedBox.fromSize(size: const Size(16, 5)),
                Expanded(
                  child: _ComicDescription(
                    title: comic.maxPage == null
                        ? comic.title.replaceAll("\n", "")
                        : "[${comic.maxPage}P]${comic.title.replaceAll("\n", "")}",
                    subtitle: comic.subtitle ?? '',
                    description: comic.description,
                    badge: badge ?? comic.language,
                    tags: comic.tags,
                    maxLines: 2,
                    enableTranslate:
                        ComicSource.find(
                          comic.sourceKey,
                        )?.enableTagsTranslate ??
                        false,
                    rating: comic.stars,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One short row: square cover, title, and the unread count on the right.
  ///
  /// Sized to the library's list row: 56dp tall with 8dp vertical padding, so
  /// the square cover fills the remaining 40dp and the title takes the rest.
  Widget _buildCompactMode(BuildContext context, int? unread) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reproduces the library's list row exactly: a 56dp row with 8dp
        // vertical padding, leaving a 40dp square cover.
        //
        // Both numbers matter. The shelf's grid insets each row by 4dp for its
        // selection highlight, so the row box here is the cell minus that inset;
        // a larger padding shrank the cover and a smaller one made it oversized
        // against the reference.
        final rowHeight = constraints.maxHeight;
        final vertical = rowHeight >= 40 ? 8.0 : 2.0;
        final side = math.max(8.0, rowHeight - vertical * 2);
        Widget image = Container(
          key: const ValueKey('compact-cover'),
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );
        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }
        return ClickInkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
            child: Row(
              children: [
                image,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    comic.title.replaceAll('\n', ''),
                    // A short row cannot stack two lines without overflowing.
                    maxLines: rowHeight < 52 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (unread != null && unread > 0) ...[
                  const SizedBox(width: 12),
                  // A rounded rectangle rather than a full capsule, matching the
                  // count badge beside a title in the reference library.
                  _buildUnreadBadge(context, unread, size: 26, radius: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBriefMode(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget image = Container(
          decoration: BoxDecoration(
            color: context.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.toOpacity(0.2),
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return ClickInkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: image),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: (() {
                        final subtitle = comic.subtitle
                            ?.replaceAll('\n', '')
                            .trim();
                        final text = comic.description.isNotEmpty
                            ? comic.description.split('|').join('\n')
                            : (subtitle?.isNotEmpty == true ? subtitle : null);
                        final fortSize = constraints.maxWidth < 80
                            ? 8.0
                            : constraints.maxWidth < 150
                            ? 10.0
                            : 12.0;

                        if (text == null) {
                          return const SizedBox();
                        }

                        var children = <Widget>[];
                        var lines = text.split('\n');
                        lines.removeWhere((e) => e.trim().isEmpty);
                        if (lines.length > 3) {
                          lines = lines.sublist(0, 3);
                        }
                        for (var line in lines) {
                          children.add(
                            Container(
                              margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                              padding: constraints.maxWidth < 80
                                  ? const EdgeInsets.fromLTRB(3, 1, 3, 1)
                                  : constraints.maxWidth < 150
                                  ? const EdgeInsets.fromLTRB(4, 2, 4, 2)
                                  : const EdgeInsets.fromLTRB(5, 2, 5, 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black.toOpacity(0.5),
                              ),
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: fortSize,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: children,
                        );
                      })(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  comic.title.replaceAll('\n', ''),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ).paddingHorizontal(6).paddingVertical(8),
        );
      },
    );
  }

  Widget _buildGalleryMode(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 88;
        Widget image = Container(
          decoration: BoxDecoration(
            color: context.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.toOpacity(0.16),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (heroID != null) {
          image = Hero(tag: 'cover$heroID', child: image);
        }

        return ClickInkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(4, 5, 4, 4)
                : const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: image),
                SizedBox(height: compact ? 3 : 5),
                SizedBox(
                  height: compact ? 24 : 36,
                  child: Text(
                    comic.title.replaceAll('\n', ''),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


}


class _ComicDescription extends StatelessWidget {
  const _ComicDescription({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.enableTranslate,
    this.badge,
    this.maxLines = 2,
    this.tags,
    this.rating,
  });

  final String title;
  final String subtitle;
  final String description;
  final String? badge;
  final List<String>? tags;
  final int maxLines;
  final bool enableTranslate;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    final displayTags = [
      for (final tag in tags ?? const <String>[])
        if (tag.removeAllBlank.isNotEmpty) tag.replaceAll('\n', ' '),
    ];
    var enableTranslate =
        appLocale.languageCode == 'zh' && this.enableTranslate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title.trim(),
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.0),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
        if (subtitle != "")
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.0,
              color: context.colorScheme.onSurface.toOpacity(0.7),
            ),
            maxLines: 1,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        if (displayTags.isNotEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight < 22) {
                  return Container();
                }
                int cnt = (constraints.maxHeight - 22).toInt() ~/ 25;
                return Container(
                  clipBehavior: Clip.antiAlias,
                  height: 21 + cnt * 24,
                  width: double.infinity,
                  decoration: const BoxDecoration(),
                  child: Wrap(
                    runAlignment: WrapAlignment.start,
                    clipBehavior: Clip.antiAlias,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 4,
                    runSpacing: 3,
                    children: [
                      for (var s in displayTags)
                        Container(
                          height: 21,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.45,
                          ),
                          decoration: BoxDecoration(
                            color: s == "Unavailable"
                                ? context.colorScheme.errorContainer
                                : context.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              enableTranslate
                                  ? TagsTranslation.translateTag(s)
                                  : s.split(':').last,
                              style: const TextStyle(fontSize: 12),
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ).toAlign(Alignment.topCenter);
              },
            ),
          )
        else
          const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rating != null) StarRating(value: rating!, size: 18),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12.0),
                    maxLines: displayTags.isEmpty ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: Center(
                  child: Text(
                    "${badge![0].toUpperCase()}${badge!.substring(1).toLowerCase()}",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}


class SimpleComicTile extends StatelessWidget {
  const SimpleComicTile({
    super.key,
    required this.comic,
    this.onTap,
    this.withTitle = false,
    this.heroID,
    this.gaplessPlayback = false,
  });

  final Comic comic;

  final void Function()? onTap;

  final bool withTitle;

  final int? heroID;

  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    var image = _findImageProvider(comic);

    Widget child = image == null
        ? const SizedBox()
        : AnimatedImage(
            image: image,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: gaplessPlayback,
          );

    child = Container(
      width: 98,
      height: 136,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    // The reading-progress strip used to be drawn over the cover here. It told
    // the reader a page number they cannot act on from this screen, so the cover
    // is left clean.
    if (heroID != null) {
      child = Hero(tag: "cover$heroID", child: child);
    }

    child = AnimatedTapRegion(
      borderRadius: 8,
      onTap:
          onTap ??
          () {
            _openComicPage(
              context: context,
              id: comic.id,
              sourceKey: comic.sourceKey,
              cover: comic.cover,
              title: comic.title,
              heroID: heroID,
            );
          },
      child: child,
    );

    if (withTitle) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          SizedBox(
            width: 92,
            child: Center(
              child: Text(
                comic.title.replaceAll('\n', ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}
