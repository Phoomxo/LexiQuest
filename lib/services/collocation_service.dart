class CollocationService {
  const CollocationService();

  List<String> getCollocations(String word) {
    final lower = word.toLowerCase().trim();
    switch (lower) {
      case 'decision':
        return [
          'make a decision',
          'reach a decision',
          'firm decision',
          'tough decision',
        ];
      case 'opportunity':
        return [
          'great opportunity',
          'seize the opportunity',
          'equal opportunity',
          'golden opportunity',
        ];
      case 'sustainable':
        return [
          'sustainable development',
          'sustainable energy',
          'sustainable growth',
          'sustainable practice',
        ];
      default:
        return ['use $lower in context', 'key $lower aspect'];
    }
  }
}
