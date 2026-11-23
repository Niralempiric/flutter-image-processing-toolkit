// Summarizes an lcov report: prints a per-file table, writes a badge SVG, and
// can fail when line coverage is below a minimum.
//
//   dart tool/coverage_summary.dart [--lcov coverage/lcov.info]
//       [--svg coverage/coverage.svg] [--min 80]
//
// When GITHUB_STEP_SUMMARY is set, the table is also appended to it.
import 'dart:io';

/// Line coverage of one source file.
class FileCoverage {
  const FileCoverage(this.path, this.hit, this.found);

  final String path;
  final int hit;
  final int found;

  double get percent => found == 0 ? 100 : 100 * hit / found;
}

/// Parses an lcov report into per-file line counts (the SF, LF and LH records).
List<FileCoverage> parseLcov(String lcov) {
  final files = <FileCoverage>[];
  String? path;
  var found = 0;
  var hit = 0;
  for (final raw in lcov.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      path = line.substring(3);
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hit = int.parse(line.substring(3));
    } else if (line == 'end_of_record' && path != null) {
      files.add(FileCoverage(path, hit, found));
      path = null;
    }
  }
  return files;
}

/// Overall line coverage, 0 to 100. An empty report counts as 0.
double totalPercent(List<FileCoverage> files) {
  final found = files.fold<int>(0, (sum, f) => sum + f.found);
  final hit = files.fold<int>(0, (sum, f) => sum + f.hit);
  return found == 0 ? 0 : 100 * hit / found;
}

/// Badge color for a coverage percentage.
String badgeColor(double percent) {
  if (percent >= 90) return '#4c1';
  if (percent >= 80) return '#97ca00';
  if (percent >= 70) return '#dfb317';
  if (percent >= 50) return '#fe7d37';
  return '#e05d44';
}

/// A flat, two-part SVG badge reading "coverage  NN.N%".
String badgeSvg(double percent) {
  final value = '${percent.toStringAsFixed(1)}%';
  const labelWidth = 62;
  const valueWidth = 54;
  const width = labelWidth + valueWidth;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="20" '
      'role="img" aria-label="coverage: $value">'
      '<title>coverage: $value</title>'
      '<clipPath id="r"><rect width="$width" height="20" rx="3"/></clipPath>'
      '<g clip-path="url(#r)">'
      '<rect width="$labelWidth" height="20" fill="#555"/>'
      '<rect x="$labelWidth" width="$valueWidth" height="20" '
      'fill="${badgeColor(percent)}"/>'
      '</g>'
      '<g fill="#fff" text-anchor="middle" '
      'font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">'
      '<text x="${labelWidth / 2}" y="14">coverage</text>'
      '<text x="${labelWidth + valueWidth / 2}" y="14">$value</text>'
      '</g></svg>\n';
}

String markdownTable(List<FileCoverage> files) {
  final rows = [...files]..sort((a, b) => a.path.compareTo(b.path));
  final buffer = StringBuffer()
    ..writeln('### Line coverage: ${totalPercent(files).toStringAsFixed(1)}%')
    ..writeln()
    ..writeln('| File | Lines | Coverage |')
    ..writeln('|---|---|---|');
  for (final f in rows) {
    buffer.writeln(
      '| `${f.path}` | ${f.hit}/${f.found} | ${f.percent.toStringAsFixed(1)}% |',
    );
  }
  return buffer.toString();
}

void main(List<String> args) {
  exitCode = run(args);
}

int run(List<String> args) {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final lcovFile = File(option('lcov', 'coverage/lcov.info'));
  if (!lcovFile.existsSync()) {
    stderr.writeln('No lcov report at ${lcovFile.path}.');
    return 2;
  }
  final min = double.tryParse(option('min', '0')) ?? 0;
  final files = parseLcov(lcovFile.readAsStringSync());
  final percent = totalPercent(files);

  final table = markdownTable(files);
  stdout.write(table);
  File(
    option('svg', 'coverage/coverage.svg'),
  ).writeAsStringSync(badgeSvg(percent));
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync(table, mode: FileMode.append);
  }
  if (percent < min) {
    stderr.writeln(
      'Line coverage ${percent.toStringAsFixed(1)}% is below the required '
      '${min.toStringAsFixed(1)}%.',
    );
    return 1;
  }
  return 0;
}
