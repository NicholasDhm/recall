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
            Group {
                if recordings.isEmpty {
                    VStack(spacing: 0) {
                        ScreenHeader("Insights")
                        VStack(spacing: 14) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(Color.accentColor)
                            Text("Sem dados ainda")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("Grave ou importe alguns áudios para ver seus números aqui.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                        Spacer()
                    }
                    .screenBackground()
                } else {
                    content(for: metrics)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func content(for metrics: InsightsMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                ScreenHeader("Insights", subtitle: subtitle(for: metrics))
                    .padding(.horizontal, -Metrics.gutter)

                PillPicker(
                    options: InsightsPeriod.allCases.map { ($0, $0.title) },
                    selection: $period
                )

                if metrics.isEmpty {
                    ContentUnavailableView {
                        Label("Nada neste período", systemImage: "calendar")
                    } description: {
                        Text("Escolha um período maior para ver seus números.")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    summaryCards(metrics).id("cards")
                    minutesChart(metrics).id("minutes")
                    weeklyChart(metrics).id("weekly")
                    wordsPerMinuteChart(metrics).id("wpm")
                    tagsChart(metrics).id("tags")
                    topWords(metrics).id("words")
                }
                }
                .padding()
            }
            .screenBackground()
            .onAppear {
                #if DEBUG
                if let anchor = LaunchOptions.insightsAnchor {
                    proxy.scrollTo(anchor, anchor: .top)
                }
                #endif
            }
        }
    }

    private func subtitle(for metrics: InsightsMetrics) -> String {
        metrics.isEmpty
            ? String(localized: "Nada neste período")
            : String(localized: "\(metrics.totalRecordings) gravações no período")
    }

    private func summaryCards(_ metrics: InsightsMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Gravações", value: metrics.totalRecordings.formatted())
            StatCard(title: "Horas", value: hours(metrics.totalDuration))
            StatCard(title: "Duração média", value: DurationFormat.clock(metrics.averageDuration))
            StatCard(title: "Dia mais ativo", value: weekdayName(metrics.mostActiveWeekday))
        }
    }

    private func minutesChart(_ metrics: InsightsMetrics) -> some View {
        ChartCard("Minutos gravados por dia") {
            Chart(metrics.minutesPerDay) { point in
                BarMark(
                    x: .value("Dia", point.day, unit: .day),
                    y: .value("Minutos", point.value)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartYAxisLabel("min")
            .frame(height: 180)
        }
    }

    private func weeklyChart(_ metrics: InsightsMetrics) -> some View {
        ChartCard("Gravações por semana") {
            Chart(metrics.recordingsPerWeek) { point in
                BarMark(
                    x: .value("Semana", point.day, unit: .weekOfYear),
                    y: .value("Gravações", point.value)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 160)
        }
    }

    @ViewBuilder
    private func wordsPerMinuteChart(_ metrics: InsightsMetrics) -> some View {
        if !metrics.wordsPerMinute.isEmpty {
            ChartCard("Palavras por minuto") {
                Chart {
                    ForEach(metrics.wordsPerMinute) { point in
                        LineMark(
                            x: .value("Data", point.day),
                            y: .value("Palavras por minuto", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        PointMark(
                            x: .value("Data", point.day),
                            y: .value("Palavras por minuto", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    RuleMark(y: .value("Média", metrics.averageWordsPerMinute))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Média \(metrics.averageWordsPerMinute, format: .number.precision(.fractionLength(0))) ppm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private func tagsChart(_ metrics: InsightsMetrics) -> some View {
        if !metrics.topTags.isEmpty {
            ChartCard("Tags mais usadas") {
                Chart(metrics.topTags) { tag in
                    BarMark(
                        x: .value("Gravações", tag.count),
                        y: .value("Tag", tag.name)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: CGFloat(metrics.topTags.count) * 28 + 24)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plot = proxy.plotFrame else { return }
                                let y = location.y - geometry[plot].origin.y
                                if let tag: String = proxy.value(atY: y) {
                                    navigation.showLibrary(taggedWith: tag)
                                }
                            }
                    }
                }
                Text("Toque numa tag para filtrar a Biblioteca.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func topWords(_ metrics: InsightsMetrics) -> some View {
        if !metrics.topWords.isEmpty {
            ChartCard("Palavras mais faladas") {
                VStack(spacing: 0) {
                    ForEach(Array(metrics.topWords.enumerated()), id: \.element.id) { index, word in
                        HStack {
                            Text(word.name)
                                .font(.system(.body, design: .rounded))
                            Spacer()
                            Text(word.count.formatted())
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        if index < metrics.topWords.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func hours(_ duration: TimeInterval) -> String {
        (duration / 3600).formatted(.number.precision(.fractionLength(1)))
    }

    private func weekdayName(_ weekday: Int?) -> String {
        guard let weekday else { return "—" }
        let symbols = Calendar.current.standaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "—" }
        return symbols[weekday - 1].capitalized
    }
}

private struct StatCard: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 14)
    }
}

private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.cardTitle)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}
