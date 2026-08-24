import 'package:flutter_test/flutter_test.dart';
import 'package:dynoc/services/station_name_matcher.dart';

void main() {
  final m = StationNameMatcher.instance;

  group('normalize', () {
    test('trims and lowercases', () {
      expect(m.normalize('  HELLO '), 'hello');
    });

    test('strips parenthetical', () {
      expect(m.normalize('TUN RAZAK EXCHANGE (TRX)'), 'tun razak exchange');
    });

    test('strips bank rakyat prefix', () {
      expect(m.normalize('BANK RAKYAT BANGSAR'), 'bangsar');
    });

    test('strips cgc prefix', () {
      expect(m.normalize('CGC GLENMARIE'), 'glenmarie');
    });

    test('strips known suffix after dash', () {
      expect(m.normalize('BANDARAYA - UOB'), 'bandaraya');
      expect(m.normalize('KL SENTRAL - REDONE'), 'kl sentral');
    });

    test('normalizes hyphen spacing', () {
      expect(m.normalize('SOUTH QUAY-USJ 1'), 'south quay usj 1');
      expect(m.normalize('SOUTH QUAY - USJ 1'), 'south quay usj 1');
      expect(m.normalize('SUNWAY-SETIA JAYA'), 'sunway setia jaya');
      expect(m.normalize('SUNWAY - SETIA JAYA'), 'sunway setia jaya');
    });

    test('normalizes letter-digit spacing', () {
      expect(m.normalize('USJ7'), 'usj 7');
      expect(m.normalize('USJ 7'), 'usj 7');
    });
  });

  group('match', () {
    test('identical names match', () {
      expect(m.match('PASAR SENI', 'PASAR SENI'), isTrue);
    });

    test('case insensitive', () {
      expect(m.match('pasar seni', 'PASAR SENI'), isTrue);
    });

    test('corporate prefix', () {
      expect(m.match('BANGSAR', 'BANK RAKYAT BANGSAR'), isTrue);
      expect(m.match('GLENMARIE', 'CGC GLENMARIE'), isTrue);
    });

    test('corporate suffix', () {
      expect(m.match('BANDARAYA', 'BANDARAYA - UOB'), isTrue);
      expect(m.match('KL SENTRAL', 'KL SENTRAL - REDONE'), isTrue);
      expect(m.match('KAMPUNG BARU', 'KAMPUNG BARU - CBP COOPBANK PERTAMA'), isTrue);
    });

    test('parenthetical', () {
      expect(m.match('TUN RAZAK EXCHANGE (TRX)', 'TUN RAZAK EXCHANGE'), isTrue);
    });

    test('hyphen spacing', () {
      expect(m.match('SOUTH QUAY - USJ 1', 'SOUTH QUAY-USJ 1'), isTrue);
      expect(m.match('SUNWAY - SETIA JAYA', 'SUNWAY-SETIA JAYA'), isTrue);
    });

    test('digit spacing', () {
      expect(m.match('USJ 7', 'USJ7'), isTrue);
    });

    test('alias table', () {
      expect(m.match('KENTONMEN', 'KENTOMEN'), isTrue);
      expect(m.match('KENTOMEN', 'KENTONMEN'), isTrue);
      expect(m.match('KINRARA BK5', 'KINRARA'), isTrue);
    });

    test('no false positive — prefix name vs longer name', () {
      expect(m.match('KAJANG', 'KAJANG 2'), isFalse);
      expect(m.match('SERDANG', 'SERDANG JAYA'), isFalse);
      expect(m.match('SERDANG', 'SERDANG RAYA UTARA'), isFalse);
      expect(m.match('SERDANG', 'SERDANG RAYA SELATAN'), isFalse);
    });

    test('no false positive on different stations', () {
      expect(m.match('BATU CAVES', 'BATU TIGA'), isFalse);
      expect(m.match('KL SENTRAL', 'KLCC'), isFalse);
      expect(m.match('PASAR SENI', 'PASAR MALAM'), isFalse);
    });
  });
}
