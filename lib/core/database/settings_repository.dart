/// Key/value app settings persisted in SQLite (spec §13, §16).
library;

import 'app_database.dart';

class SettingsRepository {
  const SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) => _db.setting(key);

  Future<void> set(String key, String value) => _db.setSetting(key, value);
}
