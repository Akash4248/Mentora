import 'package:sqflite/sqflite.dart' as sqflite;
import '../../../config/app_environment.dart';
import '../../../features/course/data/local/app_database.dart';

/// DEPRECATED single-DB facade.
///
/// There is exactly one SQLite file now ([AppDatabase], `offline_tutor_stage1.db`).
/// This class is kept only so the ~30 legacy `EducationalDatabase.database`
/// call sites keep compiling; it delegates 1:1 to [AppDatabase].
/// Do not add tables here — add migrations to `app_database.dart`.
@Deprecated('Single DB now: use AppDatabase directly.')
class EducationalDatabase {
  static final EducationalDatabase _instance = EducationalDatabase._internal();

  factory EducationalDatabase() {
    return _instance;
  }

  EducationalDatabase._internal();

  /// Single database for the whole app.
  static Future<sqflite.Database> get database async {
    return AppDatabase.instance.database;
  }

  /// FTS availability mirrors the single DB (v2 FTS artifacts).
  static bool get isFullTextSearchAvailable => true;

  /// No-op close (owned by [AppDatabase]).
  static Future<void> close() async {
    AppEnvironment.log('SYNC', 'Educational database delegated close');
  }

  /// Delete the single app database (use with caution).
  static Future<void> deleteDatabase() async {
    await AppDatabase.instance.delete();
  }
}
