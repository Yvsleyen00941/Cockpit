import Foundation

public enum BriefTone: String, Sendable, Hashable { case great, steady, careful, neutral }

public struct Brief: Sendable, Hashable {
    public var greeting: String
    public var headline: String
    public var tone: BriefTone
    public var lines: [String]
}

/// Turns the morning's numbers into plain language — deterministic, local,
/// no model call. "High recovery — good day for deep work."
public enum BriefComposer {
    public static func greeting(name: String, at date: Date, cal: Calendar = .current) -> String {
        let hour = cal.component(.hour, from: date)
        let part: String = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Working late"
        }
        return name.isEmpty ? part : "\(part), \(name)"
    }

    public static func recoveryHeadline(_ whoop: WhoopState?) -> (String, BriefTone) {
        guard let whoop, whoop.connected else {
            return ("Connect WHOOP to see today's recovery", .neutral)
        }
        guard let score = whoop.recovery, whoop.recoveryState != .pending else {
            return ("Recovery is still being scored", .neutral)
        }
        switch RecoveryZone(score: score) {
        case .green: return ("High recovery — good day for deep work", .great)
        case .yellow: return ("Moderate recovery — front-load the hard things", .steady)
        case .red: return ("Low recovery — keep it light and protect your energy", .careful)
        }
    }

    public static func compose(
        whoop: WhoopState?,
        calendar: CalendarState?,
        bot: BotState?,
        weather: WeatherState?,
        preferences: WorkspacePreferences,
        now: Date,
        cal: Calendar = .current
    ) -> Brief {
        let (headline, tone) = recoveryHeadline(whoop)
        var lines: [String] = []

        if let hours = whoop?.sleepHours {
            var sleep = "\(Fmt.hoursMinutes(hours)) of sleep"
            if let perf = whoop?.sleepPerformance { sleep += " (\(Int(perf.rounded()))% of need)" }
            lines.append(sleep + ".")
        }

        if let calendar, calendar.access == .granted {
            let remaining = calendar.today(now, calendar: cal).filter { !$0.isAllDay && $0.end > now }
            if let first = remaining.first {
                let free = first.start.timeIntervalSince(now)
                var line = "\(remaining.count) event\(remaining.count == 1 ? "" : "s") left today; next is \(first.title) at \(Fmt.clock(first.start))"
                if free >= 45 * 60 { line += " — a \(Fmt.duration(free)) window for focused work first" }
                lines.append(line + ".")
            } else {
                lines.append("Nothing on the calendar for the rest of the day.")
            }
        }

        if let bot, bot.mode != .off {
            if let overnight = bot.overnight, overnight.trades > 0 {
                let verb = overnight.pnl >= 0 ? "made" : "lost"
                lines.append("The bot \(verb) \(Fmt.money(abs(overnight.pnl), currency: bot.currency)) overnight across \(overnight.trades) trade\(overnight.trades == 1 ? "" : "s").")
            } else if bot.status == .running {
                lines.append("The bot is running with \(bot.positions.count) open position\(bot.positions.count == 1 ? "" : "s").")
            } else {
                lines.append("The bot is \(bot.status.title.lowercased()).")
            }
        }

        if let weather {
            var line = "\(Int(weather.temperature.rounded()))° and \(weather.condition.description.lowercased()) in \(weather.location)"
            if let wet = weather.hourly.first(where: { WeatherCondition(code: $0.code, isDay: $0.isDay).isWet && $0.precipitationChance >= 50 && $0.time > now }) {
                line += ", rain from \(Fmt.clock(wet.time))"
            } else {
                line += ", high of \(Int(weather.high.rounded()))°"
            }
            lines.append(line + ".")
        }

        return Brief(
            greeting: greeting(name: preferences.ownerName, at: now, cal: cal),
            headline: headline,
            tone: tone,
            lines: lines
        )
    }
}
