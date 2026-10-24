import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 多账户本地存储。
///
/// 说明：为简化实现，密码以明文存储于本地偏好中。
/// 如需更高安全性，可替换为 flutter_secure_storage 并做加密。
class AccountStore {
  AccountStore._();

  static final AccountStore instance = AccountStore._();

  static const String _key = 'xlf_accounts';

  List<Account> _accounts = [];
  bool _loaded = false;

  /// 读取全部账号。
  Future<List<Account>> load() async {
    if (_loaded) return List.unmodifiable(_accounts);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _accounts = [];
    } else {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => Account.fromJson(e as Map<String, dynamic>))
            .toList();
        _accounts = list;
      } catch (_) {
        _accounts = [];
      }
    }
    _loaded = true;
    return List.unmodifiable(_accounts);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_accounts.map((e) => e.toJson()).toList()));
  }

  /// 新增账号（若用户名已存在则更新信息）。
  /// 第一个账号自动设为默认。返回保存后的账号。
  Future<Account> addOrUpdate(Account account) async {
    await load();
    // 首次添加视为默认账号。
    final saved = account.copyWith(isDefault: _accounts.isEmpty ? true : account.isDefault);
    final idx = _accounts.indexWhere((a) => a.username == saved.username);
    if (idx >= 0) {
      _accounts[idx] = _accounts[idx].copyWith(
        password: saved.password,
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
    return _accounts.firstWhere((a) => a.isDefault, orElse: () => _accounts.first);
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
}
