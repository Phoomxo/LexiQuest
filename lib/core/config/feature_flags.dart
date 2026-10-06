/// Feature flags for gradual rollout of new features
///
/// This allows us to toggle features on/off without code changes
class FeatureFlags {
  /// Enable the redesigned UI (2026 redesign)
  ///
  /// When true, uses new design system with:
  /// - Light mode with warm surfaces
  /// - Sky blue accent colors
  /// - Fully rounded components
  /// - Modern typography (Kanit + Sarabun)
  static bool useRedesignedUI = false;

  /// Toggle the redesigned UI on/off
  static void toggleRedesignUI() {
    useRedesignedUI = !useRedesignedUI;
  }

  /// Enable/disable redesigned UI explicitly
  static void setRedesignUI(bool enabled) {
    useRedesignedUI = enabled;
  }

  /// Get current UI mode as string
  static String get currentUIMode => useRedesignedUI ? 'Redesign 2026' : 'Classic';
}
