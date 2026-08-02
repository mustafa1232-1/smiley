class GateValidator {
  const GateValidator();

  bool accepts(DateTime date) {
    return date.year == 2026 && date.month == 8 && date.day == 3;
  }
}
