import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/presentation/chat/widgets/chat_reaction_bar.dart';

void main() {
  group('ChatReactionBar Responsive & Overflow Tests', () {
    testWidgets('Renders without overflow on compact 320px width screen', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? selectedEmoji;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatReactionBar(
                currentReaction: '👍',
                onSelectEmoji: (emoji) => selectedEmoji = emoji,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check all emojis render
      for (final emoji in ChatReactionBar.defaultEmojis) {
        expect(find.text(emoji), findsOneWidget);
      }

      // Tap an emoji
      await tester.tap(find.text('❤️'));
      await tester.pumpAndSettle();

      expect(selectedEmoji, '❤️');
    });

    testWidgets('Renders without overflow on 360px Huawei width with large text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.4), // Emulate large EMUI accessibility font
            ),
            child: Scaffold(
              body: Center(
                child: ChatReactionBar(
                  currentReaction: null,
                  onSelectEmoji: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify no overflow exception was thrown and all emojis rendered
      for (final emoji in ChatReactionBar.defaultEmojis) {
        expect(find.text(emoji), findsOneWidget);
      }
    });

    testWidgets('ChatMessage modal bottom sheet layout fits on compact 360x600 device without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (ctx) => SafeArea(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                ChatReactionBar(
                                  currentReaction: null,
                                  onSelectEmoji: (_) {},
                                ),
                                const SizedBox(height: 6),
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                  leading: const Icon(Icons.copy_rounded),
                                  title: const Text('Copy Text'),
                                  onTap: () {},
                                ),
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                  leading: const Icon(Icons.reply_rounded),
                                  title: const Text('Reply'),
                                  subtitle: const Text(
                                    'Quote this message in your reply',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {},
                                ),
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                  leading: const Icon(Icons.delete_outline_rounded),
                                  title: const Text('Delete for me'),
                                  subtitle: const Text(
                                    'Removes this message from your device only',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {},
                                ),
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                  leading: const Icon(Icons.delete_forever_rounded),
                                  title: const Text('Delete for everyone'),
                                  subtitle: const Text(
                                    'Erases this message for all tour members like Telegram',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Actions'),
                );
              },
            ),
          ),
        ),
      );

      // Open bottom sheet
      await tester.tap(find.text('Open Actions'));
      await tester.pumpAndSettle();

      // Verify all items are present and no layout overflow occurred
      expect(find.text('Copy Text'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      for (final emoji in ChatReactionBar.defaultEmojis) {
        expect(find.text(emoji), findsOneWidget);
      }
    });
  });
}
