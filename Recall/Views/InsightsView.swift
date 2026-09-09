import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(Navigation.self) private var navigation
    @Query private var recordings: [Recording]
    @State private var period: InsightsPeriod = .month

    private var metrics: InsightsMetrics {
        InsightsMetrics.make(from: recordings.map(\.stats), period: period)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()
                if recordings.isEmpty { empty } else { content(for: metrics) }
            }
            .navigationBarHidden(true)
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            PageTitle("Insights")
            VStack(spacing: 10) {
                Text("Sem dados ainda.")
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                Text("Grave ou importe alguns áudios para ver seus números aqui.")
                    .font(.uiMeta)
                    .foregroundStyle(Color.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            Spacer()
        }
    }

    private func content(for metrics: InsightsMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle(
                        "Insights",
                        subtitle: metrics.isEmpty
                            ? String(localized: "Nada neste período")
                            : String(localized: "\(metrics.totalRecordings) gravações no período")
                    )
                    .padding(.horizontal, -Metrics.gutter)

                    UnderlinePicker(
                        options: InsightsPeriod.allCases.map { ($0, $0.title) },
                        selection: $period
                    )
                    .padding(.bottom, 30)

                    if metrics.isEmpty {
                        Text("Escolha um período maior.")
                            .font(.uiMeta)
                            .foregroundStyle(Color.inkSoft)
                    } else {
                        figures(metrics).id("cards")
                        section("Minutos por dia", id: "minutes") { minutesChart(metrics) }
                        section("Gravações por semana", id: "weekly") { weeklyChart(metrics) }
                        if !metrics.wordsPerMinute.isEmpty {
                            section("Palavras por minuto", id: "wpm") { wordsChart(metrics) }
                        }
                        if !metrics.topTags.isEmpty {
                            section("Tags", id: "tags") { tagsChart(metrics) }
                        }
                        if !metrics.topWords.isEmpty {
                            section("Palavras mais faladas", id: "words") { wordList(metrics) }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 40)
            }
            .paperBackground()
            .onAppear {
                #if DEBUG
                if let anchor = LaunchOptions.insightsAnchor { proxy.scrollTo(anchor, anchor: .top) }
                #endif
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Rule()
            Marker(text: title).padding(.top, 4)
            content()
        }
        .padding(.bottom, 34)
        .id(id)
    }

    /// Four numbers, set in serif and separated by rules. No boxes.
    private func figures(_ metrics: InsightsMetrics) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                figure(metrics.totalRecordings.formatted(), "Gravações")
                Rectangle().fill(Color.rule).frame(width: 0.5, height: 46)
                figure((metrics.totalDuration / 3600).formatted(.number.precision(.fractionLength(1))), "Horas")
            }
            Rule().padding(.vertical, 18)
            HStack(spacing: 0) {
                figure(DurationFormat.clock(metrics.averageDuration), "Duração média")
                Rectangle().fill(Color.rule).frame(width: 0.5, height: 46)
                figure(weekdayName(metrics.mostActiveWeekday), "Dia mais ativo")
            }
        }
        .padding(.bottom, 34)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.numeric(30))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Marker(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    private func minutesChart(_ metrics: InsightsMetrics) -> some View {
        Chart(metrics.minutesPerDay) { point in
            BarMark(x: .value("Dia", point.day, unit: .day), y: .value("Minutos", point.value))
                .foregroundStyle(Color.ember)
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .frame(height: 150)
    }

    private func weeklyChart(_ metrics: InsightsMetrics) -> some View {
        Chart(metrics.recordingsPerWeek) { point in
            BarMark(x: .value("Semana", point.day, unit: .weekOfYear), y: .value("Gravações", point.value))
                .foregroundStyle(Color.ember)
        }
        .frame(height: 130)
    }

    private func wordsChart(_ metrics: InsightsMetrics) -> some View {
        Chart {
            ForEach(metrics.wordsPerMinute) { point in
                LineMark(x: .value("Data", point.day), y: .value("Palavras por minuto", point.value))
                    .foregroundStyle(Color.ember)
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(y: .value("Média", metrics.averageWordsPerMinute))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(Color.inkFaint)
                .annotation(position: .top, alignment: .leading) {
                    Text("média \(metrics.averageWordsPerMinute, format: .number.precision(.fractionLength(0))) ppm")
                        .font(.caption2)
                        .foregroundStyle(Color.inkSoft)
                }
        }
        .frame(height: 150)
    }

    private func tagsChart(_ metrics: InsightsMetrics) -> some View {
        VStack(spacing: 0) {
            ForEach(metrics.topTags) { tag in
                Button {
                    navigation.showLibrary(taggedWith: tag.name)
                } label: {
                    HStack(spacing: 12) {
                        Text(tag.name)
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.ink)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { proxy in
                            let maximum = metrics.topTags.map(\.count).max() ?? 1
                            Capsule()
                                .fill(Color.ember.opacity(0.9))
                                .frame(
                                    width: proxy.size.width * CGFloat(tag.count) / CGFloat(maximum),
                                    height: 6
                                )
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 20)
                        Text(tag.count.formatted())
                            .font(.system(.caption, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.inkSoft)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Filtra a Biblioteca por esta tag"))
            }
        }
    }

    private func wordList(_ metrics: InsightsMetrics) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(metrics.topWords.enumerated()), id: \.element.id) { index, word in
                if index > 0 { Rule() }
                HStack {
                    Text(word.name)
                        .font(.readingSmall)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text(word.count.formatted())
                        .font(.system(.footnote, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.inkFaint)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func weekdayName(_ weekday: Int?) -> String {
        guard let weekday else { return "—" }
        let symbols = Calendar.current.standaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "—" }
        return symbols[weekday - 1].capitalized
    }
}
