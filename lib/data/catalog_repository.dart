import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/models.dart';
import 'db.dart';

/// A category with its children and banks, for the Banks screen tree.
class CategoryNode {
  CategoryNode(this.category, this.children, this.banks);
  final Category category;
  final List<CategoryNode> children;
  final List<QuestionBank> banks;
  int questionCount = 0;

  Iterable<QuestionBank> get allBanks sync* {
    yield* banks;
    for (final c in children) {
      yield* c.allBanks;
    }
  }
}

/// Subjects, categories and question banks.
class CatalogRepository {
  CatalogRepository(this.db);
  final Database db;

  // ---------------- Categories ----------------

  Future<List<Category>> allCategories({bool includeArchived = true}) async {
    final rows = await db.query('categories',
        where: includeArchived ? null : 'archived = 0',
        orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(Category.fromRow).toList();
  }

  Future<Category?> category(String id) async {
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Category.fromRow(rows.first);
  }

  Future<Category> createCategory({
    required String name,
    String? parentId,
    String? description,
    String? iconKey,
    int? color,
  }) async {
    final c = Category(
      id: newId(),
      parentId: parentId,
      name: name.trim(),
      description: description,
      iconKey: iconKey,
      color: color,
      sortOrder: await _nextSort('categories', 'parent_id', parentId),
    );
    await db.insert('categories', c.toRow());
    return c;
  }

  Future<void> updateCategory(Category c) => db.update(
      'categories', c.copyWith().toRow(),
      where: 'id = ?', whereArgs: [c.id]);

  /// Moves a category under [newParentId] (null = make it a subject).
  /// Refuses to create a cycle.
  Future<void> moveCategory(String id, String? newParentId) async {
    if (newParentId != null) {
      final sub = await descendantCategoryIds(id);
      if (sub.contains(newParentId)) {
        throw ArgumentError('A category cannot be moved inside itself.');
      }
    }
    await db.update('categories',
        {'parent_id': newParentId, 'updated_at': toMs(DateTime.now())},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a category, its sub-categories, banks and questions (cascade).
  /// The UI asks for confirmation first.
  Future<void> deleteCategory(String id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  /// The category and all of its descendants.
  Future<List<String>> descendantCategoryIds(String id) async {
    final rows = await db.rawQuery('''
WITH RECURSIVE sub(id) AS (
  SELECT ?
  UNION ALL
  SELECT c.id FROM categories c JOIN sub ON c.parent_id = sub.id
)
SELECT id FROM sub''', [id]);
    return rows.map((r) => r['id'] as String).toList();
  }

  /// Path from the subject down to this category, e.g. [English, Grammar].
  Future<List<Category>> categoryPath(String id) async {
    final all = {for (final c in await allCategories()) c.id: c};
    final path = <Category>[];
    var cur = all[id];
    var guard = 0;
    while (cur != null && guard++ < 64) {
      path.insert(0, cur);
      cur = cur.parentId == null ? null : all[cur.parentId];
    }
    return path;
  }

  // ---------------- Banks ----------------

  Future<List<QuestionBank>> allBanks({bool includeArchived = true}) async {
    final rows = await db.query('banks',
        where: includeArchived ? null : 'archived = 0',
        orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(QuestionBank.fromRow).toList();
  }

  Future<List<QuestionBank>> banksIn(String categoryId) async {
    final rows = await db.query('banks',
        where: 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(QuestionBank.fromRow).toList();
  }

  Future<QuestionBank?> bank(String id) async {
    final rows = await db.query('banks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : QuestionBank.fromRow(rows.first);
  }

  Future<QuestionBank> createBank({
    required String categoryId,
    required String name,
    String? description,
    String? iconKey,
    int? color,
  }) async {
    final b = QuestionBank(
      id: newId(),
      categoryId: categoryId,
      name: name.trim(),
      description: description,
      iconKey: iconKey,
      color: color,
      sortOrder: await _nextSort('banks', 'category_id', categoryId),
    );
    await db.insert('banks', b.toRow());
    return b;
  }

  /// Finds a bank by name (case-insensitive) inside a category, creating it
  /// when missing. Used by the "Bank" column of the advanced Excel template.
  Future<QuestionBank> findOrCreateBank(
      DatabaseExecutor ex, String categoryId, String name) async {
    final rows = await ex.query('banks',
        where: 'category_id = ? AND name = ? COLLATE NOCASE',
        whereArgs: [categoryId, name.trim()]);
    if (rows.isNotEmpty) return QuestionBank.fromRow(rows.first);
    final b = QuestionBank(id: newId(), categoryId: categoryId, name: name.trim());
    await ex.insert('banks', b.toRow());
    return b;
  }

  Future<void> updateBank(QuestionBank b) => db.update(
      'banks', b.copyWith().toRow(),
      where: 'id = ?', whereArgs: [b.id]);

  Future<void> deleteBank(String id) =>
      db.delete('banks', where: 'id = ?', whereArgs: [id]);

  // ---------------- Tree ----------------

  /// Builds the full subject tree with per-node question counts.
  Future<List<CategoryNode>> tree({bool includeArchived = false}) async {
    final cats = await allCategories(includeArchived: includeArchived);
    final banks = await allBanks(includeArchived: includeArchived);
    final counts = <String, int>{};
    final rows = await db.rawQuery(
        'SELECT bank_id, COUNT(*) AS n FROM questions WHERE archived = 0 GROUP BY bank_id');
    for (final r in rows) {
      counts[r['bank_id'] as String] = intOf(r['n']);
    }
    final byParent = <String?, List<Category>>{};
    for (final c in cats) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final banksByCat = <String, List<QuestionBank>>{};
    for (final b in banks) {
      banksByCat.putIfAbsent(b.categoryId, () => []).add(b);
    }
    final ids = cats.map((c) => c.id).toSet();

    CategoryNode build(Category c, int depth) {
      final kids = depth > 32
          ? <CategoryNode>[]
          : (byParent[c.id] ?? []).map((k) => build(k, depth + 1)).toList();
      final node = CategoryNode(c, kids, banksByCat[c.id] ?? []);
      node.questionCount = node.banks.fold<int>(0, (a, b) => a + (counts[b.id] ?? 0)) +
          kids.fold<int>(0, (a, k) => a + k.questionCount);
      return node;
    }

    // Roots: real subjects, plus orphans whose parent is hidden/archived.
    final roots = cats.where((c) => c.parentId == null || !ids.contains(c.parentId));
    return roots.map((c) => build(c, 0)).toList();
  }

  /// Question counts per bank (non-archived questions).
  Future<Map<String, int>> questionCountsByBank() async {
    final rows = await db.rawQuery(
        'SELECT bank_id, COUNT(*) AS n FROM questions WHERE archived = 0 GROUP BY bank_id');
    return {for (final r in rows) r['bank_id'] as String: intOf(r['n'])};
  }

  /// Resolves a quiz scope to bank ids: explicit banks, plus every bank under
  /// the given categories, minus banks under excluded categories. Archived
  /// banks are left out.
  Future<List<String>> resolveBankIds({
    List<String> bankIds = const [],
    List<String> categoryIds = const [],
    List<String> excludedCategoryIds = const [],
  }) async {
    final result = <String>{...bankIds};
    for (final c in categoryIds) {
      final sub = await descendantCategoryIds(c);
      final rows = await db.rawQuery(
          'SELECT id FROM banks WHERE archived = 0 AND category_id IN ${sqlInList(sub)}');
      result.addAll(rows.map((r) => r['id'] as String));
    }
    if (excludedCategoryIds.isNotEmpty) {
      final excluded = <String>{};
      for (final c in excludedCategoryIds) {
        excluded.addAll(await descendantCategoryIds(c));
      }
      final rows = await db.rawQuery(
          'SELECT id FROM banks WHERE category_id IN ${sqlInList(excluded)}');
      result.removeAll(rows.map((r) => r['id'] as String));
    }
    if (result.isEmpty) return [];
    final active = await db.rawQuery(
        'SELECT id FROM banks WHERE archived = 0 AND id IN ${sqlInList(result)}');
    return active.map((r) => r['id'] as String).toList();
  }

  /// All bank ids in a category subtree (for statistics).
  Future<List<String>> bankIdsUnder(String categoryId) =>
      resolveBankIds(categoryIds: [categoryId]);

  /// The top-level subject of each bank: bank id -> subject category.
  Future<Map<String, Category>> subjectOfBanks() async {
    final cats = {for (final c in await allCategories()) c.id: c};
    final out = <String, Category>{};
    for (final b in await allBanks()) {
      var c = cats[b.categoryId];
      var guard = 0;
      while (c != null && c.parentId != null && cats[c.parentId] != null && guard++ < 64) {
        c = cats[c.parentId];
      }
      if (c != null) out[b.id] = c;
    }
    return out;
  }

  Future<int> _nextSort(String table, String parentCol, String? parent) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM $table WHERE '
      '${parent == null ? '$parentCol IS NULL' : '$parentCol = ?'}',
      parent == null ? [] : [parent],
    );
    return intOf(rows.first['n']);
  }
}
