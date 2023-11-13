import 'dart:io';
import 'dart:math' as math;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'workspace.dart';

// todo: readme

// todo: update any variables in workflow files (# {pkgs.versions})

// todo: re-generate workflow files for packages
// todo: update the package table for the repo readme
// todo: update the issue templates for a repo
// todo: update the PR labeller for a repo

Future<int> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'pkgs',
    '''
Manage Dart package in a mono-repo.

This command requires a workspace.yaml file to exist. An example of a simple
configuration:

    # Sample workspace.yaml configuration file.
    packages:
      - pkgs/*''',
  )
    ..addCommand(ListCommand())
    ..addCommand(PubGetCommand())
    ..addCommand(GenerateCommand());

  return await runner.run(args) ?? 0;
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
        sdk: [stable, dev] # {pkgs.versions}
        include:
          - sdk: stable
            run-tests: true
    steps:
      - uses: actions/checkout@2541b1294d2704b0964813337f33b291d3f8596b
      - uses: dart-lang/setup-dart@b64355ae6ca0b5d484f0106a033dd1388965d06d
        with:
          sdk: ${{ matrix.sdk }}

      - run: dart pub get

      - run: dart analyze --fatal-infos

      - run: dart format --output=none --set-exit-if-changed .
        if: ${{matrix.run-tests}}

      - run: dart test
        if: ${{matrix.run-tests}}
''';

abstract class AbstractCommand extends Command<int> {
  @override
  final String name;

  @override
  final String description;

  Workspace? _workspace;

  Workspace? get workspace =>
      (_workspace ??= Workspace.locate() ?? Workspace.fromPkgs());

  AbstractCommand({required this.name, required this.description});

  @override
  Future<int> run();
}

class ListCommand extends AbstractCommand {
  ListCommand()
      : super(
          name: 'list',
          description: 'List the packages that make up this workspace.',
        );

  @override
  Future<int> run() async {
    final workspace = this.workspace;
    if (workspace == null) {
      print('No workspace found.');
      return 1;
    }

    if (workspace.packages.isEmpty) {
      print('No packages found.');
      return 0;
    }

    print('${workspace.packages.length} packages:');
    for (final package in workspace.packages) {
      print('  - ${package.path}');
    }

    return 0;
  }
}

class PubGetCommand extends AbstractCommand {
  PubGetCommand() : super(name: 'pub-get', description: 'todo: doc') {
    argParser.addFlag(
      'upgrade',
      negatable: true,
      defaultsTo: true,
      help: 'todo:',
    );
  }

  @override
  Future<int> run() async {
    final workspace = this.workspace;
    if (workspace == null) {
      print('No workspace found.');
      return 1;
    }

    if (workspace.packages.isEmpty) {
      print('No packages found.');
      return 0;
    }

    final pubUpgrade = argResults!['upgrade'] as bool;
    final command = pubUpgrade ? 'upgrade' : 'get';

    var firstPackage = true;
    var exitCode = 0;

    for (final package in workspace.packages) {
      if (!firstPackage) {
        print('');
      }
      firstPackage = false;

      print('[${package.path}] dart pub $command');
      print('');

      final process = await Process.start(
        Platform.executable,
        ['pub', command, '--color'],
        workingDirectory: package.path,
      );
      process.stdout.listen(stdout.add);
      process.stderr.listen(stderr.add);

      exitCode = math.max(exitCode, await process.exitCode);
    }

    return exitCode;
  }
}

class GenerateCommand extends AbstractCommand {
  GenerateCommand()
      : super(
          name: 'generate',
          description: 'Generate various artifacts and package meta-data.',
        );

  @override
  Future<int> run() async {
    // pkgs generate [--readme] [--issues] [--labeller] [--workflows] [--all]

    // todo: clean this up

    final workspace = this.workspace;
    if (workspace == null) {
      print('No workspace found.');
      return 1;
    }

    var packages = workspace.packages.toList()..sort();

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

    return 0;
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
}
