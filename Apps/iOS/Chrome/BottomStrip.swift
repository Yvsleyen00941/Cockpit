import CCCore
import SwiftUI

/// 80 pt, always visible: four fixed quick keys · a live "now" area (timer,
/// bot P&L when it's not already on screen, now playing) · volume · mic.
struct BottomStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let strip = model.workspace.strip
        HStack(spacing: 10) {
            ForEach(strip.keys.prefix(4)) { key in
                CompactKey(key: key)
            }
            Spacer(minLength: 14)
            NowArea()
            Spacer(minLength: 14)
            if strip.showsVolume, model.store.audio != nil {
                VolumeControl()
            }
            if strip.showsMic {
                MicKey()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Metrics.strip)
        .background(CC.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(CC.divider).frame(height: 1)
        }
    }
}

/// 60 × 60 quick key.
struct CompactKey: View {
    let key: ButtonDef
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.tap(key, pageID: nil)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: key.symbol ?? "circle")
                    .font(.system(size: 19, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CC.keyTint(key.color))
                Text(key.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Metrics.compactKey, height: Metrics.compactKey)
            .background(KeyFace(color: key.color, feedback: model.keyFeedback[key.id], radius: 14))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(key.label)
    }
}

// MARK: - Now area

struct NowArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let strip = model.workspace.strip
        let pageChannels = model.currentPage?.channels ?? []
        HStack(spacing: 10) {
            if strip.showsTimer, let timer = model.store.timers?.primary {
                TimerPill(timer: timer)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if let bot = model.store.bot, bot.mode != .off, !pageChannels.contains(.bot) {
                BotTicker(bot: bot)
                    .transition(.opacity)
            }
            if strip.showsNowPlaying, let track = model.store.media?.nowPlaying, !pageChannels.contains(.media) || model.currentPage?.id != "home" {
                NowPlayingMini(track: track)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.store.timers?.primary?.id)
    }
}

struct TimerPill: View {
    let timer: TimerState
    @Environment(AppModel.self) private var model

    var body: some View {
        let tint = timer.kind.isBreak ? CC.green : CC.orange
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 10) {
                    RingGauge(value: timer.progress(at: context.date), color: tint, lineWidth: 4, track: CC.elevated)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.9)
                            .foregroundStyle(CC.text2)
                        Text(Fmt.countdown(timer.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                            .foregroundStyle(timer.state == .paused ? CC.text2 : CC.text)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(timer.remaining(at: context.date)))
                    }
                }
            }
            Button {
                Feedback.tap()
                model.send(.timer(TimerCommand(.toggle)))
            } label: {
                Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.16)))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .onTapGesture { model.show(page: "study") }
    }
}

/// Mini P&L for pages that don't already show the bot.
struct BotTicker: View {
    let bot: BotState
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.show(page: "bot")
        } label: {
            HStack(spacing: 10) {
                StatusDot(color: bot.status == .running ? CC.green : (bot.status == .paused ? CC.orange : CC.red), size: 7)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot.mode == .simulated ? "BOT · SIM" : "BOT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(CC.text2)
                    Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.pnl(bot.pnlToday))
                        .contentTransition(.numericText(value: bot.pnlToday))
                        .animation(.snappy, value: bot.pnlToday)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated.opacity(0.65)))
        }
        .buttonStyle(PressStyle(scale: 0.97))
    }
}

struct NowPlayingMini: View {
    let track: NowPlaying
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Artwork(track: track, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CC.text)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(CC.text2)
            }
            .lineLimit(1)
            .frame(maxWidth: 150, alignment: .leading)
            HStack(spacing: 2) {
                mediaButton("backward.fill", .previous)
                mediaButton(track.isPlaying ? "pause.fill" : "play.fill", .playPause, prominent: true)
                mediaButton("forward.fill", .next)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated.opacity(0.65)))
    }

    private func mediaButton(_ symbol: String, _ command: MediaCommand, prominent: Bool = false) -> some View {
        Button {
            Feedback.tap()
            model.send(.media(command))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 16 : 12, weight: .bold))
                .foregroundStyle(prominent ? CC.text : CC.text2)
                .frame(width: 32, height: 36)
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

struct Artwork: View {
    let track: NowPlaying
    var size: CGFloat = 48
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = track.artworkID, let image = model.images.artwork[id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [CC.accent.opacity(0.55), CC.purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white.opacity(0.85)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .onAppear { model.images.requestArtwork(track.artworkID, via: model.link) }
    }
}

// MARK: - Volume & mic

struct VolumeControl: View {
    @Environment(AppModel.self) private var model
    @State private var dragValue: Double?
    @State private var lastSent = Date.distantPast

    var body: some View {
        let audio = model.store.audio
        let volume = dragValue ?? audio?.outputVolume ?? 0
        let muted = audio?.outputMuted ?? false
        HStack(spacing: 10) {
            Button {
                Feedback.tap()
                model.send(.audio(AudioCommand(.outputMuteToggle)))
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : (volume > 0.66 ? "speaker.wave.3.fill" : volume > 0.33 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(muted ? CC.red : CC.text2)
                    .frame(width: 26)
            }
            .buttonStyle(PressStyle())
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(CC.elevated)
                    Capsule()
                        .fill(LinearGradient(colors: [CC.accent.opacity(0.7), CC.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, proxy.size.width * (muted ? 0 : volume)))
                        .opacity(muted ? 0.3 : 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let value = min(1, max(0, gesture.location.x / proxy.size.width))
                            dragValue = value
                            if Date().timeIntervalSince(lastSent) > 0.08 {
                                lastSent = .now
                                model.send(.audio(AudioCommand(.setOutputVolume, value: value)))
                            }
                        }
                        .onEnded { _ in
                            if let value = dragValue { model.send(.audio(AudioCommand(.setOutputVolume, value: value))) }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                dragValue = nil
                            }
                        }
                )
            }
            .frame(width: 120, height: 10)
            Text("\(Int((muted ? 0 : volume) * 100))")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(CC.text2)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated.opacity(0.65)))
    }
}

/// The blueprint's mic mute indicator — and more: it shows when an app is
/// actually capturing (LIVE) and mutes system-wide.
struct MicKey: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let audio = model.store.audio
        let muted = audio?.inputMuted ?? false
        let live = (audio?.micInUse ?? false) && !muted
        let tint = muted ? CC.red : (live ? CC.green : CC.text2)
        Button {
            Feedback.tap()
            model.send(.audio(AudioCommand(.micToggle)))
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                    if live {
                        StatusDot(color: CC.green, size: 6, pulsing: true).offset(x: 8, y: -3)
                    }
                }
                Text(muted ? "MUTED" : (live ? "LIVE" : "MIC"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(tint)
            }
            .frame(width: Metrics.compactKey, height: Metrics.compactKey)
            .background(
                ZStack {
                    KeyFace(color: muted ? .red : (live ? .green : .neutral), radius: 14)
                }
            )
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(muted ? "Microphone muted" : "Microphone on")
    }
}
