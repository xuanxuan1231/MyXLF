import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 密码存储接口（便于测试替换，也可接入其他安全存储实现）。
abstract class PasswordVault {
  Future<String?> read(String username);

  Future<void> write(String username, String password);

  Future<void> delete(String username);
}

/// 基于系统安全存储的密码实现。
///
/// Android 使用 Keystore，iOS/macOS 使用 Keychain，
/// Linux 使用 libsecret（GNOME Keyring / KWallet）。
class SystemPasswordVault implements PasswordVault {
  const SystemPasswordVault();

  static const String _keyPrefix = 'xlf.account.password.v1.';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 用户名可能包含中文，使用 base64url 规避特殊字符。
  String _key(String username) =>
      '$_keyPrefix${base64Url.encode(utf8.encode(username))}';

  @override
  Future<String?> read(String username) => _storage.read(key: _key(username));

  @override
  Future<void> write(String username, String password) =>
      _storage.write(key: _key(username), value: password);

  @override
  Future<void> delete(String username) => _storage.delete(key: _key(username));
}

/// 多账户本地存储。
///
/// 账号资料（用户名、学校、班级等）保存在 `shared_preferences`；
/// 密码单独保存在系统安全存储（Android Keystore / iOS Keychain /
/// Linux libsecret），不会写入 `shared_preferences`。
///
/// 旧版本曾把密码明文写入 `shared_preferences`。首次读取时会自动迁移：
/// 成功写入安全存储后立即重写账号 JSON 删除密码字段；若安全存储不可用，
/// 则保留原有数据并通过 [consumeLastError] 向界面报告，
/// 不会把新密码降级为明文保存。
class AccountStore {
  AccountStore._(this._vault);

  static final AccountStore instance = AccountStore._(
    const SystemPasswordVault(),
  );

  /// 创建使用指定密码存储的实例（仅用于测试）。
  @visibleForTesting
  factory AccountStore.withVault(PasswordVault vault) => AccountStore._(vault);

  static const String _accountsKey = 'xlf_accounts';

  final PasswordVault _vault;

  List<Account> _accounts = [];
  bool _loaded = false;
  Future<List<Account>>? _loading;

  /// 尚未成功迁移到安全存储的旧版明文密码（用户名 → 密码）。
  final Map<String, String> _legacyPasswords = {};

  String? _lastError;

  /// 取出并清除最近一次安全存储错误；无错误时返回 null。
  String? consumeLastError() {
    final error = _lastError;
    _lastError = null;
    return error;
  }

  /// 读取全部账号。
  ///
  /// 同一个实例的并发调用会共享同一次读取；出错不会抛出，
  /// 而是记录到 [consumeLastError]。
  Future<List<Account>> load() {
    if (_loaded) return Future.value(List.unmodifiable(_accounts));
    return _loading ??= _doLoad().whenComplete(() => _loading = null);
  }

  Future<List<Account>> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    _accounts = [];
    _legacyPasswords.clear();
    _lastError = null;

    if (raw == null || raw.isEmpty) {
      _loaded = true;
      return List.unmodifiable(_accounts);
    }

    final List<Map<String, dynamic>> rawList;
    try {
      rawList = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      _loaded = true;
      return List.unmodifiable(_accounts);
    }

    final resolvedPasswords = <String, String>{};
    var migrated = false;

    for (final json in rawList) {
      final account = Account.fromJson(json);
      // fromJson 会读取旧版 JSON 中的 password 字段。
      final legacy = account.password;
      if (legacy.isNotEmpty) {
        _legacyPasswords[account.username] = legacy;
      }

      String? stored;
      try {
        stored = await _vault.read(account.username);
      } catch (e) {
        _recordStorageError(e, '读取');
      }

      if (stored != null && stored.isNotEmpty) {
        resolvedPasswords[account.username] = stored;
        if (legacy.isNotEmpty) {
          // 安全存储里已有密码，旧版明文可以安全删除。
          _legacyPasswords.remove(account.username);
          migrated = true;
        }
      } else if (legacy.isNotEmpty) {
        // 旧版明文密码迁移到安全存储。
        try {
          await _vault.write(account.username, legacy);
          resolvedPasswords[account.username] = legacy;
          _legacyPasswords.remove(account.username);
          migrated = true;
        } catch (e) {
          _recordStorageError(e, '保存');
          // 安全存储不可用时密码只保留在内存中；原明文数据暂不删除，
          // 避免用户密码丢失，但绝不会把新密码写入明文。
          resolvedPasswords[account.username] = legacy;
        }
      }

      _accounts.add(
        account.copyWith(password: resolvedPasswords[account.username] ?? ''),
      );
    }

    if (migrated) await _save();
    _loaded = true;
    return List.unmodifiable(_accounts);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _accounts.map((account) {
      final json = account.toJson();
      final legacy = _legacyPasswords[account.username];
      // 仅当旧版密码尚未成功迁移时才保留原字段，避免数据丢失。
      // 新密码永远只写入安全存储。
      if (legacy != null && legacy.isNotEmpty) {
        json['password'] = legacy;
      }
      return json;
    }).toList();
    await prefs.setString(_accountsKey, jsonEncode(list));
  }

  /// 新增账号（若用户名已存在则更新信息）。
  /// 第一个账号自动设为默认。返回保存后的账号。
  Future<Account> addOrUpdate(Account account) async {
    await load();

    if (account.password.isNotEmpty) {
      try {
        await _vault.write(account.username, account.password);
        _legacyPasswords.remove(account.username);
      } catch (e) {
        _recordStorageError(e, '保存');
        // 不把新密码写入 shared_preferences；当前会话仍可使用内存中的密码。
      }
    }

    final idx = _accounts.indexWhere((a) => a.username == account.username);
    // 首次添加视为默认账号；更新已有账号时保留其默认标记，
    // 避免重新登录已保存账号后默认账号被意外取消。
    final saved = account.copyWith(
      isDefault: _accounts.isEmpty
          ? true
          : (account.isDefault || (idx >= 0 && _accounts[idx].isDefault)),
    );
    if (idx >= 0) {
      _accounts[idx] = _accounts[idx].copyWith(
        password: saved.password.isEmpty
            ? _accounts[idx].password
            : saved.password,
        schoolName: saved.schoolName,
        className: saved.className,
        userId: saved.userId,
        schoolId: saved.schoolId,
        classId: saved.classId,
        isDefault: saved.isDefault,
        lastLoginAt: saved.lastLoginAt,
      );
    } else {
      _accounts.add(saved);
    }
    await _save();
    return saved;
  }

  /// 删除账号。若删除的是默认账号，则把剩余第一个账号设为默认。
  /// 至少保留一个账号：当只剩一个时抛出 [StateError]。
  Future<void> remove(String username) async {
    await load();
    if (_accounts.length <= 1) {
      throw StateError('至少保留一个账号');
    }
    final removing = _accounts.firstWhere((a) => a.username == username);
    final wasDefault = removing.isDefault;
    _accounts.removeWhere((a) => a.username == username);
    _legacyPasswords.remove(username);
    try {
      await _vault.delete(username);
    } catch (e) {
      _recordStorageError(e, '删除');
    }
    if (wasDefault && _accounts.isNotEmpty) {
      _accounts[0].isDefault = true;
    }
    await _save();
  }

  /// 设置默认账号。
  Future<void> setDefault(String username) async {
    await load();
    for (final a in _accounts) {
      a.isDefault = a.username == username;
    }
    await _save();
  }

  /// 获取默认账号（无默认时返回第一个）。
  Future<Account?> getDefault() async {
    await load();
    if (_accounts.isEmpty) return null;
    return _accounts.firstWhere(
      (a) => a.isDefault,
      orElse: () => _accounts.first,
    );
  }

  /// 更新某账号的最近登录时间。
  Future<void> touch(String username) async {
    await load();
    final idx = _accounts.indexWhere((a) => a.username == username);
    if (idx >= 0) {
      _accounts[idx].lastLoginAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
    }
  }

  void _recordStorageError(Object error, String action) {
    debugPrint('AccountStore: 安全存储$action失败: $error');
    // 保留第一个错误，避免后续重复错误覆盖更有价值的信息。
    if (_lastError != null) return;

    String detail;
    if (error is MissingPluginException) {
      detail = '当前平台未提供安全存储插件';
    } else if (error is PlatformException) {
      final message = error.message?.trim();
      detail = (message == null || message.isEmpty) ? error.code : message;
    } else {
      detail = error.toString();
    }
    if (detail.length > 160) {
      detail = '${detail.substring(0, 160)}…';
    }
    _lastError = '系统安全存储$action失败：$detail';
  }
}
