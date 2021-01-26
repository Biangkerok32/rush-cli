import 'dart:io' show Directory, File, exit;

import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:dart_casing/dart_casing.dart';
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/new_command/questions.dart';
import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/mixins/download_mixin.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/readme.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/templates/rush_yaml_template.dart';
import 'package:rush_cli/templates/extension_template.dart';

class NewCommand with DownloadMixin, AppDataMixin, CopyMixin {
  final String _cd;

  NewCommand(this._cd) {
    run();
  }

  /// Creates a new extension project in the current directory.
  Future<void> run() async {
    await _checkPackage();

    final answers = RushPrompt(questions: Questions.questions).askAll();
    final extName = answers[0][1].toString().trim();
    final orgName = answers[1][1].toString().trim();
    final authorName = answers[2][1].toString().trim();
    final versionName = answers[3][1].toString().trim();

    final isOrgAndNameSame =
        orgName.split('.').last == Casing.camelCase(extName);

    final extPath = path.joinAll([
      _cd,
      Casing.camelCase(extName),
      'src',
      ...orgName.split('.'),
      if (!isOrgAndNameSame) Casing.camelCase(extName),
    ]);

    // Creates the required files for the extension.
    try {
      File(path.join(extPath, '${Casing.pascalCase(extName)}.java'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getExtensionTemp(
            Casing.pascalCase(extName),
            orgName + '.' + Casing.camelCase(extName),
          ),
        );

      File(path.join(_cd, Casing.camelCase(extName), 'rush.yml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getRushYaml(extName, versionName, authorName),
        );

      File(path.join(_cd, Casing.camelCase(extName), '.gitignore'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getDotGitignore(),
        );

      File(path.join(_cd, Casing.camelCase(extName), 'README.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getReadme(extName),
        );

      File(path.join(
          _cd, Casing.camelCase(extName), 'src', 'AndroidManifest.xml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getManifestXml(orgName),
        );
    } catch (e) {
      ThrowError(message: 'ERR : ' + e.toString());
    }

    try {
      Directory(path.join(
              _cd, Casing.camelCase(extName), 'dependencies', 'dev-deps'))
          .createSync(recursive: true);

      Directory(path.join(_cd, Casing.camelCase(extName), 'assets'))
          .createSync(recursive: true);
    } catch (e) {
      ThrowError(message: 'ERR: ' + e.toString());
    }

    // Dir where all the dev dependencies live in cache form.
    final devDepsDirPath = path.join(AppDataMixin.dataStorageDir(), 'dev-deps');

    // Copy the dev-deps from the cache.
    copyDir(
        Directory(devDepsDirPath),
        Directory(path.join(
            _cd, Casing.camelCase(extName), 'dependencies', 'dev-deps')));

    exit(0);
  }

  Future<void> _checkPackage() async {
    // Dir where Rush stores all the data.
    final dataDir = Directory(AppDataMixin.dataStorageDir());

    if (!dataDir.existsSync() || dataDir.listSync().isEmpty) {
      Console().writeLine('''
Rush needs to download some Java dependencies and other packages (total download size: 43.3 MB) to compile your extension(s).
This is a one-time process, and Rush won\'t ask you to download these files again (unless there is a necessary update in one or more of them).''');

      final continueProcess =
          BoolQuestion(id: 'continue', question: 'Do you want to continue?')
              .ask()[1];

      if (!continueProcess) {
        exit(0);
      }

      try {
        dataDir.createSync(recursive: true);
      } catch (e) {
        ThrowError(message: e);
      }

      await _downloadPackage();
      await _extractPackage();
    }
  }

  /// Downloads the required packages.
  void _downloadPackage() async {
    // HACK#1: Writing new line in the console because the progress bar shifts
    // up when intialized. Can be fixed, but you know, I'm too lazy.
    Console().writeLine();
    final progress = ProgressBar('Downloading packages...');

    const url =
        'https://firebasestorage.googleapis.com/v0/b/rush-cli.appspot.com/o/packages.zip?alt=media&token=472bae35-ac1a-422c-affe-1c81ba223931';

    await download(progress, url, AppDataMixin.dataStorageDir());
  }

  /// Extracts the package
  void _extractPackage() {
    final packageZip =
        File(path.join(AppDataMixin.dataStorageDir(), 'packages.zip'));

    if (!packageZip.existsSync()) {
      ThrowError(message: 'Unable to extract packages. Aborting...');
    }

    final bytes = packageZip.readAsBytesSync();
    final zip = ZipDecoder().decodeBytes(bytes).files;
    final total = zip.length;

    // See HACK#1
    Console().writeLine();
    final progress = ProgressBar('Extracting packages...');
    progress.totalProgress = total;

    for (var i = 0; i < zip.length; i++) {
      progress.update(i + 1);
      if (zip[i].isFile) {
        final data = zip[i].content;
        try {
          File(path.join(AppDataMixin.dataStorageDir(), zip[i].name))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } catch (e) {
          ThrowError(message: e);
        }
      }
    }

    packageZip.deleteSync();
  }
}
