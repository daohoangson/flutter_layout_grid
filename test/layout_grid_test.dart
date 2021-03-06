import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';
import 'package:flutter_layout_grid/src/rendering/layout_grid.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/flutter_layout_grid.dart';

void main() {
  testWidgets('Computes fixed intrinsic sizes', (tester) async {
    final grid = LayoutGrid(
      templateColumnSizes: [FixedTrackSize(10)],
      templateRowSizes: [FixedTrackSize(10)],
      textDirection: TextDirection.ltr,
    );
    await tester.pumpWidget(grid);
    final renderObject =
        tester.firstRenderObject<RenderLayoutGrid>(find.byType(LayoutGrid));

    expect(renderObject.getMinIntrinsicWidth(double.infinity), 10);
    expect(renderObject.getMinIntrinsicHeight(double.infinity), 10);
    expect(renderObject.getMaxIntrinsicWidth(double.infinity), 10);
    expect(renderObject.getMaxIntrinsicHeight(double.infinity), 10);
  });

  testWidgets('Piet screenshot test', (tester) async {
    await tester.pumpWidget(PietApp());
    await expectLater(
      find.byType(PietApp),
      matchesGoldenFile('goldens/piet.png'),
    );
  });
}
