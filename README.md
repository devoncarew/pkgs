[![package:pkgs](https://github.com/devoncarew/pkgs/actions/workflows/build.yaml/badge.svg)](https://github.com/devoncarew/pkgs/actions/workflows/build.yaml)

An experimental tool to manage mono-repos.

## Usage

```
Manage Dart packages in a mono-repo.

This command requires a workspace.yaml file to exist. An example of a simple
configuration:

    # Sample workspace.yaml configuration file.
    packages:
      - pkgs/*

Usage: pkgs <command> [arguments]

Global options:
-h, --help    Print this usage information.

Available commands:
  generate   Generate various artifacts and package meta-data.
  list       List the packages that make up this workspace.
  pub-get    Run pub get and pub upgrade for the workspaces packages.

Run "pkgs help <command>" for more information about a command.
```
