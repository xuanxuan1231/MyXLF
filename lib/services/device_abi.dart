/// 当前进程运行时的 Android ABI。
///
/// 通过条件导出隔离 `dart:ffi`，保证 Web 构建不会引用移动端实现。
library;

export 'device_abi_stub.dart' if (dart.library.ffi) 'device_abi_io.dart';
