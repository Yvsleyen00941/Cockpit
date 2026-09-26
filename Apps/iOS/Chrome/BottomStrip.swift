import CCCore
import SwiftUI

/// The dock — one glass slab, always visible: four quick keys · a live "now"
/// area (timer, bot P&L when it's not already on screen, now playing) ·
/// volume · mic.
struct BottomStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let strip = model.workspace.strip
        HStack(spacing: 8) {
            ForEach(strip.keys.prefix(4)) { key in
                CompactKey(key: key)
            }
            Spacer(minLength: 12)
            NowArea()
            Spacer(minLength: 12)
            if strip.showsVolume, model.store.audio != nil {
                VolumeControl()
            }
            if strip.showsMic {
                MicKey()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.dock)
        .background(GlassShape(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), outline: .rounded(28)))
        .padding(.horizontal, 20)
        .padding(.bottom, Metrics.strip - Metrics.dock)
    }
}

/// A quick key in the dock.
struct CompactKey: View {
    let key: ButtonDef
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.tap(key, pageID: nil)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: key.symbol ?? "circle")
                    .font(.system(size: 18, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CC.keyTint(key.color))
                Text(key.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Metrics.compactKey, height: Metrics.compactKey)
            .background(KeyFace(color: key.color, feedback: model.keyFeedback[key.id], radius: 17))
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
        HStack(spacing: 8) {
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
                    RingGauge(value: timer.progress(at: context.date), color: tint, lineWidth: 4)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CC.text2)
                        Text(Fmt.countdown(timer.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .light).monospacedDigit())
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
        .frame(height: 54)
        .background(Well(radius: 17, tint: tint))
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
                GlossyOrb(color: bot.status.color, size: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot.mode == .simulated ? "Bot · Sim" : "Bot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CC.text2)
                    Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                        .font(.system(size: 19, weight: .light).monospacedDigit())
                        .foregroundStyle(CC.pnl(bot.pnlToday))
                        .contentTransition(.numericText(value: bot.pnlToday))
                        .animation(.snappy, value: bot.pnlToday)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 54)
            .background(Well(radius: 17))
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
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: 54)
        .background(Well(radius: 17))
    }

    private func mediaButton(_ symbol: String, _ command: MediaCommand, prominent: Bool = false) -> some View {
        Button {
            Feedback.tap()
            model.send(.media(command))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 15 : 11, weight: .bold))
                .foregroundStyle(prominent ? CC.text : CC.text2)
                .frame(width: prominent ? 36 : 30, height: 36)
                .background(Circle().fill(prominent ? CC.elevated : .clear))
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

/// Album art — or, until it arrives, a lit gradient with a note.
struct Artwork: View {
    let track: NowPlaying
    var size: CGFloat = 48
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = track.artworkID, let image = model.images.artwork[id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x7A5CFF), Color(hex: 0x2F5BFF), Color(hex: 0x19B7E8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.45), .clear], center: UnitPoint(x: 0.25, y: 0.2), startRadius: 0, endRadius: size * 0.7)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(muted ? CC.red : CC.icon)
                    .frame(width: 26)
            }
            .buttonStyle(PressStyle())
            GeometryReader { proxy in
                let level = muted ? 0 : volume
                ZStack(alignment: .leading) {
                    Capsule().fill(CC.track)
                    Capsule()
                        .fill(LinearGradient(colors: [CC.accent.opacity(0.6), CC.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, proxy.size.width * level))
                        .opacity(muted ? 0.3 : 1)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(CC.ink.opacity(0.18), lineWidth: 0.5))
                        .offset(x: max(0, min(proxy.size.width - 14, proxy.size.width * level - 7)))
                        .opacity(muted ? 0.5 : 1)
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
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
            .frame(width: 120, height: 28)
            Text("\(Int((muted ? 0 : volume) * 100))")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(CC.text2)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Well(radius: 17))
    }
}

/// The blueprint's mic mute indicator — and more: it shows when an app is
/// actually capturing (live) and mutes system-wide.
struct MicKey: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let audio = model.store.audio
        let muted = audio?.inputMuted ?? false
        let live = (audio?.micInUse ?? false) && !muted
        let tint = muted ? CC.red : (live ? CC.green : CC.icon)
        Button {
            Feedback.tap()
            model.send(.audio(AudioCommand(.micToggle)))
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                    if live {
                        StatusDot(color: CC.green, size: 6, pulsing: true).offset(x: 8, y: -3)
                    }
                }
                Text(muted ? "Muted" : (live ? "Live" : "Mic"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(muted || live ? tint : CC.text2)
            }
            .frame(width: Metrics.compactKey, height: Metrics.compactKey)
            .background(KeyFace(color: muted ? .red : (live ? .green : .neutral), radius: 17))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(muted ? "Microphone muted" : "Microphone on")
    }
}
