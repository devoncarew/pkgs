import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:pkgs/pkgs.dart' as pkgs;

void main(List<String> args) async {
  try {
    io.exitCode = await pkgs.main(args);
  } on UsageException catch (e) {
    io.stderr.writeln('$e');
    io.exitCode = 65;
  }
}
