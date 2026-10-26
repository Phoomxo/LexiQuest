import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frozen feature catalog has exactly eight domains and f01-f44', () {
    final file = File('docs/design/feature-catalog-1.3.0.json');
    expect(file.existsSync(), isTrue, reason: 'machine-readable catalog missing');

    final catalog = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(catalog['revision'], '1.3.0');

    final capabilities = catalog['capabilities'] as List<dynamic>;
    expect(capabilities, hasLength(44));
    expect(
      capabilities.map((entry) => (entry as Map<String, dynamic>)['id']),
      [for (var index = 1; index <= 44; index++) 'f${index.toString().padLeft(2, '0')}'],
    );

    final domains = capabilities
        .map((entry) => (entry as Map<String, dynamic>)['domain'])
        .toSet();
    expect(domains, hasLength(8));

    for (final rawEntry in capabilities) {
      final entry = rawEntry as Map<String, dynamic>;
      expect(entry['capability'], isNotEmpty);
      expect(entry['authority'], 'design-catalog');
      expect(entry['rolloutState'], 'unverified');
      expect(entry['evidence'], isNotEmpty);
    }
  });
}
