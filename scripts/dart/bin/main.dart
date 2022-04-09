import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:process_run/shell_run.dart';
import 'package:quill_markdown/quill_markdown.dart';
import 'package:uuid/uuid.dart';

void main(List<String> arguments) async {
  try {
    var shell = Shell(workingDirectory: "./", environment: Platform.environment);

    var repoDir = Platform.environment["GITHUB_WORKSPACE"]!;
    var scriptDir = join(repoDir, "scripts", "dart");
    var coscli = join(repoDir, "coscli");
    var articlesDirPath = join(repoDir, "articles");
    print("start dart scripts");
    print("repo dir: $repoDir");
    print(arguments);
    var cossecretid = Platform.environment["cossecretid"];
    var cossecretkey = Platform.environment["cossecretkey"];
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
            var articleName = article["title"];
            if (article["needUpload"]) {
              var tempFile = File("./temp/${article["title"]}.jsonp");
              tempFile.createSync(recursive: true);
              tempFile.writeAsStringSync(jsonp(article["content"]));
              await shell.run("$coscli cp ${tempFile.path} cos://ybzhome-1256163827/categorys/$categoryName/${article["title"]}.jsonp -e \"cos.ap-guangzhou.myqcloud.com\" -i \"$cossecretid\" -k \"$cossecretkey\" -c $scriptDir/cos.yaml");
              tempFile.deleteSync();
            }
            article.remove("needUpload");
            article.remove("content");

            var articleDataFile = File(join(dirname(article["path"]!), ".$articleName.json"));
            if (articleDataFile.existsSync() == false) articleDataFile.createSync(recursive: true);
            articleDataFile.writeAsStringSync(jsonEncode(article));
            print("更新文章数据文件成功：${articleDataFile.path}");
          }
        }
      }
      if (children != null && children is List) {
        for (var item in children) {
          await initCategory(item);
        }
      }
      var categoryDataFile = File(join(category["path"]!, ".$categoryName.json"));
      if (categoryDataFile.existsSync() == false) categoryDataFile.createSync(recursive: true);
      categoryDataFile.writeAsStringSync(jsonEncode(category));
      print("更新分类数据文件成功：${categoryDataFile.path}");
    }

    for (var category in categorys) {
      await initCategory(category);
    }
    var json = jsonEncode(categorys);
    File articleJsonFile = File(join(repoDir, "article.json"));
    articleJsonFile.writeAsStringSync(json, mode: FileMode.write);

    var tempJsonPFile = File(join(repoDir, "article.jsonp"));
    tempJsonPFile.createSync();
    tempJsonPFile.writeAsStringSync(jsonp(categorys));
    await shell.run("$coscli cp ${tempJsonPFile.path} cos://ybzhome-1256163827/article.jsonp -e \"cos.ap-guangzhou.myqcloud.com\" -i \"$cossecretid\" -k \"$cossecretkey\" -c $scriptDir/cos.yaml");

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
  var categoryDataFile = File(join(path, ".$categoryName.json"));
  Map<String, dynamic> category = {};
  if (categoryDataFile.existsSync()) {
    category = jsonDecode(categoryDataFile.readAsStringSync());
  } else {
    print("($categoryName)新分类！");
    category = {
      "id": Uuid().v4(),
      "create_date": DateTime.now().millisecondsSinceEpoch,
      "create_by": "ybz",
      "title": categoryName,
    };
  }
  category["path"] = path;
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
      article["path"] = item.path;
      print("($categoryName-$articleName)文章属性：");
      print(JsonEncoder.withIndent('  ').convert(article));
      String articleMd5 = md5.convert(articleFile.readAsBytesSync().toList()).toString();
      if (articleMd5 != article["md5"]) {
        print("($categoryName-$articleName)文章有变动");
        article["needUpload"] = true;
        article["md5"] = articleMd5;
        String articleContentJson = "";
        if (fileExtension == ".md") {
          articleContentJson = markdownToQuill(articleFile.readAsStringSync()) ?? "";
        }
        if (fileExtension == ".json") {
          articleContentJson = articleFile.readAsStringSync();
        }
        article["content"] = articleContentJson;
      }
      articles.add(article);
    }
  }
  category["articles"] = articles;
  category['children'] = children;
  print("($categoryName)分类属性：");
  print(JsonEncoder.withIndent('  ').convert(category));
  return category;
}

String jsonp(dynamic obj, {String? jsonpCallbackName}) {
  String p = obj is Map || obj is List ? jsonEncode(obj) : "\"${obj.toString()}\"";
  return "${jsonpCallbackName?.trim() ?? "jsonpcallback"}($p)";
}
