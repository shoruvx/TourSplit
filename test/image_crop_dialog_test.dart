import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/presentation/widgets/image_crop_dialog.dart';

void main() {
  testWidgets('ImageCropDialog renders correctly with controls and overlay',
      (tester) async {
    // 1x1 PNG bytes
    final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageCropDialog(imageBytes: pngBytes),
        ),
      ),
    );

    // Verify dialog title and key elements
    expect(find.text('Crop & Position'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Apply & Save'), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });
}
