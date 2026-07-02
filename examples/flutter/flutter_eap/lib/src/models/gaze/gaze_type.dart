/// Gaze movement type
enum GazeType {
  /// No movement
  none(0),

  /// Fixation - eye is relatively stable
  fixation(1),

  /// Saccade - rapid eye movement
  saccade(2);

  final int value;
  const GazeType(this.value);

  static GazeType fromValue(int value) {
    switch (value) {
      case 0:
        return GazeType.none;
      case 1:
        return GazeType.fixation;
      case 2:
        return GazeType.saccade;
      default:
        return GazeType.none;
    }
  }
}
