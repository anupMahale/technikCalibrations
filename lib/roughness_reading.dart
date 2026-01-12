class RoughnessReading {
  final double? ra;
  final double? rmax;
  final double? rz;
  final double? raConfidence;
  final double? rmaxConfidence;
  final double? rzConfidence;

  RoughnessReading({
    this.ra,
    this.rmax,
    this.rz,
    this.raConfidence,
    this.rmaxConfidence,
    this.rzConfidence,
  });

  bool get isComplete =>
      ra != null &&
      (raConfidence ?? 0) > 0.9 &&
      rmax != null &&
      (rmaxConfidence ?? 0) > 0.9 &&
      rz != null &&
      (rzConfidence ?? 0) > 0.9;

  @override
  String toString() {
    return 'RoughnessReading(ra: $ra ($raConfidence), rmax: $rmax ($rmaxConfidence), rz: $rz ($rzConfidence))';
  }
}
