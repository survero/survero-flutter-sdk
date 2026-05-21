import 'package:flutter_test/flutter_test.dart';
import 'package:survero/src/models/survey_config.dart';
import 'package:survero/src/utils/color_utils.dart';

void main() {
  group('SurveyConfig', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'test-id',
        'title': 'How was your experience?',
        'type': 'star_rating',
        'is_active': true,
        'settings': {'maxStars': 5, 'showComment': true},
        'style': {
          'primaryColor': '#E30B5C',
          'fontFamily': 'Inter',
          'borderRadius': 8,
        },
      };

      final config = SurveyConfig.fromJson(json);

      expect(config.id, 'test-id');
      expect(config.title, 'How was your experience?');
      expect(config.type, 'star_rating');
      expect(config.isActive, true);
      expect(config.settings.maxStars, 5);
      expect(config.settings.showComment, true);
      expect(config.style.primaryColor, '#E30B5C');
      expect(config.style.fontFamily, 'Inter');
      expect(config.style.borderRadius, 8);
    });

    test('uses defaults for missing fields', () {
      final json = {
        'id': 'test-id',
        'title': 'Test',
        'type': 'star_rating',
      };

      final config = SurveyConfig.fromJson(json);

      expect(config.settings.maxStars, 5);
      expect(config.settings.showComment, true);
      expect(config.style.primaryColor, '#E30B5C');
    });
  });

  group('hexToColor', () {
    test('parses hex color with hash', () {
      final color = hexToColor('#FF0000');
      expect(color.r, 1.0);
      expect(color.g, 0.0);
      expect(color.b, 0.0);
    });

    test('parses hex color without hash', () {
      final color = hexToColor('00FF00');
      expect(color.g, 1.0);
    });
  });
}
