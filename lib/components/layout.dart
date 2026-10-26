import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';

/// The three cover sizes, shared by the discovery panel and the shelf.
///
/// The spread is wide on purpose: a narrow one let adjacent steps round to the
/// same column count, so changing the size appeared to do nothing.
const coverSizeSmall = 0.7;
const coverSizeMedium = 1.0;
const coverSizeLarge = 1.4;

/// Target cover width at the medium step, in logical pixels.
const _coverCellWidth = 140.0;

/// The scale for a named step.
double coverSizeScale(String label) => switch (label) {
  'small' => coverSizeSmall,
  'large' => coverSizeLarge,
  _ => coverSizeMedium,
};

/// Maps a stored scale onto the named step it belongs to.
String coverSizeLabel(double scale) {
  if (scale < (coverSizeSmall + coverSizeMedium) / 2) return 'small';
  if (scale > (coverSizeMedium + coverSizeLarge) / 2) return 'large';
  return 'medium';
}

/// Cover size for the discovery lists, taken from the arrangement in use.
///
/// The list and the grid keep separate values, so a size chosen in one does not
/// silently change the other.
double discoveryCoverScale() {
  final store = GlobalPreferenceStore(appdata.settings);
  final grid = store.read(DiscoveryPreferences.comicDisplayMode) == 'brief';
  return store
      .read(
        grid
            ? DiscoveryPreferences.comicTileScale
            : DiscoveryPreferences.comicListTileScale,
      )
      .toDouble();
}

/// Number of covers that fit across [width] at [scale].
///
/// Rounding rather than ceiling keeps the steps distinct at common widths: the
/// old ceiling made 360dp phones show 3 / 2 / 2 columns, so "large" and "medium"
/// were the same picture.
int coverColumnsFor(double width, double scale) {
  if (width <= 0) return 1;
  // The count is derived at the medium step and then shifted by one for each
  // other step. Scaling the target width instead made small and medium round to
  // the same count on common phone widths, and made "small" a five-column wall
  // of thumbnails.
  final base = (width / _coverCellWidth).round().clamp(3, 6);
  return switch (coverSizeLabel(scale)) {
    'small' => base + 1,
    'large' => math.max(2, base - 1),
    _ => base,
  };
}

class SliverGridViewWithFixedItemHeight extends StatelessWidget {
  const SliverGridViewWithFixedItemHeight({
    required this.delegate,
    required this.maxCrossAxisExtent,
    required this.itemHeight,
    super.key,
  });

  final SliverChildDelegate delegate;

  final double maxCrossAxisExtent;

  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverGrid(
        delegate: delegate,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxCrossAxisExtent,
          childAspectRatio: calcChildAspectRatio(constraints.crossAxisExtent),
        ),
      ),
    );
  }

  double calcChildAspectRatio(double width) {
    var crossItems = width ~/ maxCrossAxisExtent;
    if (width % maxCrossAxisExtent != 0) {
      crossItems += 1;
    }
    final itemWidth = width / crossItems;
    return itemWidth / itemHeight;
  }
}

class SliverGridDelegateWithFixedHeight extends SliverGridDelegate {
  const SliverGridDelegateWithFixedHeight({
    required this.maxCrossAxisExtent,
    required this.itemHeight,
  });

  final double maxCrossAxisExtent;

  final double itemHeight;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    var crossItems = width ~/ maxCrossAxisExtent;
    if (width % maxCrossAxisExtent != 0) {
      crossItems += 1;
    }
    return SliverGridRegularTileLayout(
      crossAxisCount: crossItems,
      mainAxisStride: itemHeight,
      crossAxisStride: width / crossItems,
      childMainAxisExtent: itemHeight,
      childCrossAxisExtent: width / crossItems,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(covariant SliverGridDelegate oldDelegate) {
    if (oldDelegate is! SliverGridDelegateWithFixedHeight) return true;
    if (oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.itemHeight != itemHeight) {
      return true;
    }
    return false;
  }
}

class SliverGridDelegateWithComics extends SliverGridDelegate {
  SliverGridDelegateWithComics({
    this.galleryColumns,
    this.forceDetailed = false,
    this.forceCompact = false,
    double? scaleOverride,
  }) : scale = scaleOverride ?? discoveryCoverScale();

  final int? galleryColumns;

  final bool forceDetailed;

  /// One short row per comic: cover, title, source. Set by lists that show a
  /// plain list rather than the tall detailed card.
  final bool forceCompact;

  /// Cover size this delegate was built with.
  ///
  /// A caller with its own size setting passes it through `scaleOverride`; the
  /// rest read the discovery value. It is captured here rather than read on
  /// demand because shouldRelayout compares it against the old delegate, and a
  /// getter would read the same live setting on both sides — so a size change
  /// could never look different and the grid would never relayout.
  final double scale;

  final bool useBriefMode =
      GlobalPreferenceStore(
        appdata.settings,
      ).read(DiscoveryPreferences.comicDisplayMode) ==
      'brief';

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    if (forceCompact) {
      return getCompactModeLayout(constraints, scale);
    } else if (galleryColumns != null) {
      return getGalleryModeLayout(constraints, galleryColumns!, scale);
    } else if (useBriefMode && !forceDetailed) {
      return getBriefModeLayout(constraints, scale);
    } else {
      return getDetailedModeLayout(constraints, scale);
    }
  }

  /// A single full-width column of short rows.
  SliverGridLayout getCompactModeLayout(
    SliverConstraints constraints,
    double scale,
  ) {
    // The library's list row (56) plus the 4dp inset the shelf puts around each
    // row, so the resulting cover matches the reference at 40dp. The bounds are
    // only a guard against unreadable rows; they are wide enough that all three
    // named steps land on distinct heights.
    final itemHeight = (64.0 * scale).clamp(48.0, 100.0);
    final width = constraints.crossAxisExtent;
    return SliverGridRegularTileLayout(
      crossAxisCount: 1,
      mainAxisStride: itemHeight,
      crossAxisStride: width,
      childMainAxisExtent: itemHeight,
      childCrossAxisExtent: width,
      reverseCrossAxis: false,
    );
  }

  SliverGridLayout getGalleryModeLayout(
    SliverConstraints constraints,
    int configuredColumns,
    double scale,
  ) {
    const childAspectRatio = 0.64;
    final width = constraints.crossAxisExtent;
    final explicit = configuredColumns > 0;
    // "Auto" derives the count from a target cell width, so the cover size
    // decides how many fit. Rounding (not ceiling) keeps the three steps from
    // collapsing onto the same count at common phone widths.
    final crossAxisCount = explicit
        ? configuredColumns
        : coverColumnsFor(width, scale);
    final cell = width / crossAxisCount;
    // An explicit count leaves the cell fixed, so the cover fills only part of it
    // and the size steps still show. Under "Auto" the cell already came from the
    // size, and filling it a second time would shrink small covers twice.
    final fill = explicit ? (scale / coverSizeLarge).clamp(0.45, 1.0) : 1.0;
    final childCrossAxisExtent = cell * fill;
    final childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent,
      crossAxisStride: cell,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  SliverGridLayout getDetailedModeLayout(
    SliverConstraints constraints,
    double scale,
  ) {
    const minCrossAxisExtent = 360;
    final itemHeight = 152 * scale;
    final width = constraints.crossAxisExtent;
    var crossItems = width ~/ minCrossAxisExtent;
    crossItems = math.max(1, crossItems);
    return SliverGridRegularTileLayout(
      crossAxisCount: crossItems,
      mainAxisStride: itemHeight,
      crossAxisStride: width / crossItems,
      childMainAxisExtent: itemHeight,
      childCrossAxisExtent: width / crossItems,
      reverseCrossAxis: false,
    );
  }

  SliverGridLayout getBriefModeLayout(
    SliverConstraints constraints,
    double scale,
  ) {
    const childAspectRatio = 0.64;
    const crossAxisSpacing = 0.0;
    // Same rule as the gallery layout, so the size steps behave alike in every
    // grid the app shows instead of only in some of them.
    int crossAxisCount = coverColumnsFor(constraints.crossAxisExtent, scale);
    final double usableCrossAxisExtent = math.max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final double childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    final double childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant SliverGridDelegate oldDelegate) {
    if (oldDelegate is! SliverGridDelegateWithComics) return true;
    if (oldDelegate.galleryColumns != galleryColumns ||
        oldDelegate.forceDetailed != forceDetailed ||
        oldDelegate.scale != scale ||
        oldDelegate.useBriefMode != useBriefMode) {
      return true;
    }
    return false;
  }
}

class SliverLazyToBoxAdapter extends StatelessWidget {
  /// Creates a sliver that contains a single box widget which can be lazy loaded.
  const SliverLazyToBoxAdapter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverList.list(children: [SizedBox(), child]);
  }
}

class SliverAnimatedVisibility extends StatelessWidget {
  const SliverAnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var child = visible ? this.child : const SizedBox.shrink();

    return SliverToBoxAdapter(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}
