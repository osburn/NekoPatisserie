import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - Pink Palette & Game Models

private enum PinkPalette {
    static let bgPink = Color(red: 1.0, green: 0.88, blue: 0.94)
    static let panelPink = Color(red: 1.0, green: 0.78, blue: 0.88)
    static let counterPink = Color(red: 0.96, green: 0.56, blue: 0.76)
    static let hotPink = Color(red: 0.91, green: 0.25, blue: 0.56)
    static let deepBerry = Color(red: 0.42, green: 0.10, blue: 0.27)
    static let creamWhite = Color(red: 1.0, green: 0.98, blue: 0.99)
    static let stripePink = Color(red: 1.0, green: 0.82, blue: 0.90)
    static let skinLight = Color(red: 1.0, green: 0.93, blue: 0.90)
    static let skinShadow = Color(red: 0.94, green: 0.76, blue: 0.74)
    static let blushPink = Color(red: 1.0, green: 0.48, blue: 0.70)
}

private enum Ingredient: String, CaseIterable, Identifiable {
    case mochi = "Pink Mochi"
    case strawberry = "Strawberry"
    case cream = "Whipped Cream"
    case sakura = "Sakura Glaze"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .mochi: return Color(red: 1.0, green: 0.65, blue: 0.81)
        case .strawberry: return Color(red: 0.96, green: 0.20, blue: 0.38)
        case .cream: return Color.white
        case .sakura: return Color(red: 1.0, green: 0.49, blue: 0.72)
        }
    }
}

private struct Recipe: Identifiable {
    let id = UUID()
    let name: String
    let steps: [Ingredient]

    static let all: [Recipe] = [
        Recipe(name: "Neko Mochi Parfait", steps: [.mochi, .cream, .strawberry]),
        Recipe(name: "Sakura Berry Cake", steps: [.strawberry, .cream, .sakura]),
        Recipe(name: "Sweet Kitty Sundae", steps: [.mochi, .strawberry, .sakura])
    ]
}

// MARK: - Optional Multi-Layer Part Loader (for custom Live2D-style PNG parts)

private enum RigPartLoader {
    static func loadPart(_ name: String) -> NSImage? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let candidate = cwd.appendingPathComponent("Assets/\(name).png")
        if fm.fileExists(atPath: candidate.path) {
            return NSImage(contentsOf: candidate)
        }
        return nil
    }
}

// MARK: - Audio Engine with Lip-Sync State

private final class NekoAudioEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = NekoAudioEngine()

    @Published var isSpeaking: Bool = false
    @Published var activeSpeakerPitch: Float = 1.35

    private let engine = AVAudioEngine()
    private let synthPlayer = AVAudioPlayerNode()
    private let bgmPlayer = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat
    private let synthesizer = AVSpeechSynthesizer()

    var bgmEnabled: Bool = true {
        didSet { bgmEnabled ? startBGM() : bgmPlayer.stop() }
    }
    var voiceEnabled: Bool = true

    private override init() {
        let sr = 44100.0
        self.audioFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        super.init()
        synthesizer.delegate = self

        engine.attach(synthPlayer)
        engine.attach(bgmPlayer)
        engine.connect(synthPlayer, to: engine.mainMixerNode, format: audioFormat)
        engine.connect(bgmPlayer, to: engine.mainMixerNode, format: audioFormat)
        bgmPlayer.volume = 0.13
        synthPlayer.volume = 0.28

        do {
            try engine.start()
            synthPlayer.play()
            bgmPlayer.play()
            startBGM()
        } catch {
            print("Audio warning: \(error)")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speakJapanese(_ text: String, pitch: Float = 1.35, rate: Float = 0.52) {
        guard voiceEnabled else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeSpeakerPitch = pitch
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.pitchMultiplier = pitch
        utterance.rate = rate
        utterance.volume = 0.92
        synthesizer.speak(utterance)
    }

    func playPopSFX() { playTone(freq: 660, endFreq: 990, duration: 0.08) }

    func playSuccessSFX() {
        playTone(freq: 587.33, endFreq: 587.33, duration: 0.09, delay: 0.00)
        playTone(freq: 783.99, endFreq: 783.99, duration: 0.09, delay: 0.09)
        playTone(freq: 1046.5, endFreq: 1174.66, duration: 0.18, delay: 0.18)
    }

    func playMissSFX() { playTone(freq: 360, endFreq: 210, duration: 0.22) }

    private func playTone(freq: Double, endFreq: Double, duration: Double, delay: Double = 0) {
        guard engine.isRunning else { return }
        let sr = audioFormat.sampleRate
        let frames = AVAudioFrameCount(max(1, Int(sr * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var phase = 0.0
        for i in 0..<Int(frames) {
            let p = Double(i) / Double(frames)
            phase += (2.0 * .pi * (freq + (endFreq - freq) * p)) / sr
            data[i] = Float(sin(phase) * sin(.pi * p))
        }
        let when: AVAudioTime? = delay > 0
            ? AVAudioTime(sampleTime: (synthPlayer.lastRenderTime?.sampleTime ?? 0) + AVAudioFramePosition(delay * sr), atRate: sr)
            : nil
        synthPlayer.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
    }

    private func startBGM() {
        guard bgmEnabled, engine.isRunning else { return }
        let notes: [(Double, Double)] = [
            (523.25, 0.22), (659.25, 0.22), (783.99, 0.22), (880.00, 0.34),
            (783.99, 0.22), (659.25, 0.22), (587.33, 0.44),
            (587.33, 0.22), (698.46, 0.22), (880.00, 0.22), (1046.50, 0.34),
            (880.00, 0.22), (783.99, 0.22), (659.25, 0.44)
        ]
        let sr = audioFormat.sampleRate
        let totalFrames = AVAudioFrameCount(max(1, Int(sr * notes.reduce(0.0) { $0 + $1.1 })))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: totalFrames) else { return }
        buffer.frameLength = totalFrames
        let out = buffer.floatChannelData![0]
        var cursor = 0
        var phase = 0.0
        for (freq, dur) in notes {
            let n = Int(sr * dur)
            for j in 0..<n where cursor < Int(totalFrames) {
                let p = Double(j) / Double(max(1, n))
                phase += (2.0 * .pi * freq) / sr
                out[cursor] = Float((0.75 * sin(phase) + 0.25 * sin(2.0 * phase)) * sin(.pi * min(1.0, p)) * 0.65)
                cursor += 1
            }
        }
        bgmPlayer.stop()
        bgmPlayer.play()
        bgmPlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    }
}

// MARK: - Main App

@main
struct NekoPatisserieApp: App {
    var body: some Scene {
        WindowGroup {
            NekoKitchenView()
                .frame(minWidth: 940, minHeight: 670)
        }
    }
}

struct NekoKitchenView: View {
    @ObservedObject private var audio = NekoAudioEngine.shared

    @State private var score = 0
    @State private var combo = 0
    @State private var patience: Double = 100.0
    @State private var currentOrder: Recipe = Recipe.all[0]
    @State private var currentPlate: [Ingredient] = []
    @State private var chefMood = "Nya~! Ready to bake!"
    @State private var earTwitchImpulse: Double = 0
    @State private var headNodImpulse: Double = 0
    @State private var cheerTicks: Int = 0
    @State private var bgmOn = true
    @State private var voiceOn = true

    private let logicTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PinkPalette.bgPink.ignoresSafeArea()

            VStack(spacing: 12) {
                topHudBar
                HStack(spacing: 12) {
                    kitchenStage
                    orderTicketPanel
                }
                bottomIngredientBar
            }
            .padding(12)
        }
        .onAppear { pickNewOrder(announce: true) }
        .onReceive(logicTimer) { _ in
            patience = max(0, patience - 0.24)
            earTwitchImpulse *= 0.80
            headNodImpulse *= 0.78
            if cheerTicks > 0 { cheerTicks -= 1 }

            if patience <= 0 {
                combo = 0
                chefMood = "Customer left! New order up~"
                audio.playMissSFX()
                audio.speakJapanese("残念！次の注文だよ。", pitch: 1.38)
                currentPlate.removeAll()
                pickNewOrder(announce: false)
            }
        }
    }

    private var topHudBar: some View {
        HStack(spacing: 12) {
            Text("Neko Patisserie")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.deepBerry)

            Spacer()

            Button(action: {
                bgmOn.toggle()
                audio.bgmEnabled = bgmOn
            }) {
                Text(bgmOn ? "♪ Music: ON" : "♪ Music: OFF")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PinkPalette.deepBerry)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(PinkPalette.creamWhite).overlay(Capsule().stroke(PinkPalette.hotPink, lineWidth: 1.5)))
            }
            .buttonStyle(.plain)

            Button(action: {
                voiceOn.toggle()
                audio.voiceEnabled = voiceOn
            }) {
                Text(voiceOn ? "✿ JP Voice: ON" : "✿ JP Voice: OFF")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PinkPalette.hotPink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(PinkPalette.creamWhite).overlay(Capsule().stroke(PinkPalette.hotPink, lineWidth: 1.5)))
            }
            .buttonStyle(.plain)

            Text("Combo: x\(combo)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.hotPink)

            Text("Score: \(score)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.deepBerry)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(PinkPalette.panelPink)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinkPalette.hotPink, lineWidth: 2))
        )
    }

    // MARK: - 60fps Skeletal-Rigged Kitchen Stage

    private var kitchenStage: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    LinearGradient(
                        colors: [PinkPalette.bgPink, PinkPalette.stripePink],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack(spacing: 28) {
                        ForEach(0..<15, id: \.self) { _ in
                            Rectangle()
                                .fill(PinkPalette.panelPink.opacity(0.45))
                                .frame(width: 18)
                        }
                    }
                    .clipped()

                    // Momo (Left Articulated Cat-Ear Chef)
                    ArticulatedNekoChefRig(
                        prefix: "momo",
                        time: t,
                        phaseOffset: 0.0,
                        hairMain: Color(red: 1.0, green: 0.62, blue: 0.81),
                        hairShade: Color(red: 0.84, green: 0.30, blue: 0.58),
                        eyeIris: Color(red: 0.88, green: 0.16, blue: 0.48),
                        apronColor: Color(red: 1.0, green: 0.36, blue: 0.64),
                        earTwitch: earTwitchImpulse,
                        headNod: headNodImpulse,
                        isCheering: cheerTicks > 0,
                        isTalking: audio.isSpeaking && audio.activeSpeakerPitch > 1.32,
                        voicePitch: 1.38
                    )
                    .position(x: w * 0.27, y: h * 0.44)

                    // Sakura (Right Articulated Cat-Ear Chef)
                    ArticulatedNekoChefRig(
                        prefix: "sakura",
                        time: t,
                        phaseOffset: 1.7,
                        hairMain: Color(red: 1.0, green: 0.75, blue: 0.88),
                        hairShade: Color(red: 0.76, green: 0.24, blue: 0.50),
                        eyeIris: Color(red: 0.56, green: 0.14, blue: 0.40),
                        apronColor: Color(red: 0.92, green: 0.25, blue: 0.56),
                        earTwitch: -earTwitchImpulse * 0.8,
                        headNod: headNodImpulse,
                        isCheering: cheerTicks > 0,
                        isTalking: audio.isSpeaking && audio.activeSpeakerPitch <= 1.32,
                        voicePitch: 1.26
                    )
                    .position(x: w * 0.73, y: h * 0.44)

                    // Mood speech bubble
                    Text(chefMood)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PinkPalette.deepBerry)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(PinkPalette.creamWhite)
                                .overlay(Capsule().stroke(PinkPalette.hotPink, lineWidth: 2))
                        )
                        .position(x: w * 0.5, y: 34)

                    // Counter & Plate
                    VStack(spacing: 0) {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    LinearGradient(
                                        colors: [PinkPalette.counterPink, PinkPalette.hotPink.opacity(0.75)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(PinkPalette.hotPink, lineWidth: 3))
                                .frame(height: h * 0.32)

                            Ellipse()
                                .fill(PinkPalette.creamWhite)
                                .overlay(Ellipse().stroke(PinkPalette.hotPink, lineWidth: 3))
                                .frame(width: 184, height: 48)
                                .offset(y: -12)

                            ForEach(Array(currentPlate.enumerated()), id: \.offset) { index, ing in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ing.color)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(PinkPalette.deepBerry, lineWidth: 1.5))
                                    .frame(width: 78, height: 16)
                                    .offset(y: CGFloat(-22 - index * 14))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinkPalette.hotPink, lineWidth: 2))
    }

    // MARK: - Order Ticket Panel

    private var orderTicketPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Order")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.deepBerry)

            Text(currentOrder.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.hotPink)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(currentOrder.steps.enumerated()), id: \.offset) { idx, step in
                    Text("\(idx + 1). \(step.rawValue)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(PinkPalette.deepBerry)
                }
            }
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("Customer Patience")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PinkPalette.deepBerry)

                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PinkPalette.panelPink)
                        Capsule()
                            .fill(PinkPalette.hotPink)
                            .frame(width: max(0, barGeo.size.width * CGFloat(patience / 100.0)))
                    }
                }
                .frame(height: 14)
            }
            .padding(.bottom, 10)

            Text("On Your Plate:")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PinkPalette.deepBerry)

            if currentPlate.isEmpty {
                Text("(Empty)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(PinkPalette.deepBerry.opacity(0.75))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(currentPlate.enumerated()), id: \.offset) { _, item in
                        Text("• \(item.rawValue)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(PinkPalette.deepBerry)
                    }
                }
            }

            Spacer()

            Button(action: serveOrder) {
                Text("Serve Order!")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(PinkPalette.hotPink))
            }
            .buttonStyle(.plain)

            Button(action: { clearPlate("Plate cleared, nya!") }) {
                Text("Clear Plate")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PinkPalette.deepBerry)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(PinkPalette.panelPink)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(PinkPalette.hotPink, lineWidth: 1.5))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(PinkPalette.creamWhite)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinkPalette.hotPink, lineWidth: 2))
        )
    }

    private var bottomIngredientBar: some View {
        HStack(spacing: 12) {
            ForEach(Ingredient.allCases) { ing in
                Button(action: { addIngredient(ing) }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ing.color)
                            .overlay(Circle().stroke(PinkPalette.deepBerry, lineWidth: 1.5))
                            .frame(width: 14, height: 14)
                        Text("+ \(ing.rawValue)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(PinkPalette.deepBerry)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(PinkPalette.creamWhite)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(PinkPalette.hotPink, lineWidth: 2))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(PinkPalette.panelPink)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinkPalette.hotPink, lineWidth: 2))
        )
    }

    private func pickNewOrder(announce: Bool) {
        currentOrder = Recipe.all.randomElement() ?? Recipe.all[0]
        patience = 100.0
        if announce {
            audio.speakJapanese("いらっしゃいませ！甘いにゃんこスイーツはいかが？", pitch: 1.38)
        }
    }

    private func addIngredient(_ ing: Ingredient) {
        guard currentPlate.count < 4 else {
            chefMood = "Plate is full, nya~!"
            audio.speakJapanese("お皿がいっぱいだよ、にゃ～！", pitch: 1.38)
            return
        }
        currentPlate.append(ing)
        chefMood = "Added \(ing.rawValue)!"
        earTwitchImpulse = 18.0
        headNodImpulse = 6.0
        audio.playPopSFX()

        switch ing {
        case .mochi: audio.speakJapanese("もちもちピンクもち！", pitch: 1.38)
        case .strawberry: audio.speakJapanese("甘いいちご、にゃん！", pitch: 1.26)
        case .cream: audio.speakJapanese("ふわふわホイップクリーム！", pitch: 1.38)
        case .sakura: audio.speakJapanese("さくらグレーズでかわいく！", pitch: 1.26)
        }
    }

    private func clearPlate(_ message: String) {
        currentPlate.removeAll()
        chefMood = message
        earTwitchImpulse = -12.0
        audio.playPopSFX()
        audio.speakJapanese("お皿をきれいにしたよ！", pitch: 1.26)
    }

    private func serveOrder() {
        if currentPlate == currentOrder.steps {
            combo += 1
            let earned = 100 + Int(patience * 0.5) + combo * 25
            score += earned
            chefMood = "Purr-fect! +\(earned) pts!"
            cheerTicks = 45
            earTwitchImpulse = 24.0
            headNodImpulse = 10.0
            audio.playSuccessSFX()
            audio.speakJapanese("できました！とってもおいしそう、にゃ～！", pitch: 1.38)
            currentPlate.removeAll()
            pickNewOrder(announce: false)
        } else {
            combo = 0
            chefMood = "Oops! Check the recipe order, nya!"
            earTwitchImpulse = -16.0
            audio.playMissSFX()
            audio.speakJapanese("あらら、レシピをもういちど見てね！", pitch: 1.26)
            currentPlate.removeAll()
        }
    }
}

// MARK: - Multi-Bone Articulated Anime Rig (60fps Hierarchical Motion)

private struct ArticulatedNekoChefRig: View {
    let prefix: String
    let time: TimeInterval
    let phaseOffset: Double
    let hairMain: Color
    let hairShade: Color
    let eyeIris: Color
    let apronColor: Color
    let earTwitch: Double
    let headNod: Double
    let isCheering: Bool
    let isTalking: Bool
    let voicePitch: Float

    var body: some View {
        let t = time + phaseOffset
        let torsoBreathY = sin(t * 2.4) * 3.0
        let torsoSwayDeg = sin(t * 1.6) * 2.2
        let headTiltDeg = sin(t * 1.6 - 0.55) * 4.2 + (isCheering ? sin(t * 14.0) * 5.0 : 0)
        let headNodY = cos(t * 2.4 - 0.4) * 2.5 + headNod
        let backHairSwayDeg = sin(t * 1.6 - 1.1) * 5.5
        let earSpringDeg = sin(t * 3.2 - 0.7) * 4.5 + earTwitch

        let blinkCycle = t.truncatingRemainder(dividingBy: 3.8)
        let eyeOpenAmount: CGFloat = (blinkCycle > 3.62 && blinkCycle < 3.76) ? 0.08 : 1.0
        let mouthOpen: CGFloat = isTalking ? CGFloat(0.25 + 0.75 * abs(sin(t * 18.0))) : 0.0

        ZStack {
            // 1. Back Hair Bone
            Group {
                if let img = RigPartLoader.loadPart("\(prefix)_hair_back") {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 150, height: 150)
                } else {
                    ZStack {
                        Ellipse()
                            .fill(LinearGradient(colors: [hairMain, hairShade], startPoint: .top, endPoint: .bottom))
                            .overlay(Ellipse().stroke(PinkPalette.deepBerry, lineWidth: 2))
                            .frame(width: 126, height: 122)
                        Capsule()
                            .fill(LinearGradient(colors: [hairMain, hairShade], startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                            .frame(width: 28, height: 88)
                            .rotationEffect(.degrees(12))
                            .offset(x: -52, y: 36)
                        Capsule()
                            .fill(LinearGradient(colors: [hairMain, hairShade], startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                            .frame(width: 28, height: 88)
                            .rotationEffect(.degrees(-12))
                            .offset(x: 52, y: 36)
                    }
                }
            }
            .rotationEffect(.degrees(backHairSwayDeg), anchor: .top)
            .offset(y: 18 + torsoBreathY)

            // 2. Torso & Arms Bone
            Group {
                if let img = RigPartLoader.loadPart("\(prefix)_body") {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 130, height: 110)
                } else {
                    ZStack {
                        Capsule()
                            .fill(PinkPalette.skinLight)
                            .overlay(Capsule().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                            .frame(width: 20, height: 52)
                            .rotationEffect(.degrees(isCheering ? 135 : 28 + sin(t * 3.0) * 8), anchor: .top)
                            .offset(x: -44, y: 54)

                        Capsule()
                            .fill(PinkPalette.skinLight)
                            .overlay(Capsule().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                            .frame(width: 20, height: 52)
                            .rotationEffect(.degrees(isCheering ? -135 : -28 - sin(t * 3.0) * 8), anchor: .top)
                            .offset(x: 44, y: 54)

                        Ellipse()
                            .fill(PinkPalette.creamWhite)
                            .overlay(Ellipse().stroke(PinkPalette.deepBerry, lineWidth: 2))
                            .frame(width: 96, height: 86)
                            .offset(y: 74)

                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [apronColor, hairShade], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PinkPalette.deepBerry, lineWidth: 2))
                            .frame(width: 64, height: 54)
                            .offset(y: 78)
                    }
                }
            }
            .rotationEffect(.degrees(torsoSwayDeg), anchor: .bottom)
            .offset(y: torsoBreathY)

            // 3. Head + Face + Independent Cat Ears Bone
            ZStack {
                catEarView(isLeft: true)
                    .rotationEffect(.degrees(-18 - earSpringDeg), anchor: .bottom)
                    .offset(x: -34, y: -46)

                catEarView(isLeft: false)
                    .rotationEffect(.degrees(18 + earSpringDeg), anchor: .bottom)
                    .offset(x: 34, y: -46)

                if let img = RigPartLoader.loadPart("\(prefix)_head") {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 110, height: 110)
                } else {
                    Ellipse()
                        .fill(LinearGradient(colors: [PinkPalette.skinLight, PinkPalette.skinShadow], startPoint: .top, endPoint: .bottom))
                        .overlay(Ellipse().stroke(PinkPalette.deepBerry, lineWidth: 2))
                        .frame(width: 92, height: 82)
                }

                HStack(spacing: 18) {
                    articulatedEye(openAmount: eyeOpenAmount)
                    articulatedEye(openAmount: eyeOpenAmount)
                }
                .offset(y: -2)

                Ellipse().fill(PinkPalette.blushPink.opacity(0.65)).frame(width: 16, height: 8).offset(x: -28, y: 11)
                Ellipse().fill(PinkPalette.blushPink.opacity(0.65)).frame(width: 16, height: 8).offset(x: 28, y: 11)

                if mouthOpen > 0.12 {
                    Ellipse()
                        .fill(PinkPalette.hotPink)
                        .overlay(Ellipse().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                        .frame(width: 14, height: 4 + 10 * mouthOpen)
                        .offset(y: 13)
                } else {
                    HStack(spacing: 0) {
                        NekoSmileArc().stroke(PinkPalette.deepBerry, lineWidth: 2).frame(width: 9, height: 8)
                        NekoSmileArc().stroke(PinkPalette.deepBerry, lineWidth: 2).frame(width: 9, height: 8)
                    }
                    .offset(y: 12)
                }

                HStack(spacing: -4) {
                    Capsule().fill(hairMain).frame(width: 24, height: 22).rotationEffect(.degrees(18))
                    Capsule().fill(hairMain).frame(width: 26, height: 24).rotationEffect(.degrees(-8))
                    Capsule().fill(hairMain).frame(width: 26, height: 24).rotationEffect(.degrees(8))
                    Capsule().fill(hairMain).frame(width: 24, height: 22).rotationEffect(.degrees(-18))
                }
                .rotationEffect(.degrees(headTiltDeg * 0.35))
                .offset(y: -30)

                VStack(spacing: -3) {
                    Capsule()
                        .fill(PinkPalette.creamWhite)
                        .overlay(Capsule().stroke(PinkPalette.deepBerry, lineWidth: 1.8))
                        .frame(width: 48, height: 22)
                    Rectangle()
                        .fill(PinkPalette.hotPink)
                        .overlay(Rectangle().stroke(PinkPalette.deepBerry, lineWidth: 1.5))
                        .frame(width: 34, height: 9)
                }
                .offset(y: -58)
            }
            .rotationEffect(.degrees(headTiltDeg), anchor: .bottom)
            .offset(y: torsoBreathY + headNodY)
        }
        .onTapGesture {
            NekoAudioEngine.shared.playPopSFX()
            NekoAudioEngine.shared.speakJapanese("にゃ～！いっしょに作ろうね！", pitch: voicePitch)
        }
    }

    @ViewBuilder
    private func catEarView(isLeft: Bool) -> some View {
        let partName = isLeft ? "\(prefix)_ear_l" : "\(prefix)_ear_r"
        if let img = RigPartLoader.loadPart(partName) {
            Image(nsImage: img).resizable().scaledToFit().frame(width: 42, height: 46)
        } else {
            ZStack {
                CatEarShape()
                    .fill(LinearGradient(colors: [hairMain, hairShade], startPoint: .top, endPoint: .bottom))
                    .overlay(CatEarShape().stroke(PinkPalette.deepBerry, lineWidth: 2))
                    .frame(width: 38, height: 42)
                CatEarShape()
                    .fill(PinkPalette.blushPink)
                    .frame(width: 20, height: 24)
                    .offset(y: 5)
            }
        }
    }

    private func articulatedEye(openAmount: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [eyeIris.opacity(0.75), eyeIris, PinkPalette.deepBerry], startPoint: .top, endPoint: .bottom))
                .frame(width: 14, height: 17)
            Ellipse()
                .fill(PinkPalette.deepBerry)
                .frame(width: 6, height: 8)
                .offset(y: 1)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .offset(x: -3, y: -4)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2.5, height: 2.5)
                .offset(x: 3, y: 2)
        }
        .scaleEffect(y: openAmount, anchor: .center)
        .overlay(
            Capsule()
                .fill(PinkPalette.deepBerry)
                .frame(width: 16, height: 3)
                .offset(y: -7 * openAmount)
        )
        .frame(width: 16, height: 18)
    }
}

private struct CatEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct NekoSmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        return path
    }
}

