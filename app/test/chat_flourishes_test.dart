import 'package:family_app/features/chat/presentation/chat_flourishes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three flourishes, and the rules inside each that are not decoration.
void main() {
  group('the speaker disc', () {
    test('the same name always gets the same colour', () {
      // ⚠ THE WHOLE POINT. The colour is a hash, not an assignment, because
      //   there is nowhere to store an assignment — the room is a table of
      //   messages and the author is a snapshot string. A colour that changed
      //   between sessions would be worse than no colour at all, because a
      //   reader would have learned it.
      expect(
        ChatAvatar.toneFor('محمد العدولي'),
        ChatAvatar.toneFor('محمد العدولي'),
      );
    });

    test('...and different names generally get different ones', () {
      // Six tones and a handful of members, so collisions exist and are fine —
      // the name is printed beside the disc. What must NOT happen is every name
      // landing on one colour, which is what a broken hash looks like.
      final Set<Color> tones = <String>[
        'محمد العدولي',
        'أيمن صالح',
        'عبدالله محمد',
        'سالم بلها',
        'خالد المهدي',
      ].map(ChatAvatar.toneFor).toSet();

      expect(tones.length, greaterThan(1));
    });

    test('a name that is only spaces still yields a letter', () {
      // Arabic names arrive with the odd leading space. A blank disc reads as a
      // rendering fault, which is a bug report about the wrong thing.
      expect(ChatAvatar.initialFor('   '), isNotEmpty);
      expect(ChatAvatar.initialFor('  محمد  '), 'م');
    });

    testWidgets('it draws at the size it is given', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: ChatAvatar(name: 'محمد', size: 30))),
        ),
      );
      expect(tester.getSize(find.byType(ChatAvatar)), const Size(30, 30));
    });
  });

  group('a gesture, not a sentence', () {
    test('one emoji is a gesture', () {
      expect(isEmojiOnly('🙏'), isTrue);
      expect(isEmojiOnly('❤️'), isTrue);
      expect(isEmojiOnly('😀😀'), isTrue);
      expect(isEmojiOnly(' 🙏 '), isTrue);
    });

    test('...and words are not, even beside one', () {
      expect(isEmojiOnly('شكراً 🙏'), isFalse);
      expect(isEmojiOnly('شكراً'), isFalse);
      expect(isEmojiOnly(''), isFalse);
      expect(isEmojiOnly('   '), isFalse);
    });

    test('⚠ and FOUR is a message again, not a wall of 40pt glyphs', () {
      // Without the cap a member pastes forty hearts and takes a page of the
      // room with them. Above it, an ordinary bubble.
      expect(isEmojiOnly('❤️❤️❤️'), isTrue);
      expect(isEmojiOnly('❤️❤️❤️❤️'), isFalse);
    });
  });
}
