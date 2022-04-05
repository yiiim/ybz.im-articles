import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:process_run/shell_run.dart';
import 'package:uuid/uuid.dart';

void main(List<String> arguments) async {
  try {
    var shell = Shell(workingDirectory: "./", environment: Platform.environment);

    var repoDir = Platform.environment["GITHUB_WORKSPACE"]!;
    var scriptDir = join(repoDir, "scripts", "dart");
    var coscli = join(repoDir, "coscli");
    var articlesDirPath = join(repoDir, "articles");
    print(JsonEncoder.withIndent('  ').convert(Platform.environment));
    print("start dart scripts");
    print("repo dir: $repoDir");
    print(arguments);
    var cossecretid = Platform.environment["cossecretid"];
    var cossecretkey = Platform.environment["cossecretkey"];
    print(Platform.environment["cossecretid"]);
    print(Platform.environment["cossecretkey"]);
    var categorys = <Map>[];
    var articlesDir = Directory(join(Directory.current.path, articlesDirPath));
    for (var item in articlesDir.listSync()) {
      if (FileSystemEntity.isDirectorySync(item.path)) {
        categorys.add(outPutCategory(item.path));
      }
    }
    Future initCategory(Map category) async {
      var categoryName = category["name"];
      var articles = category["articles"];
      var children = category["children"];
      if (articles != null && articles is List) {
        for (var article in articles) {
          if (article is Map) {
            if (article["needUpload"]) {
              var tempFile = File("./temp/${article["title"]}.json");
              tempFile.createSync(recursive: true);
              tempFile.writeAsStringSync(article["content"]);
              await shell.run("$coscli cp ${tempFile.path} cos://ybzhome-1256163827/categorys/$categoryName/ -e \"cos.ap-guangzhou.myqcloud.com\" -i \"$cossecretid\" -k \"$cossecretkey\" -c $scriptDir/cos.yaml");
              tempFile.deleteSync();
            }
            article.remove("needUpload");
            article.remove("content");
          }
        }
      }
      if (children != null && children is List) {
        for (var item in children) {
          await initCategory(item);
        }
      }
    }

    for (var category in categorys) {
      await initCategory(category);
    }
    var json = jsonEncode(categorys);
    File articleJsonFile = File(join(repoDir, "article.json"));
    articleJsonFile.writeAsStringSync(json, mode: FileMode.write);

    await shell.run("$coscli cp ${articleJsonFile.path} cos://ybzhome-1256163827/ -e \"cos.ap-guangzhou.myqcloud.com\" -i \"\$cossecretid\" -k \"\$cossecretkey\" -c $scriptDir/cos.yaml");

    print("exec done");
    exit(0);
  } catch (e) {
    print("$e");
    exit(1);
  }
}

Map outPutCategory(String path) {
  var categoryName = basename(path);
  print("正在检查分类：$categoryName");
  Map<String, dynamic> category = {"name": categoryName};
  var children = [];
  var articles = [];
  for (var item in Directory(path).listSync()) {
    if (basename(item.path).startsWith(".")) continue;
    if (FileSystemEntity.isDirectorySync(item.path)) {
      print("（$categoryName）发现子分类");
      children.add(outPutCategory(item.path));
    }
    if (FileSystemEntity.isFileSync(item.path)) {
      var articleName = basenameWithoutExtension(item.path);
      print("（$categoryName）发现文章:$articleName");
      File articleFile = File(item.path);
      var fileExtension = extension(item.path);
      var dataFile = File(join(dirname(item.path), ".$articleName.json"));
      var article = {};
      if (dataFile.existsSync()) {
        article = jsonDecode(dataFile.readAsStringSync());
      } else {
        print("($categoryName-$articleName)新文章！");
        article = {
          "id": Uuid().v4(),
          "create_date": DateTime.now().millisecondsSinceEpoch,
          "create_by": "ybz",
          "title": articleName,
        };
      }
      print("($categoryName-$articleName)文章属性：");
      print(JsonEncoder.withIndent('  ').convert(article));
      String articleMd5 = md5.convert(articleFile.readAsBytesSync().toList()).toString();
      if (articleMd5 != article["md5"]) {
        print("($categoryName-$articleName)文章有变动");
        article["needUpload"] = true;
        article["md5"] = articleMd5;
        String articleContentJson = articleFile.readAsStringSync();
        if (fileExtension == ".md") {}
        if (fileExtension == ".json") {}
        article["content"] = articleContentJson;
      }
      articles.add(article);
    }
  }
  category["articles"] = articles;
  category['children'] = children;
  return category;
}

String mdToQuillJson(String mdFilePath) {
  var mdFile = File(mdFilePath);
  return mdFile.readAsStringSync();
}
