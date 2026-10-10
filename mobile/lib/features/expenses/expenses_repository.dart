import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import 'expenses_models.dart';

/// Expense categories, expenses, their summary and receipt photos over the API. Nothing here
/// moves stock, so plain requests are enough (no operation records).
class ExpensesRepository {
  ExpensesRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';

  Future<List<ExpenseCategory>> categories() async {
    final map = (await api.get(
      '$_base/expense-categories/',
      query: {'limit': '200'},
    )).map;
    return [
      for (final r in map['results'] as List)
        ExpenseCategory.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<ExpenseCategory> createCategory(String name) async =>
      ExpenseCategory.fromJson(
        (await api.post(
          '$_base/expense-categories/',
          body: {'name': name},
        )).map,
      );

  Future<ExpensePage> expenses({
    ExpenseFilter filter = const ExpenseFilter(),
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/expenses/',
      query: {...filter.toQuery(), 'limit': '$limit', 'offset': '$offset'},
    )).map;
    return ExpensePage([
      for (final r in map['results'] as List)
        Expense.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<ExpenseSummary> summary(ExpenseFilter filter) async =>
      ExpenseSummary.fromJson(
        (await api.get(
          '$_base/expenses/summary/',
          query: filter.toQuery(),
        )).map,
      );

  Future<Expense> expense(String id) async =>
      Expense.fromJson((await api.get('$_base/expenses/$id/')).map);

  Map<String, dynamic> _body({
    required String categoryId,
    required String locationId,
    required int amountMinor,
    required String spentOn,
    required String description,
    required String? attachmentId,
  }) => {
    'category': categoryId,
    'location': locationId,
    'amount': toServerDecimal(amountMinor, 2),
    'spent_on': spentOn,
    'description': description,
    'attachment': attachmentId,
  };

  Future<Expense> createExpense({
    required String categoryId,
    required String locationId,
    required int amountMinor,
    required String spentOn,
    required String description,
    String? attachmentId,
  }) async => Expense.fromJson(
    (await api.post(
      '$_base/expenses/',
      body: _body(
        categoryId: categoryId,
        locationId: locationId,
        amountMinor: amountMinor,
        spentOn: spentOn,
        description: description,
        attachmentId: attachmentId,
      ),
    )).map,
  );

  Future<Expense> updateExpense(
    String id, {
    required String categoryId,
    required String locationId,
    required int amountMinor,
    required String spentOn,
    required String description,
    String? attachmentId,
  }) async => Expense.fromJson(
    (await api.patch(
      '$_base/expenses/$id/',
      body: _body(
        categoryId: categoryId,
        locationId: locationId,
        amountMinor: amountMinor,
        spentOn: spentOn,
        description: description,
        attachmentId: attachmentId,
      ),
    )).map,
  );

  Future<Expense> voidExpense(String id, String reason) async =>
      Expense.fromJson(
        (await api.post(
          '$_base/expenses/$id/void/',
          body: {'reason': reason},
        )).map,
      );

  /// Stores a receipt photo on the server and returns its reference.
  Future<AttachmentRef> upload(PickedFile file) async => AttachmentRef.fromJson(
    (await api.upload(
      '$_base/attachments/',
      ApiUpload(field: 'file', filename: file.name, bytes: file.bytes),
    )).map,
  );

  Future<Uint8List> attachmentBytes(String id) async {
    final response = await api.download(
      '$_base/attachments/$id/',
      accept: 'image/*, application/pdf, application/json',
    );
    return response.bytes ?? Uint8List(0);
  }
}
