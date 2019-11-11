import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';
import 'package:quiver/iterables.dart';

import '../../flutter_layout_grid.dart';
import 'placement.dart';
import 'util.dart';

/// Parent data for use with [RenderLayoutGrid].
class GridParentData extends ContainerBoxParentData<RenderBox> {
  GridParentData({
    this.columnStart,
    this.columnSpan = 1,
    this.rowStart,
    this.rowSpan = 1,
    this.debugLabel,
  });

  /// If `null`, the item is auto-placed.
  int columnStart;
  int columnSpan = 1;

  /// If `null`, the item is auto-placed.
  int rowStart;
  int rowSpan = 1;

  String debugLabel;

  int startForAxis(Axis axis) =>
      axis == Axis.horizontal ? columnStart : rowStart;

  int spanForAxis(Axis axis) => //
      axis == Axis.horizontal ? columnSpan : rowSpan;

  GridArea get area {
    assert(isDefinitelyPlaced);
    return GridArea(
      columnStart: columnStart,
      columnEnd: columnStart + columnSpan,
      rowStart: rowStart,
      rowEnd: rowStart + rowSpan,
    );
  }

  /// Returns `true` if the item has definite placement in the grid.
  bool get isDefinitelyPlaced => columnStart != null && rowStart != null;

  /// Returns `true` if the item is definitely placed on the provided axis.
  bool isDefinitelyPlacedOnAxis(Axis axis) =>
      axis == Axis.horizontal ? columnStart != null : rowStart != null;

  @override
  String toString() {
    final List<String> values = <String>[
      if (columnStart != null) 'columnStart=$columnStart',
      if (columnSpan != null) 'columnSpan=$columnSpan',
      if (rowStart != null) 'rowStart=$rowStart',
      if (rowSpan != null) 'rowSpan=$rowSpan',
      if (debugLabel != null) 'debugLabel=$debugLabel',
    ];
    values.add(super.toString());
    return values.join('; ');
  }
}

const closeToZeroEpsilon = 1 / 1024;

/// Implements the grid layout algorithm.
///
/// TODO(shyndman): Describe algorithm.
class RenderLayoutGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridParentData> {
  /// Creates a layout grid render object.
  RenderLayoutGrid({
    AutoPlacement autoPlacementMode = AutoPlacement.rowSparse,
    GridFit gridFit = GridFit.expand,
    List<RenderBox> children,
    List<TrackSize> templateColumnSizes,
    List<TrackSize> templateRowSizes,
    @required TextDirection textDirection,
  })  : assert(autoPlacementMode != null),
        assert(gridFit != null),
        assert(textDirection != null),
        _autoPlacementMode = autoPlacementMode,
        _templateColumnSizes = templateColumnSizes,
        _templateRowSizes = templateRowSizes,
        _textDirection = textDirection {
    addAll(children);
  }

  bool _needsPlacement = true;
  PlacementGrid _placementGrid;
  GridSizingInfo gridSizing;

  /// Controls how the auto-placement algorithm works, specifying exactly how
  /// auto-placed items get flowed into the grid.
  AutoPlacement get autoPlacement => _autoPlacementMode;
  AutoPlacement _autoPlacementMode;
  set autoPlacement(AutoPlacement value) {
    assert(value != null);
    if (_autoPlacementMode == value) return;
    _autoPlacementMode = value;
    markNeedsLayout();
  }

  /// Determines the constraints available to the grid layout algorithm.
  GridFit get gridFit => _gridFit;
  GridFit _gridFit;
  set gridFit(GridFit value) {
    assert(value != null);
    if (_gridFit == value) return;
    _gridFit = value;
    markNeedsLayout();
  }

  /// Defines the sizing functions of the grid's columns.
  List<TrackSize> get templateColumnSizes => _templateColumnSizes;
  List<TrackSize> _templateColumnSizes;
  set templateColumnSizes(List<TrackSize> value) {
    if (_templateColumnSizes == value) return;
    _templateColumnSizes = value;
    markNeedsLayout();
  }

  /// Defines the sizing functions of the grid's rows.
  List<TrackSize> get templateRowSizes => _templateRowSizes;
  List<TrackSize> _templateRowSizes;
  set templateRowSizes(List<TrackSize> value) {
    if (_templateRowSizes == value) return;
    _templateRowSizes = value;
    markNeedsLayout();
  }

  /// The text direction with which to resolve column ordering.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _getIntrinsicDimensionForTrackType(
        TrackType.column, _IntrinsicDimension.min);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _getIntrinsicDimensionForTrackType(
        TrackType.column, _IntrinsicDimension.max);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _getIntrinsicDimensionForTrackType(
        TrackType.row, _IntrinsicDimension.min);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _getIntrinsicDimensionForTrackType(
        TrackType.row, _IntrinsicDimension.max);
  }

  double _getIntrinsicDimensionForTrackType(
      TrackType type, _IntrinsicDimension dimension) {}

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  List<RenderBox> getChildrenInTrack(TrackType trackType, int trackIndex) {
    return _placementGrid
        .getCellsInTrack(trackIndex, trackType)
        .expand((cell) => cell.occupants)
        .where(removeDuplicates())
        .toList(growable: false);
  }

  @override
  void performLayout() {
    // Distribute grid items into cells
    performItemPlacement();

    // Ready a sizing grid
    final gridSizing = GridSizingInfo.fromTrackSizeFunctions(
      columnSizeFunctions: _templateColumnSizes,
      rowSizeFunctions: _templateRowSizes,
    );

    // Determine the size of the column tracks
    final columnTracks = performTrackSizing(TrackType.column, gridSizing,
        constraints: constraints);
    gridSizing.hasColumnSizing = true;

    // Determine the size of the row tracks
    final rowTracks =
        performTrackSizing(TrackType.row, gridSizing, constraints: constraints);
    gridSizing.hasRowSizing = true;

    // Now our track sizes are definite, and we can go ahead
    // maximizeTrackSizing(
    //     columnTracks, minConstraintForAxis(constraints, Axis.horizontal));

    // Position and lay out the grid items
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData as GridParentData;
      final area = _placementGrid.itemAreas[child];

      final width = columnTracks
          .getRange(area.columnStart, area.columnEnd)
          .fold<double>(0, (acc, track) => acc + track.baseSize);
      final height = rowTracks
          .getRange(area.rowStart, area.rowEnd)
          .fold<double>(0, (acc, track) => acc + track.baseSize);

      parentData.offset = gridSizing.offsetForArea(area);
      child.layout(BoxConstraints.tightFor(width: width, height: height));

      child = parentData.nextSibling;
    }

    final gridWidth =
        columnTracks.fold<double>(0, (acc, track) => track.baseSize);
    final gridHeight =
        rowTracks.fold<double>(0, (acc, track) => track.baseSize);

    this.gridSizing = gridSizing;
    size = constraints.constrain(Size(gridWidth, gridHeight));
  }

  /// Determines where each grid item is positioned in the grid, using the
  /// auto-placement algorithm if necessary.
  void performItemPlacement() {
    if (!_needsPlacement) return;
    _needsPlacement = false;
    _placementGrid = computeItemPlacement(this);
  }

  /// A rough approximation of
  /// https://drafts.csswg.org/css-grid/#algo-track-sizing. There are a bunch of
  /// steps left out because our model is simpler.
  List<GridTrack> performTrackSizing(
    TrackType typeBeingSized,
    GridSizingInfo gridSizing, {
    @visibleForTesting BoxConstraints constraints,
  }) {
    constraints ??= this.constraints;

    final sizingAxis = measurementAxisForTrackType(typeBeingSized);
    final intrinsicTracks = <GridTrack>[];
    final flexibleTracks = <GridTrack>[];
    final tracks = gridSizing.tracksForType(typeBeingSized);
    final initialFreeSpace = maxConstraintForAxis(constraints, sizingAxis);
    final isAxisDefinite = isTightlyConstrainedForAxis(constraints, sizingAxis);

    // 1. Initialize track sizes

    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];

      if (track.sizeFunction
          .isFixedForConstraints(typeBeingSized, constraints)) {
        // Fixed, definite
        final fixedSize = track.sizeFunction
            .minIntrinsicSize(typeBeingSized, [], initialFreeSpace);
        track.baseSize = track.growthLimit = fixedSize;
      } else if (track.sizeFunction.isFlexible) {
        // Flexible sizing
        track.baseSize = track.growthLimit = 0;

        flexibleTracks.add(track);
      } else {
        // Intrinsic sizing
        track.baseSize = 0;
        track.growthLimit = double.infinity;

        intrinsicTracks.add(track);
      }

      track.growthLimit = math.max(track.growthLimit, track.baseSize);
    }

    // 2. Resolve intrinsic track sizes

    _resolveIntrinsicTrackSizes(typeBeingSized, sizingAxis, tracks,
        intrinsicTracks, gridSizing, constraints, initialFreeSpace);

    // 3. Grow all tracks from their baseSize up to their growthLimit value
    //    until freeSpace is exhausted.

    var baseSizesWithoutMaximization = 0.0,
        growthLimitsWithoutMaximization = 0.0;
    for (final track in tracks) {
      assert(!track.isInfinite);
      baseSizesWithoutMaximization += track.baseSize;
      growthLimitsWithoutMaximization += track.growthLimit;
    }

    double freeSpace = initialFreeSpace - baseSizesWithoutMaximization;

    // We're already overflowing
    if (isAxisDefinite && freeSpace < 0) {
      return tracks;
    }

    if (isAxisDefinite) {
      _distributeFreeSpace(freeSpace, tracks, [], _IntrinsicDimension.min);
    } else {
      for (final track in tracks) {
        track.baseSize = track.growthLimit;
      }
    }

    // 4. Size flexible tracks to fill remaining space, if any

    if (flexibleTracks.isEmpty) {
      return tracks;
    }

    // TODO(shyndman): This is not to spec. Flexible rows should have a minimum
    // size of their content's minimum contribution. We will add this as soon
    // as we have the notion of distinct minimum and maximum track size
    // functions.
    // https://drafts.csswg.org/css-grid/#valdef-grid-template-columns-flex
    final flexFraction =
        findFlexFactorUnitSize(tracks, flexibleTracks, initialFreeSpace);

    for (final track in flexibleTracks) {
      track.baseSize = flexFraction * track.sizeFunction.flex;

      freeSpace -= track.baseSize;
      baseSizesWithoutMaximization += track.baseSize;
      growthLimitsWithoutMaximization += track.baseSize;
    }

    gridSizing.setMinMaxForAxis(baseSizesWithoutMaximization,
        growthLimitsWithoutMaximization, sizingAxis);

    return tracks;
  }

  void _resolveIntrinsicTrackSizes(
    TrackType type,
    Axis sizingAxis,
    List<GridTrack> tracks,
    List<GridTrack> intrinsicTracks,
    GridSizingInfo gridSizing,
    BoxConstraints constraints,
    double freeSpace,
  ) {
    final itemsInIntrinsicTracks = intrinsicTracks
        .expand((t) => getChildrenInTrack(type, t.index))
        .where(removeDuplicates());

    final itemsBySpan = groupBy(itemsInIntrinsicTracks, getSpan(sizingAxis));
    final sortedSpans = itemsBySpan.keys.toList()..sort();

    // Iterate over the spans we find in our items list, in ascending order.
    for (int span in sortedSpans) {
      final spanItems = itemsBySpan[span];
      // TODO(shyndman): This is unnecessary work. We should be able to
      // construct what we need above.
      final spanItemsByTrack = groupBy<RenderBox, int>(
        spanItems,
        (item) => _placementGrid.itemAreas[item].startForAxis(sizingAxis),
      );

      // Size all spans containing at least one intrinsic track and zero
      // flexible tracks.
      for (final i in spanItemsByTrack.keys) {
        final spannedTracks = tracks.getRange(i, i + span);
        final spanItemsInTrack = spanItemsByTrack[i];
        final intrinsicTrack = spannedTracks
            .firstWhere(isIntrinsic(type, constraints), orElse: () => null);

        // We don't size flexible tracks until later
        if (intrinsicTrack == null ||
            spannedTracks.any(isFlexible(type, constraints))) {
          continue;
        }

        final crossAxis = flipAxis(sizingAxis);
        final crossAxisSizeForItem = gridSizing.isAxisSized(crossAxis)
            ? (RenderBox item) {
                return gridSizing.sizeForAreaOnAxis(
                    _placementGrid.itemAreas[item], crossAxis);
              }
            : (RenderBox _) => double.infinity;

        // Calculate the min-size of the spanned items, and distribute the
        // additional space to the spanned tracks' base sizes.
        final minSpanSize = intrinsicTrack.sizeFunction.minIntrinsicSize(
            type, spanItemsInTrack, freeSpace,
            crossAxisSizeForItem: crossAxisSizeForItem);
        _distributeCalculatedSpaceToSpannedTracks(
            minSpanSize, type, spannedTracks, _IntrinsicDimension.min);

        // Calculate the max-size of the spanned items, and distribute the
        // additional space to the spanned tracks' growth limits.
        final maxSpanSize = intrinsicTrack.sizeFunction.maxIntrinsicSize(
            type, spanItemsInTrack, freeSpace,
            crossAxisSizeForItem: crossAxisSizeForItem);
        _distributeCalculatedSpaceToSpannedTracks(
            maxSpanSize, type, spannedTracks, _IntrinsicDimension.max);
      }
    }

    // The time for infinite growth limits is over!
    for (final track in intrinsicTracks) {
      if (track.isInfinite) track.growthLimit = track.baseSize;
    }
  }

  /// Distributes free space among [spannedTracks]
  void _distributeCalculatedSpaceToSpannedTracks(
    double calculatedSpace,
    TrackType type,
    Iterable<GridTrack> spannedTracks,
    _IntrinsicDimension dimension,
  ) {
    // Subtract calculated dimensions of the tracks
    double freeSpace = calculatedSpace;
    for (final track in spannedTracks) {
      freeSpace -= dimension == _IntrinsicDimension.min
          ? track.baseSize
          : track.isInfinite ? track.baseSize : track.growthLimit;
    }

    // If there's no free space to distribute, freeze the tracks and we're done
    if (freeSpace <= 0) {
      for (final track in spannedTracks) {
        if (track.isInfinite) {
          track.growthLimit = track.baseSize;
        }
      }
      return;
    }

    // Filter to the intrinsicly sized tracks in the span
    final intrinsicTracks = spannedTracks
        .where((track) =>
            track.sizeFunction.isIntrinsicForConstraints(type, constraints))
        .toList(growable: false);

    // Now distribute the free space between them
    if (intrinsicTracks.isNotEmpty) {
      _distributeFreeSpace(
          freeSpace, intrinsicTracks, intrinsicTracks, dimension);
    }
  }

  void _distributeFreeSpace(
    double freeSpace,
    List<GridTrack> tracks,
    List<GridTrack> growableAboveMaxTracks,
    _IntrinsicDimension dimension,
  ) {
    assert(freeSpace >= 0);

    final distribute = (List<GridTrack> tracks,
        double Function(GridTrack, double) getShareForTrack) {
      final trackCount = tracks.length;
      for (int i = 0; i < trackCount; i++) {
        final track = tracks[i];
        final availableShare = freeSpace / (tracks.length - i);
        final shareForTrack = getShareForTrack(track, availableShare);
        assert(shareForTrack >= 0.0, 'Never shrink a track');

        track.sizeDuringDistribution += shareForTrack;
        freeSpace -= shareForTrack;
      }
    };

    // Setup a size that will be used for distribution calculations, and
    // assigned back to the sizes when we complete.
    for (final track in tracks) {
      track.sizeDuringDistribution = dimension == _IntrinsicDimension.min
          ? track.baseSize
          : track.isInfinite ? track.baseSize : track.growthLimit;
    }

    tracks.sort(sortByGrowthPotential);

    // Distribute the free space between tracks
    distribute(tracks, (track, availableShare) {
      return track.isInfinite
          ? availableShare
          // Grow up until limit
          : math.min(
              availableShare,
              track.growthLimit - track.sizeDuringDistribution,
            );
    });

    // If we still have space leftover, let's unfreeze and grow some more
    // (ignoring limit)
    if (freeSpace > 0 && growableAboveMaxTracks != null) {
      distribute(
          growableAboveMaxTracks, (track, availableShare) => availableShare);
    }

    // Assign back the calculated sizes
    for (final track in tracks) {
      if (dimension == _IntrinsicDimension.min) {
        track.baseSize = math.max(track.baseSize, track.sizeDuringDistribution);
      } else {
        track.growthLimit = track.isInfinite
            ? track.sizeDuringDistribution
            : math.max(track.growthLimit, track.sizeDuringDistribution);
      }
    }
  }

  double findFlexFactorUnitSize(
    List<GridTrack> tracks,
    List<GridTrack> flexibleTracks,
    double leftOverSpace,
  ) {
    double flexSum = 0;
    for (final track in tracks) {
      if (!track.sizeFunction.isFlexible) {
        leftOverSpace -= track.baseSize;
      } else {
        flexSum += track.sizeFunction.flex;
      }
    }

    assert(flexSum > 0);
    // TODO(shyndman): This is not to spec. We need to consider track base sizes
    // (when measuring the content minimum) that are bigger than what the flex
    // would provide.
    return leftOverSpace / flexSum;
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    markNeedsPlacementIfRequired(child);
  }

  @override
  void dropChild(RenderObject child) {
    super.dropChild(child);
    markNeedsPlacementIfRequired(child);
  }

  /// Determines whether [child] may represent a change in grid item
  /// positioning, and if so, ensures that we will regenerate the placement grid
  /// on next layout.
  void markNeedsPlacementIfRequired(RenderObject child) {
    if (_needsPlacement) return;
    final parentData = child.parentData as GridParentData;
    if (parentData != null && !parentData.isDefinitelyPlaced) {
      markNeedsPlacement();
    }
  }

  void markNeedsPlacement() => _needsPlacement = true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}

double minConstraintForAxis(BoxConstraints constraints, Axis axis) {
  return axis == Axis.vertical ? constraints.minHeight : constraints.minWidth;
}

double maxConstraintForAxis(BoxConstraints constraints, Axis axis) {
  return axis == Axis.vertical ? constraints.maxHeight : constraints.maxWidth;
}

bool isTightlyConstrainedForAxis(BoxConstraints constraints, Axis axis) {
  return axis == Axis.vertical
      ? constraints.hasTightHeight
      : constraints.hasTightWidth;
}

enum _IntrinsicDimension { min, max }

class GridTrack {
  GridTrack(this.index, this.sizeFunction);

  final int index;
  final TrackSize sizeFunction;

  double _baseSize = 0;
  double _growthLimit = 0;

  double sizeDuringDistribution = 0;

  double get baseSize => _baseSize;
  set baseSize(double value) {
    _baseSize = value;
    _increaseGrowthLimitIfNecessary();
  }

  double get growthLimit => _growthLimit;
  set growthLimit(double value) {
    _growthLimit = value;
    _increaseGrowthLimitIfNecessary();
  }

  bool get isInfinite => _growthLimit == double.infinity;

  void _increaseGrowthLimitIfNecessary() {
    if (_growthLimit != double.infinity && _growthLimit < _baseSize) {
      _growthLimit = _baseSize;
    }
  }

  @override
  String toString() {
    return 'GridTrack(baseSize=$baseSize, growthLimit=$growthLimit, sizeFunction=$sizeFunction)';
  }
}

List<GridTrack> _sizesToTracks(Iterable<TrackSize> sizes) => enumerate(sizes)
    .map((s) => GridTrack(s.index, s.value))
    .toList(growable: false);

class GridSizingInfo {
  GridSizingInfo({
    @required this.columnTracks,
    @required this.rowTracks,
  })  : assert(columnTracks != null),
        assert(rowTracks != null);

  GridSizingInfo.fromTrackSizeFunctions({
    @required List<TrackSize> columnSizeFunctions,
    @required List<TrackSize> rowSizeFunctions,
  }) : this(
          columnTracks: _sizesToTracks(columnSizeFunctions),
          rowTracks: _sizesToTracks(rowSizeFunctions),
        );

  List<GridTrack> columnTracks;
  List<GridTrack> rowTracks;

  List<double> _columnStarts;
  List<double> get columnStarts {
    if (_columnStarts == null) {
      _columnStarts = cumulativeSum(
        columnTracks.map((t) => t.baseSize),
        includeLast: false,
      ).toList(growable: false);
    }
    return _columnStarts;
  }

  List<double> _rowStarts;
  List<double> get rowStarts {
    if (_rowStarts == null) {
      _rowStarts = cumulativeSum(
        rowTracks.map((t) => t.baseSize),
        includeLast: false,
      ).toList(growable: false);
    }
    return _rowStarts;
  }

  double minWidth = 0.0;
  double minHeight = 0.0;

  double maxWidth = 0.0;
  double maxHeight = 0.0;

  bool hasColumnSizing = false;
  bool hasRowSizing = false;

  Offset offsetForArea(GridArea area) {
    return Offset(columnStarts[area.columnStart], rowStarts[area.rowStart]);
  }

  void markTrackTypeSized(TrackType type) {
    if (type == TrackType.column) {
      hasColumnSizing = true;
    } else {
      hasRowSizing = true;
    }
  }

  void setMinMaxForAxis(double min, double max, Axis sizingAxis) {
    if (sizingAxis == Axis.horizontal) {
      minWidth = min;
      maxWidth = max;
    } else {
      minHeight = min;
      maxHeight = max;
    }
  }

  bool isAxisSized(Axis sizingAxis) =>
      sizingAxis == Axis.horizontal ? hasColumnSizing : hasRowSizing;

  List<GridTrack> tracksForType(TrackType type) =>
      type == TrackType.column ? columnTracks : rowTracks;

  List<GridTrack> tracksAlongAxis(Axis sizingAxis) =>
      sizingAxis == Axis.horizontal ? columnTracks : rowTracks;

  double sizeForAreaOnAxis(GridArea area, Axis axis) {
    assert(isAxisSized(axis));

    // TODO(shyndman): Support row/col gaps

    final trackBaseSizes = tracksAlongAxis(axis)
        .getRange(area.startForAxis(axis), area.endForAxis(axis))
        .map((t) => t.baseSize);
    return sum(trackBaseSizes);
  }
}