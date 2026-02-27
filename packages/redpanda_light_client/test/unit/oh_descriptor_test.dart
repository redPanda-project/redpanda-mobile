import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

void main() {
  group('OHDescriptor', () {
    test('should serialize to JSON and back', () {
      final descriptor = OHDescriptor(
        serverEndpoint: '192.168.1.1:59558',
        handleId: List.generate(20, (i) => i),
        authPublicKey: List.generate(65, (i) => i),
      );

      final json = descriptor.toJson();
      final reconstructed = OHDescriptor.fromJson(json);

      expect(reconstructed.serverEndpoint, descriptor.serverEndpoint);
      expect(reconstructed.handleId, descriptor.handleId);
      expect(reconstructed.authPublicKey, descriptor.authPublicKey);
    });

    test('should serialize to JSON map and back', () {
      final descriptor = OHDescriptor(
        serverEndpoint: 'localhost:9000',
        handleId: List.filled(20, 0xAB),
        authPublicKey: List.filled(65, 0xCD),
      );

      final map = descriptor.toJsonMap();
      expect(map['ep'], 'localhost:9000');
      expect(map.containsKey('id'), true);
      expect(map.containsKey('pk'), true);

      final reconstructed = OHDescriptor.fromJsonMap(map);
      expect(reconstructed, equals(descriptor));
    });

    test('should support equality', () {
      final a = OHDescriptor(
        serverEndpoint: 'host:1234',
        handleId: [1, 2, 3],
        authPublicKey: [4, 5, 6],
      );
      final b = OHDescriptor(
        serverEndpoint: 'host:1234',
        handleId: [1, 2, 3],
        authPublicKey: [4, 5, 6],
      );
      final c = OHDescriptor(
        serverEndpoint: 'host:5678',
        handleId: [1, 2, 3],
        authPublicKey: [4, 5, 6],
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromJsonMap rejects invalid handleId length', () {
      final map = {
        'ep': 'host:1234',
        'id': '0102030405', // 5 bytes, not 20
        'pk': '04${'ab' * 64}', // 65 bytes
      };
      expect(
        () => OHDescriptor.fromJsonMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJsonMap rejects invalid authPublicKey length', () {
      final map = {
        'ep': 'host:1234',
        'id': '${'ab' * 20}', // 20 bytes OK
        'pk': '0102030405', // 5 bytes, not 65
      };
      expect(
        () => OHDescriptor.fromJsonMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
