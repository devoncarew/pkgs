import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;

// todo: split up the impl

// todo: tests

// todo: readme

// todo: update any variables in workflow files (# {pkgs.versions})

void main(List<String> args) {
  var dir = pkgsDir;
  if (dir == null) {
    stderr.writeln('No pkgs/ or packages/ dir found.');
    exitCode = 1;
    return;
  }

  var packages = dir
      .listSync()
      .whereType<Directory>()
      .map((d) => Package(d))
      .where((p) => p.valid)
      .toList()
    ..sort();

  print('Found:');
  for (var package in packages) {
    print('  ${package.path}');
  }
  print('');

  var readme = File('README.md');
  // print('## Packages'); // todo:
  var content = '''
| Package | Description | Version |
| --- | --- | --- |
${packages.map((p) => p.tableRow).join('\n')}
''';
  _updateReadme(readme, content);
  print('Updated ${readme.path}.');

  // issues templates
  var templates = templateDir;
  for (var package in packages) {
    var file = File(p.join(templates.path, '${package.pubspecName}.md'));
    file.writeAsStringSync('''
---
name: "package:${package.pubspecName}"
about: "Create a bug or file a feature request against package:${package.pubspecName}."
labels: "package:${package.pubspecName}"
---
''');
  }
  print('Wrote templates to ${templates.path}.');

  // PR labeler
  var labelConfigFile = File(p.join('.github', 'labeler.yml'));
  labelConfigFile.writeAsStringSync('''
# Configuration for .github/workflows/pull_request_label.yml.

'type-infra':
  - '.github/**'

${packages.map((p) => p.prLabelerConfig).join('\n')}''');
  print('Wrote ${labelConfigFile.path}');

  // Workflow definitions.
  var wd = workflowsDir;
  for (var package in packages) {
    var file = File(p.join(wd.path, '${package.pubspecName}.yml'));
    var branch = getDefaultBranch(Directory.current)!;
    var content = workflowDefinition
        .replaceAll(r'{{package.name}}', package.pubspecName)
        .replaceAll(r'{{package.path}}', package.path)
        .replaceAll('{{branch}}', branch);
    file.writeAsStringSync(content);
  }
  print('Wrote workflow files to ${wd.path}.');
}

void _updateReadme(File file, String content) {
  const title = '## Packages';
  if (!file.existsSync()) {
    file.writeAsStringSync('''
$title

$content''');
  } else if (!file.readAsStringSync().contains(title)) {
    file.writeAsStringSync('\n$title\n\n$content', mode: FileMode.append);
  } else {
    var lines = file.readAsLinesSync();
    var buf = StringBuffer();
    bool skip = false;

    for (var line in lines) {
      if (line.startsWith('## ')) {
        if (skip) {
          skip = false;
        } else if (line == title) {
          skip = true;
          buf.writeln('$title\n\n$content');
        }
      }
      if (!skip) {
        buf.writeln(line);
      }
    }

    file.writeAsStringSync(buf.toString());
  }
}

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

  String get pubspecName => pubspec!['name'];

  String? get description {
    var pubspecFile = File(p.join(dir.path, 'pubspec.yaml'));
    var pubspec = yaml.loadYaml(pubspecFile.readAsStringSync()) as yaml.YamlMap;
    return (pubspec['description'] as String?)?.trim();
  }

  bool get publishable => pubspec != null && pubspec!['publish_to'] != 'none';

  String? get pubBadgeRef {
    if (!publishable) return null;

    return '[![pub package](https://img.shields.io/pub/v/$pubspecName.svg)]'
        '(https://pub.dev/packages/$pubspecName)';
  }

  String get prLabelerConfig => '''
'package:$pubspecName':
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

Directory? get pkgsDir => dirIfExists('pkgs') ?? dirIfExists('packages');

Directory? dirIfExists(String path) {
  var dir = Directory(path);
  return dir.existsSync() ? dir : null;
}

Directory get templateDir {
  var dir = Directory(p.join('.github', 'ISSUE_TEMPLATE'));
  dir.createSync(recursive: true);
  return dir;
}

Directory get workflowsDir {
  var dir = Directory(p.join('.github', 'workflows'));
  dir.createSync(recursive: true);
  return dir;
}

/// This makes a best effort to find the default branch of the given repo.
String? getDefaultBranch(Directory repoDir) {
  const branchNames = {'main', 'master'};

  var configFile = File(p.join(repoDir.path, '.git', 'config'));
  if (!configFile.existsSync()) return null;

  var lines = configFile.readAsLinesSync();

  for (var name in branchNames) {
    if (lines.contains('[branch "$name"]')) {
      return name;
    }
  }

  return 'master';
}

const String workflowDefinition = r'''
name: package:{{package.name}}
permissions: read-all

on:
  pull_request:
    branches: [ {{branch}} ]
    paths:
      - '.github/workflows/{{package.name}}.yml'
      - '{{package.path}}/**'
  push:
    branches: [ {{branch}} ]
    paths:
      - '.github/workflows/{{package.name}}.yml'
      - '{{package.path}}/**'
  schedule:
    - cron: '0 0 * * 0' # weekly

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: {{package.path}}
    strategy:
      fail-fast: false
      matrix:
        sdk: ['stable', 'dev'] # {pkgs.versions}
        include:
          - sdk: 'stable'
            run-tests: true
    steps:
      - uses: actions/checkout@ac593985615ec2ede58e132d2e21d2b1cbd6127c
      - uses: dart-lang/setup-dart@b6470d418f5d8e67774a46d5d89483bd1baaf3fb
        with:
          sdk: ${{ matrix.sdk }}

      - run: dart pub get

      - run: dart analyze --fatal-infos

      - run: dart format --output=none --set-exit-if-changed .
        if: ${{matrix.run-tests}}

      - run: dart test
        if: ${{matrix.run-tests}}
''';
