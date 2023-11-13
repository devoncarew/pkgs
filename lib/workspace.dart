import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as y;

import 'model.dart';

class Workspace {
  static const fileName = 'workspace.yaml';

  /// Creates a new workspace from the given directory (defaulting to the cwd).
  ///
  /// This requires the presence of a workspace.yaml file.
  static Workspace? locate({Directory? fromDir}) {
    fromDir ??= Directory.current;

    final file = File(p.join(fromDir.path, fileName));
    if (!file.existsSync()) return null;

    var workspaceYaml = y.loadYaml(file.readAsStringSync()) as y.YamlMap;

    return Workspace._from(root: fromDir, yaml: workspaceYaml);
  }

  /// Try and create a workspace from the cwd, assuming that there is no
  /// `workspace.yaml` file and that the cwd it the root of a git repository.
  static Workspace? fromPkgs() {
    final gitDir = Directory('.git');
    if (!gitDir.existsSync()) return null;

    var workspaceYaml = y.loadYaml('''
packages:
  - pkgs/*
''') as y.YamlMap;

    return Workspace._from(root: Directory.current, yaml: workspaceYaml);
  }

  final y.YamlMap yaml;
  final Directory root;

  final List<String> parseErrors = [];
  final List<Package> packages = [];

  Workspace._from({
    required this.root,
    required this.yaml,
  }) {
    // todo: parse 'packages'
    if (yaml.containsKey('packages')) {
      final patterns = (yaml['packages'] as List).cast<String>();

      for (var pattern in patterns) {
        final glob = Glob(pattern);

        for (var match in glob.listSync().whereType<Directory>()) {
          // a match is a dir; we then look for a pubspec.yaml file
          final pubspec = File(p.join(match.path, 'pubspec.yaml'));

          if (pubspec.existsSync()) {
            packages.add(Package(Directory(p.normalize(match.path))));
          }
        }
      }

      packages.sort((a, b) => a.path.compareTo(b.path));
    } else {
      parseErrors.add("No 'packages' entry found.");
    }
  }

  @override
  String toString() => '[Workspace ${root.path}]';
}
