import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Report Data

struct ReportData {
    let from: Date
    let to: Date
    let summaries: [SummaryRecord]
    let generatedAt: Date = Date()

    // MARK: Derived

    var totalRecordedSeconds: TimeInterval {
        summaries.reduce(0) { $0 + ($1.endTimestamp - $1.startTimestamp) }
    }

    var formattedDuration: String {
        let total = Int(totalRecordedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var medicationDayCounts: (on: Int, off: Int) {
        let cal = Calendar.current
        var onDays = Set<Date>()
        var offDays = Set<Date>()
        for s in summaries {
            let day = cal.startOfDay(for: s.startDate)
            if s.medicationActive { onDays.insert(day) } else { offDays.insert(day) }
        }
        return (onDays.count, offDays.count)
    }

    var topApps: [String] {
        var counts: [String: Int] = [:]
        for s in summaries {
            for app in s.decodedAppNames { counts[app, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    var activityBreakdown: [(type: String, percent: Int)] {
        var counts: [String: Int] = [:]
        var total = 0
        for s in summaries {
            let type = s.activityType ?? "other"
            counts[type, default: 0] += 1
            total += 1
        }
        guard total > 0 else { return [] }
        return counts.sorted { $0.value > $1.value }
            .map { (type: $0.key, percent: Int(Double($0.value) / Double(total) * 100)) }
    }

    /// Summaries grouped and sorted by calendar day.
    var byDay: [(date: Date, summaries: [SummaryRecord])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: summaries) { cal.startOfDay(for: $0.startDate) }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.startTimestamp < $1.startTimestamp }) }
    }

    var formattedDateRange: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if Calendar.current.isDate(from, inSameDayAs: to) {
            return f.string(from: from)
        }
        return "\(f.string(from: from))_\(f.string(from: to))"
    }
}

// MARK: - Report Engine

@MainActor
enum ReportEngine {

    static func export(data: ReportData) {
        let reportView = MedicalReportView(data: data)

        // Render into a headless NSHostingView to get PDF data
        let hosting = NSHostingView(rootView: reportView)
        hosting.frame = NSRect(x: 0, y: 0, width: 680, height: 10)
        hosting.layoutSubtreeIfNeeded()

        let naturalHeight = max(hosting.fittingSize.height, 400)
        hosting.frame = NSRect(x: 0, y: 0, width: 680, height: naturalHeight)
        hosting.layoutSubtreeIfNeeded()

        let pdfData = hosting.dataWithPDF(inside: hosting.bounds)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = "NeuraMind-Report-\(data.formattedDateRange).pdf"
        panel.title = "Save Activity Report"
        panel.prompt = "Save PDF"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pdfData.write(to: url)
    }
}

// MARK: - Report View

struct MedicalReportView: View {
    let data: ReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reportHeader
            dividerLine
            summarySection
            dividerLine
            dailyBreakdown
            reportFooter
        }
        .padding(40)
        .frame(width: 680, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    // MARK: Header

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NeuraMind")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                    Text("Behavioral Activity Report")
                        .font(.system(size: 22, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Generated")
                        .font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                    Text(formatDateTime(data.generatedAt))
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            HStack(spacing: 4) {
                Text("Period:")
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.45))
                Text(formatPeriod(from: data.from, to: data.to))
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.top, 2)
        }
        .padding(.bottom, 16)
    }

    // MARK: Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUMMARY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .tracking(1.2)
                .padding(.top, 14)

            let medDays = data.medicationDayCounts

            LazyVGrid(
                columns: [GridItem(.fixed(220), alignment: .leading),
                          GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 5
            ) {
                summaryRow("Total sessions", value: "\(data.summaries.count)")
                summaryRow("Total recorded time", value: data.formattedDuration)
                summaryRow("Medication days",
                           value: "On: \(medDays.on)  ·  Off: \(medDays.off)")
                summaryRow("Top apps",
                           value: data.topApps.isEmpty ? "—" : data.topApps.joined(separator: ", "))
                if !data.activityBreakdown.isEmpty {
                    summaryRow("Activity breakdown",
                               value: data.activityBreakdown
                                   .map { "\($0.type) \($0.percent)%" }
                                   .joined(separator: "  ·  "))
                }
            }
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func summaryRow(_ label: String, value: String) -> some View {
        Text(label)
            .font(.system(size: 12)).foregroundStyle(Color(white: 0.4))
        Text(value)
            .font(.system(size: 12, weight: .medium))
    }

    // MARK: Daily Breakdown

    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DAILY BREAKDOWN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .tracking(1.2)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ForEach(data.byDay, id: \.date) { dayGroup in
                daySection(date: dayGroup.date, summaries: dayGroup.summaries)
            }
        }
    }

    @ViewBuilder
    private func daySection(date: Date, summaries: [SummaryRecord]) -> some View {
        let hasMedication = summaries.contains { $0.medicationActive }
        let isMedDay = summaries.first?.medicationActive ?? false

        VStack(alignment: .leading, spacing: 0) {
            // Day header
            HStack(spacing: 8) {
                Text(formatDay(date))
                    .font(.system(size: 13, weight: .semibold))
                if hasMedication {
                    Text(isMedDay ? "💊 On medication" : "Off medication")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(isMedDay ? Color.blue.opacity(0.12) : Color(white: 0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(isMedDay ? Color.blue : Color(white: 0.4))
                }
            }
            .padding(.vertical, 8)

            // Sessions
            ForEach(summaries, id: \.startTimestamp) { s in
                sessionRow(s)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func sessionRow(_ s: SummaryRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(formatTimeRange(from: s.startDate, to: s.endDate))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 110, alignment: .leading)

            if let activity = s.activityType {
                Text(activity)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(activityColor(activity).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(activityColor(activity))
                    .frame(width: 82, alignment: .leading)
            } else {
                Color.clear.frame(width: 82)
            }

            Text(s.summary)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.15))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)

        Rectangle()
            .fill(Color(white: 0.93))
            .frame(height: 0.5)
    }

    // MARK: Footer

    private var reportFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            dividerLine
            Text("This report was generated automatically by NeuraMind for clinical review.")
                .font(.system(size: 9)).foregroundStyle(Color(white: 0.5))
            Text("Data reflects passive screen activity captured on this device. All data remains local and is not transmitted externally.")
                .font(.system(size: 9)).foregroundStyle(Color(white: 0.5))
        }
        .padding(.top, 16)
    }

    // MARK: Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(white: 0.8))
            .frame(height: 1)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatPeriod(from: Date, to: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        if Calendar.current.isDate(from, inSameDayAs: to) {
            return f.string(from: from)
        }
        return "\(f.string(from: from)) – \(f.string(from: to))"
    }

    private func formatDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: date)
    }

    private func formatTimeRange(from: Date, to: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(f.string(from: from))–\(f.string(from: to))"
    }

    private func activityColor(_ type: String) -> Color {
        switch type {
        case "coding":        return .blue
        case "research":      return .orange
        case "communication": return .green
        case "admin":         return .purple
        default:              return .gray
        }
    }
}
