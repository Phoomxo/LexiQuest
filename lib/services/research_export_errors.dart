class InsufficientData implements Exception {
  const InsufficientData([
    this.message = 'Insufficient real observations for this report.',
  ]);

  final String message;

  @override
  String toString() => 'InsufficientData: $message';
}
