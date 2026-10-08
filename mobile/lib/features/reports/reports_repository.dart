import 'dart:typed_data';

import '../../core/api/api_client.dart';
import 'reports_models.dart';

/// Reports, the dashboard and the activity history over the API. Everything here only reads:
/// nothing changes stock or money, so plain requests are enough.
class ReportsRepository {
  ReportsRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';

  Future<ReportSummary> summary(ReportQuery q) async => ReportSummary.fromJson(
    (await api.get('$_base/reports/summary/', query: q.toQuery())).map,
  );

  Future<SalesReport> sales(ReportQuery q) async => SalesReport.fromJson(
    (await api.get('$_base/reports/sales/', query: q.toQuery())).map,
  );

  Future<StockReport> stock(ReportQuery q) async => StockReport.fromJson(
    (await api.get('$_base/reports/stock/', query: q.toQuery())).map,
  );

  Future<PurchasingReport> purchasing(ReportQuery q) async =>
      PurchasingReport.fromJson(
        (await api.get('$_base/reports/purchasing/', query: q.toQuery())).map,
      );

  Future<ReturnsReport> returns(ReportQuery q) async => ReturnsReport.fromJson(
    (await api.get('$_base/reports/returns/', query: q.toQuery())).map,
  );

  Future<ExpensesReport> expenses(ReportQuery q) async =>
      ExpensesReport.fromJson(
        (await api.get('$_base/reports/expenses/', query: q.toQuery())).map,
      );

  /// The report as a spreadsheet file ("sales", "stock", "purchasing", "returns", "expenses").
  Future<Uint8List> export(String slug, ReportQuery q) async {
    final response = await api.download(
      '$_base/reports/$slug/export/',
      query: q.toQuery(),
      accept: 'text/csv, application/json',
    );
    return response.bytes ?? Uint8List(0);
  }

  Future<Dashboard> dashboard() async =>
      Dashboard.fromJson((await api.get('$_base/dashboard/')).map);

  Future<AuditPage> audit({
    ReportQuery? period,
    String? action,
    String query = '',
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/audit/',
      query: {
        if (period != null) 'date_from': period.from,
        if (period != null) 'date_to': period.to,
        if (action != null && action.isNotEmpty) 'action': action,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return AuditPage([
      for (final r in map['results'] as List)
        AuditEntry.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<List<String>> auditActions() async {
    final map = (await api.get('$_base/audit/actions/')).map;
    return [for (final a in (map['actions'] as List?) ?? const []) a as String];
  }
}
