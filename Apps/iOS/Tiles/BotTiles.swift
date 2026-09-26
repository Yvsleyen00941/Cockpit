import Charts
import CCCore
import SwiftUI

// MARK: - Home quadrant

/// P&L today, positions, last action, a live sparkline and a big Pause.
struct BotSummaryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            GeometryReader { proxy in
                let roomy = proxy.size.height > 250
                let narrow = proxy.size.width < 440
                VStack(alignment: .leading, spacing: roomy ? 12 : 8) {
                    CardHeader(title: "Trading bot", symbol: "chart.line.uptrend.xyaxis") {
                        HStack(spacing: 6) {
                            if bot.mode == .simulated { Pill(text: "Sim", color: CC.purple) }
                            Pill(text: bot.status.title, color: bot.status.color, dot: true)
                            if !narrow { GoToBadge() }
                        }
                    }
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            RollingMoney(value: bot.pnlToday, currency: bot.currency, size: roomy ? 56 : 42)
                            HStack(spacing: 8) {
                                Text(Fmt.percent(bot.pnlTodayPct ?? 0))
                                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(CC.pnl(bot.pnlToday))
                                Text("today")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CC.text2)
                                if let equity = bot.equity, !narrow {
                                    Text("·").foregroundStyle(CC.text3)
                                    Text("Equity \(Fmt.money(equity, currency: bot.currency, decimals: 0))")
                                        .font(.system(size: 14).monospacedDigit())
                                        .foregroundStyle(CC.text2)
                                }
                            }
                            .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        pauseButton(bot, height: roomy ? 62 : 52)
                            .frame(width: min(170, proxy.size.width * 0.3))
                    }
                    Sparkline(values: WidgetSnapshot.downsample(model.store.botSeries?.points ?? [], to: 90).map(\.v) + [bot.pnlToday], color: CC.pnl(bot.pnlToday), baseline: 0)
                        .frame(maxHeight: .infinity)
                    HStack(spacing: 26) {
                        Stat(label: "Positions", value: "\(bot.positions.count)", size: 22)
                        Stat(label: "Trades", value: "\(bot.tradesToday)", size: 22)
                        if let last = bot.lastEvent {
                            VStack(alignment: .leading, spacing: 5) {
                                SectionLabel("Last · \(Fmt.ago(last.time))")
                                LastTradeLine(event: last)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .card()
            .contentShape(Rectangle())
            .onTapGesture { model.show(page: "bot") }
        }
    }

    @ViewBuilder
    private func pauseButton(_ bot: BotState, height: CGFloat) -> some View {
        if bot.status == .paused {
            LargeActionButton(title: "Resume", symbol: "play.fill", color: CC.green, height: height) {
                model.send(.bot(.resume))
            }
        } else {
            LargeActionButton(title: "Pause", symbol: "pause.fill", color: CC.orange, height: height, enabled: bot.status == .running) {
                model.send(.bot(.pause))
            }
        }
    }
}

struct LastTradeLine: View {
    let event: BotEvent

    var body: some View {
        HStack(spacing: 7) {
            Tag(text: event.kind == .buy ? "BUY" : "SELL", color: event.kind == .buy ? CC.green : CC.red)
            Text([event.symbol, event.price.map(Fmt.price)].compactMap { $0 }.joined(separator: " @ "))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(CC.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - P&L chart

/// Full-width P&L for today: a glowing line over a soft area, green above
/// zero, red below.
struct BotChartTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "P&L today", symbol: "chart.xyaxis.line") {
                    HStack(spacing: 6) {
                        if bot.mode == .simulated { Pill(text: "Sim", color: CC.purple) }
                        Pill(text: bot.status.title, color: bot.status.color, dot: true)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    RollingMoney(value: bot.pnlToday, currency: bot.currency, size: 60)
                    Text(Fmt.percent(bot.pnlTodayPct ?? 0))
                        .font(.system(size: 20, weight: .medium).monospacedDigit())
                        .foregroundStyle(CC.pnl(bot.pnlToday))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        SectionLabel("High / low")
                        Text(highLow(bot))
                            .font(.system(size: 15, weight: .regular).monospacedDigit())
                            .foregroundStyle(CC.text)
                    }
                }
                PnLChart(points: points(bot), currency: bot.currency)
            }
            .card()
        }
    }

    private func points(_ bot: BotState) -> [PnLPoint] {
        var points = model.store.botSeries?.points ?? []
        points.append(PnLPoint(t: bot.updatedAt, v: bot.pnlToday))
        return points
    }

    private func highLow(_ bot: BotState) -> String {
        let values = points(bot).map(\.v)
        guard let high = values.max(), let low = values.min() else { return "—" }
        return "\(Fmt.compactMoney(high, currency: bot.currency)) / \(Fmt.compactMoney(low, currency: bot.currency))"
    }
}

struct PnLChart: View {
    let points: [PnLPoint]
    var currency = "EUR"

    var body: some View {
        let values = points.map(\.v)
        let low = min(0, values.min() ?? 0)
        let high = max(0, values.max() ?? 0)
        let span = max(high - low, 1)
        let zero = high / span
        let lineStops: [Gradient.Stop] = [
            .init(color: CC.green, location: 0),
            .init(color: CC.green, location: zero),
            .init(color: CC.red, location: zero),
            .init(color: CC.red, location: 1),
        ]
        let lastColor = CC.pnl(points.last?.v ?? 0)
        let areaStops: [Gradient.Stop] = [
            .init(color: CC.green.opacity(0.3), location: 0),
            .init(color: CC.green.opacity(0.02), location: zero),
            .init(color: CC.red.opacity(0.02), location: zero),
            .init(color: CC.red.opacity(0.3), location: 1),
        ]
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                // The glow: the same curve, wide and faint, under the line.
                LineMark(x: .value("Time", point.t), y: .value("P&L", point.v), series: .value("Layer", "glow"))
                    .foregroundStyle(lastColor.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Time", point.t), yStart: .value("Zero", 0), yEnd: .value("P&L", point.v))
                    .foregroundStyle(LinearGradient(stops: areaStops, startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.t), y: .value("P&L", point.v), series: .value("Layer", "line"))
                    .foregroundStyle(LinearGradient(stops: lineStops, startPoint: .top, endPoint: .bottom))
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(CC.text3.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
            if let last = points.last {
                PointMark(x: .value("Time", last.t), y: .value("P&L", last.v))
                    .symbolSize(420)
                    .foregroundStyle(CC.pnl(last.v).opacity(0.18))
                PointMark(x: .value("Time", last.t), y: .value("P&L", last.v))
                    .symbolSize(60)
                    .foregroundStyle(.white)
            }
        }
        .chartYScale(domain: (low - span * 0.08)...(high + span * 0.12))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine().foregroundStyle(CC.divider)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Fmt.clock(date)).font(.system(size: 11).monospacedDigit()).foregroundStyle(CC.text3)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(CC.divider)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.compactMoney(v, currency: currency)).font(.system(size: 11).monospacedDigit()).foregroundStyle(CC.text3)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: points.count)
    }
}

// MARK: - Controls

struct BotActionsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            GeometryReader { proxy in
                let showsTotals = proxy.size.height > 330
                let height = min(Metrics.largeButton, (proxy.size.height - 24 - (showsTotals ? 80 : 0)) / 3)
                VStack(spacing: 12) {
                    LargeActionButton(title: "Pause bot", symbol: "pause.fill", color: CC.orange, style: bot.status == .running ? .filled : .tinted, height: height, enabled: bot.status == .running) {
                        model.send(.bot(.pause))
                    }
                    LargeActionButton(title: "Resume bot", symbol: "play.fill", color: CC.green, style: bot.status == .paused ? .filled : .tinted, height: height, enabled: bot.status != .running) {
                        model.send(.bot(.resume))
                    }
                    LargeActionButton(title: "Close all", symbol: "xmark.octagon.fill", color: CC.red, style: .tinted, height: height, enabled: !bot.positions.isEmpty, hold: true, subtitle: bot.positions.isEmpty ? "No open positions" : "Hold · \(bot.positions.count) position\(bot.positions.count == 1 ? "" : "s")") {
                        model.confirmation = PendingConfirmation(key: ButtonDef(id: "bot.closeAll", label: "Close All Positions", symbol: "xmark.octagon.fill", color: .red, action: .bot(.closeAll), confirm: .dialog), pageID: "bot")
                    }
                    if showsTotals {
                        Spacer(minLength: 0)
                        Rectangle().fill(CC.divider).frame(height: 1)
                        HStack {
                            Stat(label: "Realised", value: Fmt.money(bot.pnlToday - bot.unrealizedTotal, currency: bot.currency, signed: true), color: CC.pnl(bot.pnlToday - bot.unrealizedTotal), size: 18)
                            Spacer()
                            Stat(label: "Unrealised", value: Fmt.money(bot.unrealizedTotal, currency: bot.currency, signed: true), color: CC.pnl(bot.unrealizedTotal), size: 18)
                            Spacer()
                            Stat(label: "Exposure", value: Fmt.compactMoney(bot.positions.reduce(0) { $0 + abs($1.quantity * $1.currentPrice) }, currency: bot.currency), size: 18)
                        }
                    }
                }
            }
            .card()
        }
    }
}

// MARK: - Health

struct BotHealthTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 0) {
                    chip(bot.apiConnected ? "API connected" : "API down", symbol: "antenna.radiowaves.left.and.right", color: bot.apiConnected ? CC.green : CC.red, dot: true)
                    divider
                    chip("Heartbeat \(bot.lastHeartbeat.map { Fmt.ago($0, from: context.date) } ?? "—")", symbol: "waveform.path.ecg", color: heartbeatColor(bot, now: context.date))
                    divider
                    chip("\(bot.tradesToday) trades today", symbol: "arrow.left.arrow.right", color: CC.accent)
                    divider
                    chip("Equity \(bot.equity.map { Fmt.money($0, currency: bot.currency, decimals: 0) } ?? "—")", symbol: "banknote", color: CC.accent)
                    divider
                    chip(bot.mode == .simulated ? "Simulated" : "Live", symbol: bot.mode == .simulated ? "testtube.2" : "bolt.fill", color: bot.mode == .simulated ? CC.purple : CC.yellow)
                    if let error = bot.error {
                        divider
                        chip(error, symbol: "exclamationmark.triangle.fill", color: CC.red)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CardBackground())
        }
    }

    private var divider: some View {
        Rectangle().fill(CC.divider).frame(width: 1, height: 20).padding(.horizontal, 16)
    }

    private func heartbeatColor(_ bot: BotState, now: Date) -> Color {
        guard let beat = bot.lastHeartbeat else { return CC.text2 }
        let age = now.timeIntervalSince(beat)
        return age < 10 ? CC.green : (age < 60 ? CC.yellow : CC.red)
    }

    private func chip(_ text: String, symbol: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 9) {
            if dot {
                GlossyOrb(color: color, size: 10)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(CC.text)
                .lineLimit(1)
        }
    }
}

// MARK: - Positions

struct BotPositionsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Positions", symbol: "list.bullet.rectangle") {
                    HStack(spacing: 6) {
                        Text("Unrealised")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CC.text2)
                        Text(Fmt.money(bot.unrealizedTotal, currency: bot.currency, signed: true))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CC.pnl(bot.unrealizedTotal))
                    }
                }
                if bot.positions.isEmpty {
                    Text("Flat — no open positions.")
                        .font(.system(size: 15))
                        .foregroundStyle(CC.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
                        GridRow {
                            Text("Symbol").gridColumnAlignment(.leading)
                            Text("Side").gridColumnAlignment(.leading)
                            Text("Qty")
                            Text("Entry")
                            Text("Last")
                            Text("P&L")
                            Text("%")
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(CC.text3)
                        .padding(.bottom, 8)
                        ForEach(bot.positions) { position in
                            Rectangle().fill(CC.divider).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                Text(position.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(CC.text)
                                    .gridColumnAlignment(.leading)
                                Tag(text: position.side == .long ? "LONG" : "SHORT", color: position.side == .long ? CC.green : CC.red)
                                    .gridColumnAlignment(.leading)
                                Text(Fmt.quantity(position.quantity))
                                Text(Fmt.price(position.entryPrice)).foregroundStyle(CC.text2)
                                Text(Fmt.price(position.currentPrice))
                                    .contentTransition(.numericText(value: position.currentPrice))
                                Text(Fmt.money(position.unrealizedPnL, currency: bot.currency, signed: true))
                                    .foregroundStyle(CC.pnl(position.unrealizedPnL))
                                    .contentTransition(.numericText(value: position.unrealizedPnL))
                                Text(Fmt.percent(position.unrealizedPct, decimals: 2))
                                    .foregroundStyle(CC.pnl(position.unrealizedPnL))
                            }
                            .font(.system(size: 14, weight: .regular).monospacedDigit())
                            .foregroundStyle(CC.text)
                            .padding(.vertical, 10)
                            .animation(.snappy, value: position.currentPrice)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .card()
        }
    }
}

// MARK: - Log

/// Last buy/sell events — the terminal feed.
struct BotLogTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Activity", symbol: "text.alignleft") {
                Text("Last 10")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CC.text3)
            }
            let all = Array((model.store.botEvents?.events ?? []).prefix(10))
            if all.isEmpty {
                Text("No trades yet today.")
                    .font(.system(size: 15))
                    .foregroundStyle(CC.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                let events = Array(all.prefix(max(1, Int((proxy.size.height + 8) / 29))))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(events) { event in
                        HStack(spacing: 10) {
                            Text(Fmt.clock(event.time, seconds: true))
                                .foregroundStyle(CC.text3)
                            Tag(text: tag(event), color: color(event))
                                .frame(width: 58, alignment: .leading)
                            Text(line(event))
                                .foregroundStyle(CC.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let pnl = event.pnl {
                                Text(Fmt.money(pnl, signed: true))
                                    .foregroundStyle(CC.pnl(pnl))
                            } else if let outcome = event.outcome {
                                Text(outcome.capitalized).foregroundStyle(CC.text3)
                            }
                        }
                        .font(.system(size: 12.5, design: .monospaced))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: events.map(\.id))
                }
            }
        }
        .card()
    }

    private func tag(_ event: BotEvent) -> String {
        switch event.kind {
        case .buy: "BUY"
        case .sell: "SELL"
        case .paused: "PAUSE"
        case .resumed: "RESUME"
        case .error: "ERROR"
        case .warning: "WARN"
        case .info: "INFO"
        }
    }

    private func color(_ event: BotEvent) -> Color {
        switch event.kind {
        case .buy: CC.green
        case .sell: CC.red
        case .paused, .warning: CC.orange
        case .resumed: CC.accent
        case .error: CC.red
        case .info: CC.text2
        }
    }

    private func line(_ event: BotEvent) -> String {
        if !event.isTrade { return event.message ?? "" }
        let quantity = event.quantity.map(Fmt.quantity) ?? ""
        let price = event.price.map(Fmt.price) ?? ""
        return "\(event.symbol ?? "") \(quantity) @ \(price)"
    }
}

// MARK: - Overnight (Brief)

struct BotOvernightTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BotGate { bot in
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Bot overnight", symbol: "moon.stars.fill", tint: CC.indigo) {
                    if bot.mode == .simulated { Pill(text: "Sim", color: CC.purple) }
                }
                if let night = bot.overnight {
                    RollingMoney(value: night.pnl, currency: bot.currency, size: 46)
                    Text("\(night.trades) trade\(night.trades == 1 ? "" : "s") between \(Fmt.clock(night.from)) and \(Fmt.clock(night.to))")
                        .font(.system(size: 14))
                        .foregroundStyle(CC.text2)
                } else {
                    Text("Quiet night")
                        .font(CCFont.title(30, weight: .light))
                        .foregroundStyle(CC.text)
                    Text("No trades since 22:00.")
                        .font(.system(size: 14))
                        .foregroundStyle(CC.text2)
                }
                Spacer(minLength: 0)
                Rectangle().fill(CC.divider).frame(height: 1)
                HStack {
                    Stat(label: "Today", value: Fmt.money(bot.pnlToday, currency: bot.currency, signed: true), color: CC.pnl(bot.pnlToday), size: 19)
                    Spacer()
                    Stat(label: "Status", value: bot.status.title, color: bot.status.color, size: 19)
                }
            }
            .card()
        }
    }
}
