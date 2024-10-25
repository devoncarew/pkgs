import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;

class Package implements Comparable<Package> {
  final Directory dir;
  yaml.YamlMap? pubspec;

  Package(this.dir) {
    var pubspecFile = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      pubspec = yaml.loadYaml(pubspecFile.readAsStringSync()) as yaml.YamlMap;
    }
  }

  bool get valid => pubspec != null;

  String get path => dir.path;

  String get dirName => p.basename(dir.path);

  String get pubspecName => pubspec!['name'] as String;

  String? get description => (pubspec?['description'] as String?)?.trim();

  bool get publishable => pubspec != null && pubspec!['publish_to'] != 'none';

  String? get pubBadgeRef {
    if (!publishable) return null;

    return '[![pub package](https://img.shields.io/pub/v/$pubspecName.svg)]'
        '(https://pub.dev/packages/$pubspecName)';
  }

  String get prLabelerConfig => '''
'package:$pubspecName':
  - changed-files:
    - '$path/**'
''';

  String get tableRow => '| [$pubspecName]($path/) | '
      '${description ?? ''} | '
      '${publishable ? pubBadgeRef : ''} |';

  @override
  int compareTo(Package other) => dirName.compareTo(other.dirName);

  @override
  String toString() => dirName;
}
