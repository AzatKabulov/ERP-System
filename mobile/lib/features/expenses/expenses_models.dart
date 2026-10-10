import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';

@immutable
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isActive,
  });
  final String id;
  final String name;
  final bool isActive;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: (json['is_active'] as bool?) ?? true,
      );
}

/// A file stored on the server (a photo of a receipt).
@immutable
class AttachmentRef {
  const AttachmentRef({
    required this.id,
    required this.name,
    required this.contentType,
    required this.size,
  });
  final String id;
  final String name;
  final String contentType;
  final int size;

  bool get isImage => contentType.startsWith('image/');

  factory AttachmentRef.fromJson(Map<String, dynamic> json) => AttachmentRef(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    contentType: (json['content_type'] as String?) ?? '',
    size: (json['size'] as int?) ?? 0,
  );
}

@immutable
class Expense {
  const Expense({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.locationId,
    required this.locationName,
    required this.amountMinor,
    required this.spentOn,
    required this.description,
    required this.createdBy,
    required this.createdAt,
    required this.voided,
    required this.voidReason,
    this.attachment,
  });
  final String id;
  final String categoryId;
  final String categoryName;
  final String locationId;
  final String locationName;
  final int amountMinor;

  /// The day it was spent, "2026-10-07".
  final String spentOn;
  final String description;
  final AttachmentRef? attachment;
  final String createdBy;
  final DateTime createdAt;
  final bool voided;
  final String voidReason;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    categoryId: (json['category'] as Map)['id'] as String,
    categoryName: (json['category'] as Map)['name'] as String,
    locationId: (json['location'] as Map)['id'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    amountMinor: parseServerDecimal(json['amount'] as String, 2) ?? 0,
    spentOn: json['spent_on'] as String,
    description: (json['description'] as String?) ?? '',
    attachment: json['attachment'] == null
        ? null
        : AttachmentRef.fromJson(
            (json['attachment'] as Map).cast<String, dynamic>(),
          ),
    createdBy: ((json['created_by'] as Map?)?['name'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    voided: (json['voided'] as bool?) ?? false,
    voidReason: (json['void_reason'] as String?) ?? '',
  );
}

class ExpensePage {
  const ExpensePage(this.items, this.count);
  final List<Expense> items;
  final int count;
}

@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.totalMinor,
    required this.count,
  });
  final String categoryId;
  final String name;
  final int totalMinor;
  final int count;
}

@immutable
class ExpenseSummary {
  const ExpenseSummary({
    required this.totalMinor,
    required this.count,
    required this.byCategory,
  });
  final int totalMinor;
  final int count;
  final List<CategoryTotal> byCategory;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) => ExpenseSummary(
    totalMinor: parseServerDecimal(json['total'] as String, 2) ?? 0,
    count: (json['count'] as int?) ?? 0,
    byCategory: [
      for (final r in (json['by_category'] as List?) ?? const [])
        CategoryTotal(
          categoryId: ((r as Map)['category'] as Map)['id'] as String,
          name: (r['category'] as Map)['name'] as String,
          totalMinor: parseServerDecimal(r['total'] as String, 2) ?? 0,
          count: (r['count'] as int?) ?? 0,
        ),
    ],
  );
}

/// Which expenses to look at: a period (dates as "2026-10-01") and a category.
@immutable
class ExpenseFilter {
  const ExpenseFilter({this.from, this.to, this.categoryId});
  final String? from;
  final String? to;
  final String? categoryId;

  Map<String, String> toQuery() => {
    'date_from': ?from,
    'date_to': ?to,
    'category': ?categoryId,
  };
}
