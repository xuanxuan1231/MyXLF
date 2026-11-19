import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter/widgets.dart';

/// 应用级本地化代理。
///
/// 本项目整体使用 `package:material_ui/material_ui.dart`，而部分第三方插件
/// （例如 PostHog 的问卷弹层）仍用 `package:flutter/material.dart` 构建界面。
/// 两者是**两套独立的类型**，`MaterialLocalizations` 并不是同一个类：
///
/// - `material_ui` 的 `MaterialApp` 只会注册自己的
///   `MaterialLocalizations`；
/// - 插件里的 `showModalBottomSheet` / `MaterialLocalizations.of()` 查找的是
///   `flutter/material.dart` 的 `MaterialLocalizations`。
///
/// 只注册一套时，插件拿到的结果是 `null`：debug 构建触发
/// “No MaterialLocalizations found” 断言，release 构建则抛出空值异常。
/// PostHog 的 `SurveyService` 会吞掉这个异常，表现为**问卷永远不显示、也不
/// 上报 `survey shown`**，且没有任何日志。
///
/// 两个代理的 `type` 不同，`Localizations` 会分别缓存，互不覆盖。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  flutter_material.DefaultMaterialLocalizations.delegate,
];
