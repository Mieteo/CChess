import 'package:cchess/presentation/online/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'https://example.test';

  group('normalizeRoomId / isValidRoomId', () {
    test('trims and uppercases', () {
      expect(RoomShare.normalizeRoomId('  abc234  '), 'ABC234');
    });

    test('accepts a 6-char alphanumeric code', () {
      expect(RoomShare.isValidRoomId('ABC234'), isTrue);
      expect(RoomShare.isValidRoomId('abc234'), isTrue); // normalized first
    });

    test('rejects wrong length or illegal chars', () {
      expect(RoomShare.isValidRoomId('ABC23'), isFalse); // 5 chars
      expect(RoomShare.isValidRoomId('ABC2345'), isFalse); // 7 chars
      expect(RoomShare.isValidRoomId('ABC-23'), isFalse); // dash
      expect(RoomShare.isValidRoomId(''), isFalse);
    });
  });

  group('linkFor', () {
    test('builds spectate link by default', () {
      expect(
        RoomShare.linkFor('ABC234', base: base),
        'https://example.test/r/ABC234',
      );
    });

    test('builds join link with mode=join', () {
      expect(
        RoomShare.linkFor('ABC234', spectate: false, base: base),
        'https://example.test/r/ABC234?mode=join',
      );
    });

    test('normalizes the room id and strips trailing slash in base', () {
      expect(
        RoomShare.linkFor('abc234', base: '$base/'),
        'https://example.test/r/ABC234',
      );
    });
  });

  group('inviteText', () {
    test('contains the code and the link', () {
      final text = RoomShare.inviteText('ABC234', base: base);
      expect(text, contains('ABC234'));
      expect(text, contains('https://example.test/r/ABC234'));
    });

    test('join invite uses the join link', () {
      final text = RoomShare.inviteText('ABC234', spectate: false, base: base);
      expect(text, contains('?mode=join'));
    });
  });

  group('roomIdFromLink', () {
    test('parses a bare code', () {
      expect(RoomShare.roomIdFromLink('abc234'), 'ABC234');
    });

    test('parses an https /r/ link', () {
      expect(
        RoomShare.roomIdFromLink('https://example.test/r/ABC234'),
        'ABC234',
      );
    });

    test('parses /r/ link with query', () {
      expect(
        RoomShare.roomIdFromLink('https://example.test/r/ABC234?mode=join'),
        'ABC234',
      );
    });

    test('parses cchess:// deep links', () {
      expect(RoomShare.roomIdFromLink('cchess://spectate/ABC234'), 'ABC234');
      expect(RoomShare.roomIdFromLink('cchess://join/ABC234'), 'ABC234');
    });

    test('parses in-app lobby query links', () {
      expect(
        RoomShare.roomIdFromLink('/online-lobby?spectate=ABC234'),
        'ABC234',
      );
      expect(RoomShare.roomIdFromLink('/online-lobby?join=ABC234'), 'ABC234');
    });

    test('returns null for junk input', () {
      expect(RoomShare.roomIdFromLink(''), isNull);
      expect(RoomShare.roomIdFromLink('https://example.test/about'), isNull);
      expect(RoomShare.roomIdFromLink('not a link'), isNull);
    });

    test('round-trips with linkFor', () {
      final link = RoomShare.linkFor('K7M9PQ', base: base);
      expect(RoomShare.roomIdFromLink(link), 'K7M9PQ');
      final joinLink = RoomShare.linkFor('K7M9PQ', spectate: false, base: base);
      expect(RoomShare.roomIdFromLink(joinLink), 'K7M9PQ');
    });
  });

  group('isJoinLink', () {
    test('true for mode=join and ?join=', () {
      expect(
        RoomShare.isJoinLink('https://example.test/r/ABC234?mode=join'),
        isTrue,
      );
      expect(RoomShare.isJoinLink('/online-lobby?join=ABC234'), isTrue);
      expect(RoomShare.isJoinLink('cchess://join/ABC234'), isTrue);
    });

    test('false for spectate / bare links', () {
      expect(RoomShare.isJoinLink('https://example.test/r/ABC234'), isFalse);
      expect(RoomShare.isJoinLink('cchess://spectate/ABC234'), isFalse);
      expect(RoomShare.isJoinLink('ABC234'), isFalse);
    });
  });
}
