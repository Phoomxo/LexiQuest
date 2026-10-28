import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/account_link_coordinator.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';

void main() {
  final resetLink = Uri.parse(
    'https://vocab-learning-app-219ef.web.app/auth/action?mode=resetPassword&oobCode=reset-code',
  );
  final verifyLink = Uri.parse(
    'https://vocab-learning-app-219ef.web.app/auth/action?mode=verifyEmail&oobCode=verify-code',
  );

  test('cold reset action link navigates to the typed reset route', () async {
    final navigations = <({AppRoute route, Object? arguments})>[];
    final coordinator = AccountLinkCoordinator.forTesting(
      initialLink: Future<Uri?>.value(resetLink),
      uriLinks: const Stream<Uri>.empty(),
      navigate: (route, arguments) =>
          navigations.add((route: route, arguments: arguments)),
    );

    await coordinator.start();

    expect(navigations, hasLength(1));
    expect(navigations.single.route, AppRoute.resetPassword);
    expect(navigations.single.arguments, isA<ResetPasswordRouteArgs>());
    expect(
      (navigations.single.arguments! as ResetPasswordRouteArgs).code,
      'reset-code',
    );
  });

  test('handles a duplicate cold reset link only once', () async {
    final controller = StreamController<Uri>();
    final navigations = <({AppRoute route, Object? arguments})>[];
    final coordinator = AccountLinkCoordinator.forTesting(
      initialLink: Future<Uri?>.value(resetLink),
      uriLinks: controller.stream,
      navigate: (route, arguments) =>
          navigations.add((route: route, arguments: arguments)),
    );

    await coordinator.start();
    controller.add(resetLink);
    await Future<void>.delayed(Duration.zero);

    expect(navigations, hasLength(1));
    expect(navigations.single.route, AppRoute.resetPassword);
    await controller.close();
    coordinator.dispose();
  });

  test('handles a duplicate cold verification link only once', () async {
    final controller = StreamController<Uri>();
    final navigations = <({AppRoute route, Object? arguments})>[];
    final coordinator = AccountLinkCoordinator.forTesting(
      initialLink: Future<Uri?>.value(verifyLink),
      uriLinks: controller.stream,
      navigate: (route, arguments) =>
          navigations.add((route: route, arguments: arguments)),
    );

    await coordinator.start();
    controller.add(verifyLink);
    await Future<void>.delayed(Duration.zero);

    expect(navigations, hasLength(1));
    expect(navigations.single.route, AppRoute.verifyEmail);
    await controller.close();
    coordinator.dispose();
  });

  test(
    'handles a later distinct action link after deduplicating a cold link',
    () async {
      final controller = StreamController<Uri>();
      final navigations = <({AppRoute route, Object? arguments})>[];
      final coordinator = AccountLinkCoordinator.forTesting(
        initialLink: Future<Uri?>.value(resetLink),
        uriLinks: controller.stream,
        navigate: (route, arguments) =>
            navigations.add((route: route, arguments: arguments)),
      );

      await coordinator.start();
      controller
        ..add(resetLink)
        ..add(
          Uri.parse(
            'https://vocab-learning-app-219ef.web.app/auth/action?mode=resetPassword&oobCode=later-code',
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(2));
      expect(
        (navigations.last.arguments! as ResetPasswordRouteArgs).code,
        'later-code',
      );
      await controller.close();
      coordinator.dispose();
    },
  );

  test(
    'warm verification action link navigates to the typed verification route',
    () async {
      final controller = StreamController<Uri>();
      final navigations = <({AppRoute route, Object? arguments})>[];
      final coordinator = AccountLinkCoordinator.forTesting(
        initialLink: Future<Uri?>.value(null),
        uriLinks: controller.stream,
        navigate: (route, arguments) =>
            navigations.add((route: route, arguments: arguments)),
      );
      await coordinator.start();
      controller.add(verifyLink);
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(1));
      expect(navigations.single.route, AppRoute.verifyEmail);
      expect(navigations.single.arguments, isA<VerifyEmailActionRouteArgs>());
      expect(
        (navigations.single.arguments! as VerifyEmailActionRouteArgs).code,
        'verify-code',
      );
      await controller.close();
      coordinator.dispose();
    },
  );

  test(
    'subscribes to warm links before the initial lookup completes',
    () async {
      final initialLink = Completer<Uri?>();
      final controller = StreamController<Uri>();
      final navigations = <({AppRoute route, Object? arguments})>[];
      final coordinator = AccountLinkCoordinator.forTesting(
        initialLink: initialLink.future,
        uriLinks: controller.stream,
        navigate: (route, arguments) =>
            navigations.add((route: route, arguments: arguments)),
      );

      final starting = coordinator.start();
      controller.add(verifyLink);
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(1));
      initialLink.complete(null);
      await starting;
      await controller.close();
      coordinator.dispose();
    },
  );

  test(
    'contains an initial-link failure and keeps warm links active',
    () async {
      final controller = StreamController<Uri>();
      final navigations = <({AppRoute route, Object? arguments})>[];
      final coordinator = AccountLinkCoordinator.forTesting(
        initialLink: Future<Uri?>.error(StateError('initial-link-unavailable')),
        uriLinks: controller.stream,
        navigate: (route, arguments) =>
            navigations.add((route: route, arguments: arguments)),
      );

      await coordinator.start();
      controller.add(resetLink);
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(1));
      await controller.close();
      coordinator.dispose();
    },
  );

  test('contains stream errors without disabling later links', () async {
    final controller = StreamController<Uri>();
    final navigations = <({AppRoute route, Object? arguments})>[];
    final unhandledErrors = <Object>[];
    final coordinator = AccountLinkCoordinator.forTesting(
      initialLink: Future<Uri?>.value(null),
      uriLinks: controller.stream,
      navigate: (route, arguments) =>
          navigations.add((route: route, arguments: arguments)),
    );

    await runZonedGuarded(() async {
      await coordinator.start();
      controller.addError(StateError('stream-unavailable'));
      controller.add(verifyLink);
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => unhandledErrors.add(error));

    expect(unhandledErrors, isEmpty);
    expect(navigations, hasLength(1));
    await controller.close();
    coordinator.dispose();
  });

  test('foreign and malformed links are ignored without navigation', () async {
    final navigations = <({AppRoute route, Object? arguments})>[];
    final coordinator = AccountLinkCoordinator.forTesting(
      initialLink: Future<Uri?>.value(
        Uri.parse(
          'https://evil.example/auth/action?mode=resetPassword&oobCode=secret',
        ),
      ),
      uriLinks: const Stream<Uri>.empty(),
      navigate: (route, arguments) =>
          navigations.add((route: route, arguments: arguments)),
    );

    await coordinator.start();

    expect(navigations, isEmpty);
  });
}
