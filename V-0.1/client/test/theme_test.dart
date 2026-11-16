import 'package:flutter_test/flutter_test.dart';
import 'package:loyfinity_app/core/theme.dart';

void main() {
  test('Loyfinity uses Material 3 and its navy-blue-gold brand palette', () {
    final theme = buildLoyfinityTheme();
    expect(theme.useMaterial3, isTrue);
    expect(LoyColors.navy.value, 0xFF0B2942);
    expect(LoyColors.blue.value, 0xFF1379C8);
    expect(LoyColors.gold.value, 0xFFF3B800);
  });
}
