import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:drift/drift.dart';

/// Формирует составное условие буквального поиска названия намерения.
final class LocalIntentionTitleSearch {
  factory LocalIntentionTitleSearch(IntentionTitleFilter filter) {
    final searchKey = filter.map((value) => value.toLowerCase());
    final condition = switch (searchKey.runes.length) {
      1 || 2 => _ShortTitleSearchCondition(searchKey),
      _ => _FtsTitleSearchCondition(searchKey),
    };
    return LocalIntentionTitleSearch._(condition);
  }

  const LocalIntentionTitleSearch._(this._condition);

  final _TitleSearchCondition _condition;

  Expression<bool> conditionFor(Intentions intentions) =>
      _condition.conditionFor(intentions);
}

sealed class _TitleSearchCondition {
  const _TitleSearchCondition();

  Expression<bool> conditionFor(Intentions intentions);
}

final class _ShortTitleSearchCondition extends _TitleSearchCondition {
  const _ShortTitleSearchCondition(this._searchKey);

  final String _searchKey;

  @override
  Expression<bool> conditionFor(Intentions intentions) =>
      _InstrTitleSearchExpression(
        intentions.titleSearchKey,
        Variable.withString(_searchKey),
      );
}

final class _FtsTitleSearchCondition extends _TitleSearchCondition {
  const _FtsTitleSearchCondition(this._searchKey);

  final String _searchKey;

  @override
  Expression<bool> conditionFor(Intentions intentions) =>
      _FtsTitleSearchExpression(
        intentions.titleSearchKey,
        _literalFtsPhraseParameter(_searchKey),
      );
}

final class _InstrTitleSearchExpression extends Expression<bool> {
  const _InstrTitleSearchExpression(this._titleSearchKey, this._searchKey);

  final GeneratedColumn<String> _titleSearchKey;
  final Variable<String> _searchKey;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('instr(');
    _titleSearchKey.writeInto(context);
    context.buffer.write(', ');
    _searchKey.writeInto(context);
    context.buffer.write(') > 0');
  }
}

final class _FtsTitleSearchExpression extends Expression<bool> {
  const _FtsTitleSearchExpression(this._titleSearchKey, this._phrase);

  final GeneratedColumn<String> _titleSearchKey;
  final Variable<String> _phrase;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write(
      '${_titleSearchKey.tableName}.rowid IN ('
      'SELECT rowid FROM intention_titles_fts '
      'WHERE intention_titles_fts MATCH ',
    );
    _phrase.writeInto(context);
    context.buffer.write(')');
  }
}

Variable<String> _literalFtsPhraseParameter(String searchKey) {
  final escapedSearchKey = searchKey.replaceAll('"', '""');
  return Variable.withString('"$escapedSearchKey"');
}
