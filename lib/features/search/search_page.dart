import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/flyout.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/foundation/app_locale.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/global_state.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/routing/app_links.dart';
import 'package:venera_next/foundation/extensions.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'package:venera_next/features/comic_details/comic_details.dart';
import 'aggregated_search_page.dart';
import 'search_shortcuts.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final SearchBarController controller;

  var focusNode = FocusNode();

  void update() {
    setState(() {});
  }

  void search([String? text]) {
    context
        .to(() => AggregatedSearchPage(keyword: text ?? controller.text))
        .then((_) => update());
  }

  var suggestions = <Pair<String, TranslationType>>[];

  bool canHandleUrl(String text) {
    if (!text.isURL) return false;
    for (var source in ComicSource.all()) {
      if (source.linkHandler != null) {
        var uri = Uri.parse(text);
        if (source.linkHandler!.domains.contains(uri.host)) {
          return true;
        }
      }
    }
    return false;
  }

  void findSuggestions() {
    var text = controller.text.split(" ").last;
    var suggestions = this.suggestions;

    suggestions.clear();

    if (canHandleUrl(controller.text)) {
      suggestions.add(Pair("**URL**", TranslationType.other));
    } else {
      var text = controller.text;

      for (var comicSource in ComicSource.all()) {
        if (comicSource.idMatcher?.hasMatch(text) ?? false) {
          suggestions.add(
            Pair("**${comicSource.key}**", TranslationType.other),
          );
        }
      }
    }

    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    void find(Map<String, String> map, TranslationType type) {
      for (var element in map.entries) {
        if (suggestions.length > 100) {
          break;
        }
        if (check(text, element.key, element.value)) {
          suggestions.add(Pair(element.key, type));
        }
      }
    }

    find(TagsTranslation.femaleTags, TranslationType.female);
    find(TagsTranslation.maleTags, TranslationType.male);
    find(TagsTranslation.parodyTags, TranslationType.parody);
    find(TagsTranslation.characterTranslations, TranslationType.character);
    find(TagsTranslation.otherTags, TranslationType.other);
    find(TagsTranslation.mixedTags, TranslationType.mixed);
    find(TagsTranslation.languageTranslations, TranslationType.language);
    find(TagsTranslation.artistTags, TranslationType.artist);
    find(TagsTranslation.groupTags, TranslationType.group);
    find(TagsTranslation.cosplayerTags, TranslationType.cosplayer);
    update();
  }

  @override
  void initState() {
    controller = SearchBarController(onSearch: search);
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  Widget buildEmpty() {
    return NetworkError(
      message: "${"No Comic Sources".tl}\n${"Please add some sources".tl}",
      retry: () {
        context.to(() => ComicSourcePage());
      },
      withAppbar: true,
      buttonText: "Manage".tl,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to search with: every source either has no search page or none
    // is installed.
    if (ComicSource.all().every((e) => e.searchPageData == null)) {
      return buildEmpty();
    }
    return Scaffold(
      body: SmoothCustomScrollView(slivers: buildSlivers().toList()),
    );
  }

  Iterable<Widget> buildSlivers() sync* {
    yield SliverSearchBar(
      controller: controller,
      onChanged: (s) {
        findSuggestions();
      },
      focusNode: focusNode,
    );
    if (suggestions.isNotEmpty) {
      yield buildSuggestions(context);
    } else {
      yield const SearchShortcutsSliver();
      yield _SearchHistory(search);
    }
  }

  Widget buildSuggestions(BuildContext context) {
    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    void onSelected(String text, TranslationType? type) {
      var words = controller.text.split(" ");
      if (words.length >= 2 &&
          check(
            "${words[words.length - 2]} ${words[words.length - 1]}",
            text,
            text.translateTagsToCN,
          )) {
        controller.text = controller.text.replaceLast(
          "${words[words.length - 2]} ${words[words.length - 1]}",
          "",
        );
      } else {
        controller.text = controller.text.replaceLast(
          words[words.length - 1],
          "",
        );
      }
      // No single target source decides how a tag is written; the first source
      // that offers that hook is used, otherwise the canonical form.
      String? insert;
      for (final candidate in ComicSource.all()) {
        final hook = candidate.onTagSuggestionSelected;
        if (hook != null) {
          insert = hook(type?.name ?? '', text);
          break;
        }
      }
      insert ??= () {
        var t = text;
        if (t.contains(' ')) t = "'$t'";
        return type != null ? "${type.name}:$t" : t;
      }();
      controller.text += "$insert ";
      suggestions.clear();
      update();
      focusNode.requestFocus();
    }

    bool showMethod = MediaQuery.of(context).size.width < 600;
    bool showTranslation = appLocale.languageCode == "zh";
    Widget buildItem(Pair<String, TranslationType> value) {
      if (value.left == "**URL**") {
        return ListTile(
          leading: const Icon(Icons.link),
          title: Text("Open link".tl),
          subtitle: Text(
            controller.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
          trailing: const Icon(Icons.arrow_right),
          onTap: () {
            setState(() {
              suggestions.clear();
            });
            handleAppLink(Uri.parse(controller.text));
          },
        );
      }

      if (RegExp(r"^\*\*.*\*\*$").hasMatch(value.left)) {
        var key = value.left.substring(2, value.left.length - 2);
        var comicSource = ComicSource.find(key);
        if (comicSource == null) {
          return const SizedBox();
        }
        return ListTile(
          leading: const Icon(Icons.link),
          title: Text("${"Open comic".tl}: ${comicSource.name}"),
          subtitle: Text(
            controller.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
          trailing: const Icon(Icons.arrow_right),
          onTap: () {
            context.to(() => ComicPage(sourceKey: key, id: controller.text));
          },
        );
      }

      var subTitle = TagsTranslation.translationTagWithNamespace(
        value.left,
        value.right.name,
      );
      return ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: Text(value.left)),
            if (!showMethod) const SizedBox(width: 12),
            if (!showMethod && showTranslation)
              Text(
                subTitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ),
        subtitle: (showMethod && showTranslation) ? Text(subTitle) : null,
        trailing: Text(value.right.name, style: const TextStyle(fontSize: 13)),
        onTap: () => onSelected(value.left, value.right),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text("Suggestions".tl),
            trailing: Tooltip(
              message: "Clear".tl,
              child: IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: () {
                  suggestions.clear();
                  update();
                },
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return buildItem(suggestions[index]);
          }, childCount: suggestions.length),
        ),
      ],
    );
  }
}

class SearchOptionWidget extends StatelessWidget {
  const SearchOptionWidget({
    super.key,
    required this.option,
    required this.value,
    required this.onChanged,
    required this.sourceKey,
  });

  final SearchOptions option;

  final String value;

  final void Function(String) onChanged;

  final String sourceKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(option.label.ts(sourceKey)),
        ),
        if (option.type == 'select')
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: option.options.entries.map((e) {
              return OptionChip(
                text: e.value.ts(sourceKey),
                isSelected: value == e.key,
                onTap: () {
                  onChanged(e.key);
                },
              );
            }).toList(),
          ),
        if (option.type == 'multi-select')
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: option.options.entries.map((e) {
              return OptionChip(
                text: e.value.ts(sourceKey),
                isSelected: (jsonDecode(value) as List).contains(e.key),
                onTap: () {
                  var list = jsonDecode(value) as List;
                  if (list.contains(e.key)) {
                    list.remove(e.key);
                  } else {
                    list.add(e.key);
                  }
                  onChanged(jsonEncode(list));
                },
              );
            }).toList(),
          ),
        if (option.type == 'dropdown')
          Select(
            current: option.options[value],
            values: option.options.values.toList(),
            onTap: (index) {
              onChanged(option.options.keys.elementAt(index));
            },
            minWidth: 96,
          ),
      ],
    );
  }
}

class _SearchHistory extends StatefulWidget {
  const _SearchHistory(this.search);

  final void Function(String) search;

  @override
  State<_SearchHistory> createState() => _SearchHistoryState();
}

class _SearchHistoryState extends State<_SearchHistory> {
  bool _saving = false;

  Future<bool> _editHistory(Future<void> Function() edit) async {
    if (_saving || !mounted) return false;
    setState(() => _saving = true);
    try {
      await edit();
      return true;
    } catch (error, stack) {
      Log.error('Search history', error, stack);
      if (mounted) context.showMessage(message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return const SizedBox(height: 16);
        }
        if (index == 1) {
          return ListTile(
            leading: const Icon(Icons.history),
            contentPadding: EdgeInsets.zero,
            title: Text("Search History".tl),
            trailing: Flyout(
              flyoutBuilder: (context) {
                var saving = false;
                return StatefulBuilder(
                  builder: (context, update) => FlyoutContent(
                    title: "Clear Search History".tl,
                    actions: [
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final route = ModalRoute.of(context);
                                update(() => saving = true);
                                final saved = await _editHistory(
                                  appdata.clearSearchHistory,
                                );
                                if (saved &&
                                    context.mounted &&
                                    route?.isCurrent != false) {
                                  context.pop();
                                }
                                if (context.mounted) {
                                  update(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text("Clear".tl),
                      ),
                    ],
                  ),
                );
              },
              child: Builder(
                builder: (context) {
                  return Tooltip(
                    message: "Clear".tl,
                    child: IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: () {
                        context.findAncestorStateOfType<FlyoutState>()!.show();
                      },
                    ),
                  );
                },
              ),
            ),
          );
        }
        return buildItem(index - 2);
      }, childCount: 2 + appdata.searchHistory.length),
    ).sliverPaddingHorizontal(16);
  }

  Widget buildItem(int index) {
    final keyword = appdata.searchHistory[index];
    void showMenu(
      BuildContext context,
      MenuRouteController menus,
      Offset offset,
    ) {
      menus.show(context, offset, [
        MenuEntry(
          icon: Icons.copy,
          text: 'Copy'.tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: keyword));
          },
        ),
        MenuEntry(
          icon: Icons.delete,
          text: 'Delete'.tl,
          onClick: () async {
            await _editHistory(() => appdata.removeSearchHistory(keyword));
          },
        ),
      ]);
    }

    return ContextMenuRegion(
      identity: keyword,
      builder: (context, menus) {
        return ClickInkWell(
          onTap: () {
            widget.search(keyword);
          },
          onLongPress: () {
            var renderBox = context.findRenderObject() as RenderBox;
            var offset = renderBox.localToGlobal(Offset.zero);
            showMenu(
              context,
              menus,
              Offset(
                offset.dx + renderBox.size.width / 2 - 121,
                offset.dy + renderBox.size.height - 8,
              ),
            );
          },
          onSecondaryTapUp: (details) {
            showMenu(context, menus, details.globalPosition);
          },
          child: Container(
            decoration: BoxDecoration(
              // color: context.colorScheme.surfaceContainer,
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(keyword, style: ts.s14),
          ),
        ).paddingBottom(8).paddingHorizontal(4);
      },
    );
  }
}
