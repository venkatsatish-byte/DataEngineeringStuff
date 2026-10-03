import GlucoseCore
import SwiftUI

/// Renders the doctor report to a US Letter PDF with SwiftUI and Swift Charts.
@MainActor
enum ReportRenderer {
    static let pageSize = CGSize(width: 612, height: 792)

    static func makePDF(report: DoctorReport) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glucose report \(formatter.string(from: report.generatedAt)).pdf")

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pages: [AnyView] = [AnyView(ReportSummaryPage(report: report))]
        let logbookPages = stride(from: 0, to: report.logbook.count, by: ReportLogbookPage.rowsPerPage).map {
            Array(report.logbook[$0..<min($0 + ReportLogbookPage.rowsPerPage, report.logbook.count)])
        }
        for (index, rows) in logbookPages.enumerated() {
            pages.append(AnyView(ReportLogbookPage(report: report, rows: rows, page: index + 1, of: logbookPages.count)))
        }

        for page in pages {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height))
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}
