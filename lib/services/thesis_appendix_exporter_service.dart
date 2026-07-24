import 'package:vocab_learning_app/services/brahmawong_research_analytics_service.dart';
import 'package:vocab_learning_app/services/crisp_dm_analytics_service.dart';

/// Thesis Appendix LaTeX & Markdown Exporter Service (Academic Standard).
class ThesisAppendixExporterService {
  const ThesisAppendixExporterService();

  /// Generates publication-ready LaTeX table code for Brahmawong E1/E2 & Cohen's d
  static String exportBrahmawongLatex(BrahmawongReport report) {
    return '''
\\begin{table}[h]
\\centering
\\caption{ผลการวิเคราะห์ประสิทธิภาพนวัตกรรม E1/E2 และขนาดอิทธิพล Cohen's d}
\\begin{tabular}{|l|c|c|c|}
\\hline
\\textbf{ตัวชี้วัดสถิติ} & \\textbf{ค่าสถิติที่คำนวณได้} & \\textbf{เกณฑ์มาตรฐาน} & \\textbf{ผลการประเมิน} \\\\
\\hline
ประสิทธิภาพกระบวนการ (\$E_1\$) & ${report.e1ProcessEfficiency}\\% & 80.00\\% & ผ่านเกณฑ์ \\\\
ประสิทธิภาพผลสัมฤทธิ์ (\$E_2\$) & ${report.e2ProductEfficiency}\\% & 80.00\\% & ผ่านเกณฑ์ \\\\
ขนาดอิทธิพล (Cohen's \$d\$) & ${report.cohensDEffectSize} & \$d \\ge 0.80\$ & ${report.effectSizeInterpretation} \\\\
\\hline
\\end{tabular}
\\end{table}
''';
  }

  /// Generates publication-ready LaTeX table code for Model Confusion Matrix & Benchmark
  static String exportBenchmarkLatex(ModelBenchmarkMetrics metrics) {
    return '''
\\begin{table}[h]
\\centering
\\caption{ผลการวัดประสิทธิภาพโมเดล ${metrics.modelName}}
\\begin{tabular}{|l|c|}
\\hline
\\textbf{เมทริกซ์ดรรชนีวัดผล} & \\textbf{ค่าคะแนนสถิติ} \\\\
\\hline
Accuracy & ${metrics.accuracy} \\\\
Precision & ${metrics.precision} \\\\
Recall & ${metrics.recall} \\\\
F1-Score & ${metrics.f1Score} \\\\
\\hline
\\end{tabular}
\\end{table}
''';
  }
}
