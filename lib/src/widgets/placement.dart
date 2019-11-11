import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../rendering/layout_grid.dart';
import 'layout_grid.dart';

/// Packing strategies used by the auto-placement algorithm.
enum AutoPlacementPacking {
  /// The placement algorithm only ever moves “forward” in the grid when placing
  /// items, never backtracking to fill holes. This ensures that all of the
  /// auto-placed items appear “in order”, even if this leaves holes that could
  /// have been filled by later items.
  sparse,

  /// The auto-placement algorithm uses a “dense” packing algorithm, which
  /// attempts to fill in holes earlier in the grid if smaller items come up
  /// later. This may cause items to appear out-of-order, when doing so would
  /// fill in holes left by larger items.
  dense,
}

/// A widget that controls where a child of a [LayoutGrid] is placed. If a grid
/// item is not wrapped by a [GridPlacement], it will be placed in the first
/// available space, spanning one row and one column.
class GridPlacement extends ParentDataWidget<LayoutGrid> {
  const GridPlacement({
    Key key,
    @required Widget child,
    this.columnStart,
    int columnSpan = 1,
    this.rowStart,
    int rowSpan = 1,
  })  : this.columnSpan = columnSpan ?? 1,
        this.rowSpan = rowSpan ?? 1,
        super(key: key, child: child);

  /// If `null`, the child will be auto-placed.
  final int columnStart;

  /// The number of columns spanned by the child. Defaults to `1`.
  final int columnSpan;

  /// If `null`, the child will be auto-placed.
  final int rowStart;

  /// The number of rows spanned by the child. Defaults to `1`.
  final int rowSpan;

  @override
  void applyParentData(RenderObject renderObject) {
    assert(renderObject.parentData is GridParentData);
    final parentData = renderObject.parentData as GridParentData;
    bool needsLayout = false;

    if (parentData.columnStart != columnStart) {
      parentData.columnStart = columnStart;
      needsLayout = true;
    }

    if (parentData.columnSpan != columnSpan) {
      parentData.columnSpan = columnSpan;
      needsLayout = true;
    }

    if (parentData.rowStart != rowStart) {
      parentData.rowStart = rowStart;
      needsLayout = true;
    }

    if (parentData.rowSpan != rowSpan) {
      parentData.rowSpan = rowSpan;
      needsLayout = true;
    }

    if (needsLayout) {
      final AbstractNode targetParent = renderObject.parent;
      if (targetParent is RenderObject) targetParent.markNeedsLayout();
      if (targetParent is RenderLayoutGrid) targetParent.markNeedsPlacement();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (columnStart != null) {
      properties.add(IntProperty('columnStart', columnStart));
    } else {
      properties.add(StringProperty('columnStart', 'auto'));
    }
    if (columnSpan != null) {
      properties.add(IntProperty('columnSpan', columnSpan));
    }
    if (rowStart != null) {
      properties.add(IntProperty('rowStart', rowStart));
    } else {
      properties.add(StringProperty('rowStart', 'auto'));
    }
    if (rowSpan != null) {
      properties.add(IntProperty('rowSpan', rowSpan));
    }
  }
}
