import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/assessment/models/experiment_lab_report.dart';
import 'package:mentora/features/experiment/assessment/reports/report_exporter.dart';

void main() {
  test('ReportExporter creates JSON and PDF bytes', () {
    final report = ExperimentLabReport(
      id: 'report_1',
      title: 'Report',
      generatedAt: DateTime(2026, 6, 11),
      conclusion: 'Conclusion',
    );
    final exporter = ReportExporter();

    final json = exporter.exportJson(report);
    final pdf = exporter.exportPdf(report);

    expect(json, contains('"title": "Report"'));
    expect(pdf.length, greaterThan(100));
  });
}
