import 'dart:async';

/// Test-only fixed owner replayed to each listener without closing the stream.
Stream<String?> persistentProgressOwnerFixture(String ownerId) =>
    Stream<String?>.multi((events) {
      events.addSync(ownerId);
    }, isBroadcast: true);
