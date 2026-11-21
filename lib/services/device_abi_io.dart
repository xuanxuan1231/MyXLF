import 'dart:ffi';

/// ABI 名称与 Flutter 拆分 APK 的目录名 / 发布文件名保持一致。
const Map<String, String> _abiNames = {
  'android_arm64': 'arm64-v8a',
  'android_arm': 'armeabi-v7a',
  'android_x64': 'x86_64',
  'android_ia32': 'x86',
};

/// 返回当前进程 ABI 对应的 Android 拆分 APK 名称（如 `arm64-v8a`）。
///
/// 用当前进程的 ABI 而不是设备的首选 ABI：若应用以 32 位模式运行在 64 位
/// 设备上，应继续下载 32 位安装包，否则安装时会被系统拒绝。
///
/// 非 Android 平台或未知 ABI 返回 null，调用方应回退到清单里的通用安装包。
String? currentAndroidAbi() {
  try {
    return _abiNames[Abi.current().toString()];
  } catch (_) {
    return null;
  }
}
