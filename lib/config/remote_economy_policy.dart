/// Controls client visibility of remote, spendable economy features.
///
/// This is deliberately closed by default. Runtime service readiness and public
/// Dart defines must not enable spending or ranking functionality.
final class RemoteEconomyPolicy {
  const RemoteEconomyPolicy({
    this.shopAndPurchasesEnabled = false,
    this.leaderboardEnabled = false,
  });

  final bool shopAndPurchasesEnabled;
  final bool leaderboardEnabled;
}
