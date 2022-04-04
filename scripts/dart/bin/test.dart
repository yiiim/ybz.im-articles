import 'dart:convert';

void main(List<String> args) {
  print(JsonEncoder.withIndent('  ').convert({"code":"0","text":"hello world"}));
}
