import 'package:flutter_test/flutter_test.dart';

import '../tool/coverage_summary.dart';

void main() {
  const lcov = '''
SF:lib/a.dart
DA:1,1
LF:10
LH:9
end_of_record
SF:lib/b.dart
LF:10
LH:5
end_of_record
''';

  test('parses per-file line counts from lcov', () {
    final files = parseLcov(lcov);

    expect(files.map((f) => f.path), ['lib/a.dart', 'lib/b.dart']);
    expect(files.map((f) => f.hit), [9, 5]);
    expect(files.map((f) => f.found), [10, 10]);
    expect(files.first.percent, 90);
  });

  test('totals coverage over all lines, not the mean of file percentages', () {
    expect(totalPercent(parseLcov(lcov)), 70);
    expect(
      totalPercent(
        parseLcov(
          'SF:a\nLF:1\nLH:1\nend_of_record\nSF:b\nLF:99\nLH:0\nend_of_record\n',
        ),
      ),
      1,
    );
  });

  test('an empty report is 0 percent', () {
    expect(totalPercent(parseLcov('')), 0);
  });

  test('picks a badge color by threshold', () {
    expect(badgeColor(95), '#4c1');
    expect(badgeColor(85), '#97ca00');
    expect(badgeColor(75), '#dfb317');
    expect(badgeColor(60), '#fe7d37');
    expect(badgeColor(10), '#e05d44');
  });

  test('the badge states the percentage to one decimal', () {
    final svg = badgeSvg(86.36);

    expect(svg, contains('86.4%'));
    expect(svg, contains('coverage'));
    expect(svg, startsWith('<svg'));
  });
}
