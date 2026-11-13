import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/parsers.dart';

const _typicalHtml = '''
<html>
<body>
<form name="mainform">
  <input type="hidden" name="itemId" id="itemId" value=""/>
</form>
<div>
  <a href="javascript:;" onclick="showItemNoImgsJs('4085865');">10</a>&nbsp;
  <a href="javascript:;" onclick="showItemNoImgsJs('4085868');">18.1</a>&nbsp;
  <a href="javascript:;" onclick="showItemNoImgsJs('4085874');">18.2</a>&nbsp;
</div>
<ul class="slides" id="img_ul">
  <li>
    <div style="text-align: center;height: 20px;"></div>
    <div style="text-align: center;font-size: 16px;">第18.2题&nbsp;&nbsp;优秀答卷&nbsp;&nbsp; 34分&nbsp;&nbsp;<a href="/download">下载图片</a></div>
    <div class="img"><img id="img_0" src="https://example.com/a.jpg"/></div>
  </li>
  <li>
    <div style="text-align: center;height: 20px;"></div>
    <div style="text-align: center;font-size: 16px;">第18.2题&nbsp;&nbsp;典型错误&nbsp;&nbsp; 30分&nbsp;&nbsp;<a href="/download">下载图片</a></div>
    <div class="img"><img id="img_1" src="/tqweb/images/b.jpg"/></div>
  </li>
</ul>
</body>
</html>
''';

void main() {
  test('解析典型答卷的题号导航与图片分组', () {
    final sheet = Parsers.parseTypicalAnswerSheet(_typicalHtml);

    expect(sheet.items.map((e) => e.number), ['10', '18.1', '18.2']);
    expect(sheet.items.map((e) => e.itemId), ['4085865', '4085868', '4085874']);
    expect(sheet.items[0].images, isEmpty);
    expect(sheet.items[1].images, isEmpty);

    final answer = sheet.itemForNumber('18.2');
    expect(answer, isNotNull);
    expect(answer!.images.length, 2);
    expect(answer.images.first.url, 'https://example.com/a.jpg');
    expect(answer.images.first.number, '18.2');
    expect(answer.images.first.label, '优秀答卷 34分');
    expect(answer.images.last.url, contains('/tqweb/images/b.jpg'));
    expect(answer.images.last.label, '典型错误 30分');
  });

  test('题号匹配忽略全角括号和空白', () {
    final sheet = Parsers.parseTypicalAnswerSheet(
      _typicalHtml.replaceAll('18.1', '18（1）'),
    );
    expect(sheet.itemForNumber('18(1)'), isNotNull);
    expect(sheet.itemForNumber(' 18（1） '), isNotNull);
    expect(sheet.itemForNumber('18.2'), isNotNull);
  });

  test('无图片的典型答卷仍保留题号导航', () {
    final sheet = Parsers.parseTypicalAnswerSheet('''
      <a href="javascript:;" onclick="showItemNoImgsJs('1');">1</a>
      <a href="javascript:;" onclick="showItemNoImgsJs('2');">2</a>
      <ul id="img_ul"></ul>
    ''');
    expect(sheet.items.length, 2);
    expect(sheet.hasImages, isFalse);
  });

  test('答案表单可附带小题 ID', () {
    final form = AnswerSheetForm(
      paperId: 'p',
      classNo: 'c',
      studentName: 's',
      schoolName: 'school',
      testId: 't',
    );
    expect(form.toForm()['itemId'], isNull);
    expect(form.toForm(itemId: '4085865')['itemId'], '4085865');
  });
}
