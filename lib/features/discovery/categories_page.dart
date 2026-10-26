import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_locale.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/routing/page_jump_target.dart';
import 'package:venera_next/foundation/extensions.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'ranking_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.sourceKey});

  /// When set, only this source's categories are offered as tabs.
  final String? sourceKey;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<CategoriesPage> {
  var categories = <String>[];

  late TabController controller;

  /// Category keys this instance may show, restricted to [widget.sourceKey].
  List<String> get _availableCategories => [
    for (final e in ComicSource.all())
      if (widget.sourceKey == null || e.key == widget.sourceKey)
        if (e.categoryData != null) e.categoryData!.key,
  ];

  void onSettingsChanged() {
    final next = _availableCategories;
    if (!next.isEqualTo(categories)) {
      setState(() {
        categories = next;
      });
      // Dispose before replacing, or each source switch leaks a ticker.
      controller.dispose();
      controller = TabController(length: categories.length, vsync: this);
    }
  }

  @override
  void initState() {
    super.initState();
    categories = _availableCategories;
    appdata.settings.addListener(onSettingsChanged);
    controller = TabController(length: categories.length, vsync: this);
  }

  @override
  void didUpdateWidget(CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey) {
      onSettingsChanged();
    }
  }

  @override
  void dispose() {
    super.dispose();
    controller.dispose();
    appdata.settings.removeListener(onSettingsChanged);
  }

  Widget buildEmpty() {
    // The sources are listed by the discovery source selector, so an empty
    // state here means there are no sources installed.
    return NetworkError(
      message: "${"No Category Pages".tl}\n${"Please add some sources".tl}",
      retry: () => context.to(() => ComicSourcePage()),
      withAppbar: false,
      buttonText: "Manage".tl,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (categories.isEmpty) {
      return buildEmpty();
    }

    // A single category needs no tab strip; the source selector above already
    // identifies it.
    final showTabs = categories.length > 1;

    return Material(
      child: Column(
        children: [
          if (showTabs)
            AppTabBar(
              controller: controller,
              key: PageStorageKey(categories.toString()),
              tabs: categories.map((e) {
                String title = e;
                try {
                  title = getCategoryDataWithKey(e).title;
                } catch (e) {
                  //
                }
                return Tab(text: title, key: Key(e));
              }).toList(),
            ).paddingTop(context.padding.top),
          Expanded(
            child: TabBarView(
              controller: controller,
              children: categories.map((e) => _CategoryPage(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _CategoryPage extends StatelessWidget {
  const _CategoryPage(this.category);

  final String category;

  CategoryData get data => getCategoryDataWithKey(category);

  @override
  Widget build(BuildContext context) {
    var children = <Widget>[];
    if (data.enableRankingPage || data.buttons.isNotEmpty) {
      children.add(buildTitle(data.title));
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
          child: Wrap(
            children: [
              if (data.enableRankingPage)
                buildTag("Ranking".tl, () {
                  context.to(() => RankingPage(categoryKey: data.key));
                }),
              for (var buttonData in data.buttons)
                buildTag(buttonData.label.tl, buttonData.onTap),
            ],
          ),
        ),
      );
    }

    for (var part in data.categories) {
      if (part.enableRandom) {
        children.add(
          StatefulBuilder(
            builder: (context, updater) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTitleWithRefresh(part.title, () => updater(() {})),
                  buildTags(part.categories),
                ],
              );
            },
          ),
        );
      } else {
        children.add(buildTitle(part.title));
        children.add(buildTags(part.categories));
      }
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
      child: Text(
        title.tl,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget buildTitleWithRefresh(String title, void Function() onRefresh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
      child: Row(
        children: [
          Text(
            title.tl,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }

  Widget buildTags(List<CategoryItem> categories) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      child: Wrap(
        children: List<Widget>.generate(
          categories.length,
          (index) => buildCategory(categories[index]),
        ),
      ),
    );
  }

  Widget buildCategory(CategoryItem c) {
    return buildTag(c.label, () {
      var context = appNavigation.mainNavigatorKey!.currentContext!;
      c.target.jump(context);
    });
  }

  Widget buildTag(String label, VoidCallback onClick) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Builder(
        builder: (context) {
          return Material(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            color: context.colorScheme.primaryContainer.toOpacity(0.72),
            child: ClickInkWell(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              onTap: onClick,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(label),
              ),
            ),
          );
        },
      ),
    );
  }

  bool get enableTranslation => appLocale.languageCode == 'zh';
}
