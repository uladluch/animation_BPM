//
//  ContentView.swift
//  BPM Animation
//
//  Created by Ulad Luch on 18/08/2026.
//

import SwiftUI
import AudioToolbox
import UIKit

/// Одна волна из точек, расходящаяся от места касания
private struct Ripple: Identifiable {
    let id = UUID()
    let center: CGPoint
    let startDate: Date
}

/// Музыкальный размер: определяет число долей на орбите метронома,
/// акцентные доли и плотность делений между кругами
enum TimeSignature: String, CaseIterable, Identifiable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case twoFour = "2/4"
    case sixEight = "6/8"
    case twelveEight = "12/8"

    var id: String { rawValue }

    /// Число долей в такте — столько кругов на орбите
    var beatsPerBar: Int {
        switch self {
        case .fourFour: 4
        case .threeFour: 3
        case .twoFour: 2
        case .sixEight: 6
        case .twelveEight: 12
        }
    }

    /// Сильные доли (с нуля): в простых размерах — первая,
    /// в составных — начало каждой группы восьмых
    var accentBeats: Set<Int> {
        switch self {
        case .fourFour, .threeFour, .twoFour: [0]
        case .sixEight: [0, 3]
        case .twelveEight: [0, 3, 6, 9]
        }
    }

    /// Кружков-делений между соседними долями
    var ticksPerGap: Int {
        switch self {
        case .fourFour, .threeFour, .twoFour: 3
        case .sixEight: 2
        case .twelveEight: 1
        }
    }
}

struct ContentView: View {
    /// Пользователь предпочитает уменьшенное движение — заменяем волну и масштабы фейдами
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Текущее (последнее вычисленное) значение BPM
    @State private var bpm = 119
    /// Время каждого тапа в текущей сессии настукивания
    @State private var tapTimes: [Date] = []
    /// Прозрачность бордера: 0 — скрыт, 1 — виден; «дышит» после фиксации ритма
    @State private var strokeOpacity: Double = 0
    /// Отложенная задача завершения сессии (сбрасывается каждым новым тапом)
    @State private var sessionEndTask: Task<Void, Never>?
    /// Задача «дыхания» бордера после фиксации ритма
    @State private var breatheTask: Task<Void, Never>?
    /// Активные волны из точек
    @State private var ripples: [Ripple] = []
    /// Время запуска последней волны — чтобы не стробить при быстром ритме
    @State private var lastRippleDate: Date?
    /// Счётчик тапов — триггер тактильного отклика
    @State private var tapCount = 0
    /// Счётчик пробуждений — триггер хаптика пробуждения
    @State private var wakeCount = 0
    /// Счётчик фиксаций ритма — триггер финального хаптика и settle-анимации цифры
    @State private var lockCount = 0
    /// Палец сейчас прижат к компоненту
    @State private var isPressed = false
    /// Компонент «разбужен» первым тапом: рамка видна, ждём настукивания
    @State private var isAwake = false
    /// Ритм зафиксирован, рамка ещё «дышит» и догорает
    @State private var isSettling = false
    /// Фокус-режим: чёрный экран, звучит только метроном
    @State private var isFocusMode = false
    /// Задача-цикл метронома
    @State private var metronomeTask: Task<Void, Never>?
    /// Момент старта метронома — от него считаются и звук, и анимация маятника
    @State private var metronomeStartDate: Date?
    /// Подсказка о выходе из фокус-режима (показывается по тапу)
    @State private var showExitHint = false
    /// Задача скрытия подсказки
    @State private var exitHintTask: Task<Void, Never>?
    /// Прогресс удержания для выхода из фокус-режима (0…1):
    /// пока палец держит — экран темнеет и метроном сжимается
    @State private var exitHoldProgress: Double = 0
    /// Выбранный музыкальный размер
    @State private var timeSignature: TimeSignature = .fourFour

    /// Пауза, после которой считаем, что пользователь закончил настукивать
    private let sessionTimeout: TimeInterval = 2.0
    /// Максимальный BPM, который можно настучать
    private let maxBPM = 360

    // Параметры волны из точек
    private let dotSpacing: CGFloat = 13           // шаг сетки точек
    private let rippleDuration: TimeInterval = 1.4 // время жизни волны
    private let rippleBandWidth: Double = 38       // ширина светящегося фронта
    private let rippleMinInterval: TimeInterval = 0.3 // не чаще одной волны в 0.3с

    /// true, пока показываем прочерки первых трёх тапов
    private var isCountingIn: Bool {
        !tapTimes.isEmpty && tapTimes.count < 4
    }

    /// Подпись под цифрой: название темпа показываем только когда рамка полностью
    /// пропала; пока тапаем или рамка дышит — подсказки
    private var hintText: String {
        if !tapTimes.isEmpty || isSettling { return "A few more taps" }
        if isAwake { return "Tap the BPM" }
        return tempoMarking
    }

    /// Классическое музыкальное обозначение темпа для текущего BPM
    private var tempoMarking: String {
        switch bpm {
        case ..<40: "grave"
        case 40..<60: "largo"
        case 60..<66: "larghetto"
        case 66..<76: "adagio"
        case 76..<108: "andante"
        case 108..<116: "moderato"
        case 116..<168: "allegro"
        case 168..<200: "presto"
        default: "prestissimo"
        }
    }

    var body: some View {
        ZStack {
            if isFocusMode {
                // Фокус-режим: чёрный экран и круговой метроном.
                // Тап показывает подсказку, долгое нажатие — выход.
                ZStack {
                    // Полотно метронома игнорирует safe area целиком, снаружи
                    // от scaleEffect — иначе трансформация вызывает пересчёт
                    // safe area и контент прыгает
                    ZStack {
                        Color.black
                        // Вспышка — отдельный слой: не сжимается при удержании
                        MetronomeFlashView(
                            startDate: metronomeStartDate ?? Date(),
                            bpm: bpm,
                            signature: timeSignature
                        )
                        MetronomePendulumView(
                            startDate: metronomeStartDate ?? Date(),
                            bpm: bpm,
                            signature: timeSignature
                        )
                        // Хореография выхода: пока палец держит, метроном сжимается
                        // и темнеет; отпустил раньше — упруго возвращается
                        .scaleEffect(1 - 0.12 * exitHoldProgress)
                        .opacity(1 - 0.55 * exitHoldProgress)
                    }
                    .ignoresSafeArea()
                    VStack {
                        Spacer()
                        Text("Touch and hold to exit")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.bottom, 24)
                            .opacity(showExitHint || exitHoldProgress > 0.1 ? 1 : 0)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showExitHintBriefly()
                }
                .onLongPressGesture(minimumDuration: 0.9) {
                    exitFocusMode()
                } onPressingChanged: { pressing in
                    if pressing {
                        withAnimation(.linear(duration: 0.9)) {
                            exitHoldProgress = 1
                        }
                    } else if isFocusMode {
                        // Отпустил раньше времени — отпружиниваем обратно
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                            exitHoldProgress = 0
                        }
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 48) {
                    bpmBlock

                    VStack(spacing: 16) {
                        // Выбор размера — нативное системное меню
                        Menu {
                            Picker("Time Signature", selection: $timeSignature) {
                                ForEach(TimeSignature.allCases) { signature in
                                    Text(signature.rawValue).tag(signature)
                                }
                            }
                        } label: {
                            Text(timeSignature.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.glass(.clear))

                        // Системная кнопка в прозрачном Liquid Glass
                        Button {
                            enterFocusMode()
                        } label: {
                            Text("Focus Mode")
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.glass(.clear))
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden(isFocusMode)
        // Тактильная точка входа и выхода из фокус-режима
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.8), trigger: isFocusMode)
    }

    /// Входим в фокус-режим: прячем интерфейс и запускаем метроном
    private func enterFocusMode() {
        sessionEndTask?.cancel()
        breatheTask?.cancel()
        // Экран не должен гаснуть посреди практики
        UIApplication.shared.isIdleTimerDisabled = true
        withAnimation(.smooth(duration: 0.5)) {
            isFocusMode = true
            // Сбрасываем визуальные состояния компонента, чтобы после выхода он был «спящим»
            tapTimes = []
            isAwake = false
            isSettling = false
            strokeOpacity = 0
        }
        startMetronome()
    }

    /// По тапу ненадолго показываем подсказку о выходе
    private func showExitHintBriefly() {
        exitHintTask?.cancel()
        withAnimation(.smooth(duration: 0.3)) {
            showExitHint = true
        }
        exitHintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.6)) {
                showExitHint = false
            }
        }
    }

    /// Выходим из фокус-режима: останавливаем метроном и возвращаем интерфейс
    private func exitFocusMode() {
        metronomeTask?.cancel()
        metronomeTask = nil
        metronomeStartDate = nil
        exitHintTask?.cancel()
        showExitHint = false
        UIApplication.shared.isIdleTimerDisabled = false
        withAnimation(.smooth(duration: 0.5)) {
            isFocusMode = false
        }
        exitHoldProgress = 0
    }

    /// Метроном: системный щелчок в темпе пользователя.
    /// Каждый следующий удар планируем от точки старта — без накопления дрейфа.
    private func startMetronome() {
        metronomeTask?.cancel()
        let start = Date()
        metronomeStartDate = start
        metronomeTask = Task {
            let interval = 60.0 / Double(bpm)
            var beat = 0
            // Точка стартует с верхнего боба — щелчки на целых тактах,
            // в моменты касания бобов
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(1104) // системный «Tock»
                beat += 1
                let next = start.addingTimeInterval(Double(beat) * interval)
                let delay = next.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    /// Основной интерактивный блок с цифрой и подсказкой
    private var bpmBlock: some View {
        VStack(spacing: 0) {
            ZStack {
                if isCountingIn {
                    // Прочерки первых трёх тапов
                    Text(String(repeating: "-", count: tapTimes.count))
                        .contentTransition(.opacity)
                        .transition(.blurReplace)
                } else {
                    // Цифры перекатываются вверх/вниз, как в системном Таймере
                    Text("\(bpm)")
                        .contentTransition(.numericText(value: Double(bpm)))
                        .transition(.blurReplace)
                }
            }
            .font(.system(size: 130))
            .foregroundStyle(.primary)
            .frame(height: 154)
            // Момент фиксации ритма: цифра делает едва заметный «кивок» и упруго оседает
            .phaseAnimator([1.0, 1.02], trigger: lockCount) { view, scale in
                view.scaleEffect(reduceMotion ? 1.0 : scale)
            } animation: { scale in
                scale > 1.0
                    ? .smooth(duration: 0.15)
                    : .spring(duration: 0.45, bounce: 0.35)
            }

            Text(hintText)
                .textCase(.uppercase)
                .contentTransition(.opacity)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(width: 349, height: 172)
        .background {
            dotWave
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0.0),
                            .init(color: .white.opacity(0.0), location: 0.2),
                            .init(color: .white.opacity(0.0), location: 0.8),
                            .init(color: .white.opacity(0.55), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .opacity(strokeOpacity)
        }
        .contentShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        // Тап регистрируем в момент касания (а не отпускания) — точнее темп,
        // мгновеннее отклик; заодно отслеживаем прижатый палец
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard !isPressed else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        isPressed = true
                    }
                    registerTap(at: value.startLocation)
                }
                .onEnded { _ in
                    withAnimation(.snappy(duration: 0.18)) {
                        isPressed = false
                    }
                }
        )
        // Компонент едва заметно поджимается под пальцем, как физическая кнопка
        .scaleEffect(reduceMotion || !isPressed ? 1.0 : 0.985)
        // …и мягко «раздувается» при взаимодействии — следует за прозрачностью бордера
        .scaleEffect(reduceMotion ? 1.0 : 1.0 + 0.03 * strokeOpacity)
        // Мягкий тактильный отклик на каждый тап
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: tapCount)
        // Более ощутимый хаптик пробуждения — компонент «ожил»
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.9), trigger: wakeCount)
        // Отдельный хаптик «значение принято» в момент фиксации ритма
        .sensoryFeedback(.success, trigger: lockCount)
    }

    /// Сетка точек, по которой от места касания расходится мягкая волна
    private var dotWave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: ripples.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date

                // Центрируем сетку внутри блока
                let cols = Int(size.width / dotSpacing)
                let rows = Int(size.height / dotSpacing)
                let xInset = (size.width - CGFloat(cols - 1) * dotSpacing) / 2
                let yInset = (size.height - CGFloat(rows - 1) * dotSpacing) / 2

                // Волна всегда доплывает до самого дальнего угла от точки тапа —
                // на краях и в углах ведёт себя так же естественно, как в центре
                let maxRadii = ripples.map { ripple in
                    let farX = max(ripple.center.x, size.width - ripple.center.x)
                    let farY = max(ripple.center.y, size.height - ripple.center.y)
                    return hypot(farX, farY) + rippleBandWidth
                }

                for row in 0..<rows {
                    for col in 0..<cols {
                        let point = CGPoint(
                            x: xInset + CGFloat(col) * dotSpacing,
                            y: yInset + CGFloat(row) * dotSpacing
                        )

                        // Яркость точки — максимум по всем активным волнам;
                        // сильнейшая волна ещё и слегка сдвигает точку наружу
                        var intensity: Double = 0
                        var pushX: Double = 0
                        var pushY: Double = 0
                        for (index, ripple) in ripples.enumerated() {
                            let t = now.timeIntervalSince(ripple.startDate)
                            guard t >= 0, t < rippleDuration else { continue }

                            let distance = hypot(point.x - ripple.center.x, point.y - ripple.center.y)
                            // Фронт расширяется с замедлением (easeOut) — быстро под пальцем,
                            // мягко доплывает до краёв
                            let progress = t / rippleDuration
                            let waveRadius = maxRadii[index] * (1 - pow(1 - progress, 2.2))
                            // Гауссов фронт: точка светится, когда волна проходит через неё.
                            // Внутренний хвост шире внешнего — точки позади фронта гаснут
                            // медленнее, поэтому тёмный круг в центре заметно меньше
                            let delta = distance - waveRadius
                            let width = delta < 0 ? rippleBandWidth * 1.8 : rippleBandWidth
                            let band = exp(-pow(delta / width, 2))
                            // Плавное общее затухание волны со временем
                            let fade = pow(1 - progress, 1.2)
                            let contribution = band * fade

                            if contribution > intensity {
                                intensity = contribution
                                // Рябь на воде: фронт смещает точку от центра волны
                                if distance > 0.001 {
                                    let push = 4.0 * contribution
                                    pushX = (point.x - ripple.center.x) / distance * push
                                    pushY = (point.y - ripple.center.y) / distance * push
                                }
                            }
                        }

                        guard intensity > 0.02 else { continue }

                        // Точка деликатно увеличивается на пике волны
                        let radius = 0.85 + 0.65 * intensity
                        let rect = CGRect(
                            x: point.x + pushX - radius, y: point.y + pushY - radius,
                            width: radius * 2, height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(0.38 * intensity))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Регистрирует тап: первый тап пробуждает компонент,
    /// дальше — волны, прочерки и подсчёт BPM
    private func registerTap(at location: CGPoint) {
        sessionEndTask?.cancel()
        breatheTask?.cancel()

        // Первый тап только «будит» компонент: появляется рамка,
        // подпись меняется на приглашение — без волн и прочерков
        if !isAwake {
            wakeCount += 1
            withAnimation(.smooth(duration: 0.35)) {
                isAwake = true
                isSettling = false
                strokeOpacity = 1
            }
            scheduleSessionEnd()
            return
        }

        tapCount += 1

        // Пружинная анимация: прочерки материализуются через blur,
        // цифры перекатываются numericText-переходом
        withAnimation(.smooth(duration: 0.25)) {
            tapTimes.append(Date())
            if tapTimes.count >= 4 {
                bpm = computedBPM()
            }
        }

        // Волна из точек рождается под пальцем.
        // При быстром ритме (вплоть до 360 BPM) волны запускаем не на каждый тап,
        // а не чаще rippleMinInterval — иначе анимация стробит.
        // При включённом Reduce Motion волну не показываем вовсе.
        if !reduceMotion {
            let now = Date()
            if lastRippleDate.map({ now.timeIntervalSince($0) >= rippleMinInterval }) ?? true {
                lastRippleDate = now
                let ripple = Ripple(center: location, startDate: now)
                ripples.append(ripple)
                Task {
                    try? await Task.sleep(for: .seconds(rippleDuration))
                    ripples.removeAll { $0.id == ripple.id }
                }
            }
        }

        // Подсветка возвращается к полной яркости (могла притухнуть при дыхании)
        withAnimation(.smooth(duration: 0.35)) {
            strokeOpacity = 1
        }

        scheduleSessionEnd()
    }

    /// Перезапускает таймер завершения сессии
    private func scheduleSessionEnd() {
        sessionEndTask = Task {
            try? await Task.sleep(for: .seconds(sessionTimeout))
            guard !Task.isCancelled else { return }
            endSession()
        }
    }

    /// Пользователь перестал настукивать: фиксируем ритм.
    /// Бордер пару раз «вздыхает» в настуканном темпе и мягко гаснет.
    private func endSession() {
        let locked = tapTimes.count >= 4
        withAnimation(.smooth(duration: 0.3)) {
            tapTimes = []
            isAwake = false
        }

        guard locked else {
            withAnimation(.smooth(duration: 0.45)) {
                strokeOpacity = 0
            }
            return
        }

        // Момент фиксации: settle-кивок цифры + success-хаптик
        lockCount += 1
        isSettling = true

        breatheTask = Task {
            // Дыхание в настуканном темпе (в разумных пределах)
            let beat = min(max(60.0 / Double(bpm), 0.25), 1.0)
            for _ in 0..<2 {
                withAnimation(.smooth(duration: beat * 0.45)) { strokeOpacity = 0.35 }
                try? await Task.sleep(for: .seconds(beat * 0.5))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: beat * 0.45)) { strokeOpacity = 1.0 }
                try? await Task.sleep(for: .seconds(beat * 0.5))
                guard !Task.isCancelled else { return }
            }
            // Рамка пропадает — и только теперь подпись меняется на название темпа
            withAnimation(.smooth(duration: 0.5)) {
                strokeOpacity = 0
                isSettling = false
            }
        }
    }

    /// BPM по среднему интервалу между тапами текущей сессии
    private func computedBPM() -> Int {
        guard tapTimes.count >= 2 else { return bpm }
        let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return bpm }
        return min(Int((60.0 / average).rounded()), maxBPM)
    }
}

/// Полноэкранная вспышка удара — отдельный слой, чтобы не сжиматься вместе
/// с метрономом при удержании для выхода. Свет расходится радиально от круга,
/// в который только что ударила точка; сильная доля ярче. На быстрых темпах
/// и при Reduce Motion / Dim Flashing Lights приглушается.
private struct MetronomeFlashView: View {
    let startDate: Date
    let bpm: Int
    let signature: TimeSignature

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights

    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let interval = 60.0 / Double(max(bpm, 1))
                let t = max(0, timeline.date.timeIntervalSince(startDate))
                let sinceHit = t.truncatingRemainder(dividingBy: interval)
                let beatIndex = Int(t / interval)

                // Та же геометрия, что у метронома — вспышка исходит из круга удара
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 42
                let beats = signature.beatsPerBar
                let currentBeat = beatIndex % beats
                let beatAngle = -Double.pi / 2 + Double(currentBeat) * 2 * .pi / Double(beats)
                let hitCenter = CGPoint(
                    x: center.x + radius * CGFloat(cos(beatAngle)),
                    y: center.y + radius * CGFloat(sin(beatAngle))
                )

                let isAccentHit = signature.accentBeats.contains(currentBeat)
                let tempoDim = 0.35 + 0.65 * min(1, interval / 0.5)
                let calmFactor = (reduceMotion || dimFlashingLights) ? 0.12 : 1.0
                // Нежный световой «выдох»: невысокий пик и плавное затухание
                let flashPeak = (isAccentHit ? 0.32 : 0.18) * tempoDim * calmFactor
                let flash = flashPeak * exp(-sinceHit / 0.16) * smooth(t / 0.4)
                if flash > 0.01 {
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            Gradient(colors: [
                                .white.opacity(flash),
                                .white.opacity(flash * 0.2)
                            ]),
                            center: hitCenter,
                            startRadius: 0,
                            endRadius: max(size.width, size.height) * 0.9
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Метроном фокус-режима: контурные круги долей такта на орбите (по числу долей
/// выбранного размера), светящаяся точка бегает по кругу, вливаясь в очередной
/// круг на каждый удар. Сильные доли — акцентные круги.
///
/// Живая хореография в стиле Apple:
/// — материализация элементов при входе (каскадное появление),
/// — squash & stretch точки в полёте (вытягивается по ходу движения),
/// — отклик круга на удар: пружинный пульс + расходящаяся ударная волна,
/// — комета-шлейф за точкой на скорости,
/// — свечение «дышит» в ритм, сильная доля ярче.
private struct MetronomePendulumView: View {
    let startDate: Date
    let bpm: Int
    let signature: TimeSignature

    /// Доступность: убираем стробирующие и «летающие» эффекты
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Плавная S-кривая (smoothstep) для появлений
    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                    let interval = 60.0 / Double(max(bpm, 1))
                    let t = max(0, timeline.date.timeIntervalSince(startDate))
                    let sinceHit = t.truncatingRemainder(dividingBy: interval)

                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 42

                    // Геометрия размера: доли такта — круги на орбите,
                    // сильные доли акцентные (крупнее)
                    let beats = signature.beatsPerBar
                    let accents = signature.accentBeats
                    let anglePerBeat = 2 * Double.pi / Double(beats)
                    let beanRadii: [CGFloat] = (0..<beats).map { accents.contains($0) ? 19 : 16 }
                    let beanAngles: [Double] = (0..<beats).map { -Double.pi / 2 + Double($0) * anglePerBeat }
                    let beanCenters: [CGPoint] = beanAngles.map {
                        CGPoint(
                            x: center.x + radius * CGFloat(cos($0)),
                            y: center.y + radius * CGFloat(sin($0))
                        )
                    }

                    // Точка бежит по кругу: одна дуга между долями за удар,
                    // старт с верхнего круга, у кругов замедляется
                    let beatIndex = Int(t / interval)
                    let phase = (t - Double(beatIndex) * interval) / interval
                    let eased = 0.5 - 0.5 * cos(.pi * phase)
                    let angle = -Double.pi / 2 + (Double(beatIndex) + eased) * anglePerBeat
                    // Мгновенная скорость (0 у кругов, максимум на середине дуги)
                    let speed = sin(.pi * phase)
                    let dotPos = CGPoint(
                        x: center.x + radius * CGFloat(cos(angle)),
                        y: center.y + radius * CGFloat(sin(angle))
                    )

                    // Кружки-деления между долями; плотность зависит от размера.
                    // Подсвечиваются и подрастают, когда точка пролетает мимо.
                    let slotsPerGap = signature.ticksPerGap + 1
                    let tickSlots = beats * slotsPerGap
                    let orbitAppear = smooth((t - 0.2) / 0.5)
                    if orbitAppear > 0.001 {
                        for tick in 0..<tickSlots where tick % slotsPerGap != 0 {
                            let tickAngle = -Double.pi / 2 + Double(tick) * 2 * .pi / Double(tickSlots)
                            let tickPos = CGPoint(
                                x: center.x + radius * CGFloat(cos(tickAngle)),
                                y: center.y + radius * CGFloat(sin(tickAngle))
                            )
                            let tickDistance = hypot(dotPos.x - tickPos.x, dotPos.y - tickPos.y)
                            let glow = max(0, 1 - tickDistance / 34)
                            // «Вселение»: когда точка ныряет внутрь, кружок раздувается,
                            // принимая её свет, и сдувается, когда она выпрыгивает
                            let swallow = max(0, 1 - tickDistance / 26)
                            let tickRadius = (2 + 1.2 * glow + 5.5 * swallow * swallow) * orbitAppear
                            let tickRect = CGRect(
                                x: tickPos.x - tickRadius, y: tickPos.y - tickRadius,
                                width: tickRadius * 2, height: tickRadius * 2
                            )
                            context.fill(
                                Path(ellipseIn: tickRect),
                                with: .color(.white.opacity(
                                    min(0.95, 0.18 + 0.5 * glow + 0.35 * swallow) * orbitAppear
                                ))
                            )
                        }
                    }

                    let meltRange: CGFloat = 60

                    // Круги: каскадная материализация, налив при подъезде точки,
                    // пружинный пульс и ударная волна в момент попадания
                    var nearestIndex = 0
                    var nearestDistance = CGFloat.infinity
                    for index in 0..<beats {
                        let beanCenter = beanCenters[index]
                        let distance = hypot(dotPos.x - beanCenter.x, dotPos.y - beanCenter.y)
                        if distance < nearestDistance {
                            nearestDistance = distance
                            nearestIndex = index
                        }

                        // Появление с каскадной задержкой по часовой стрелке
                        let appear = smooth((t - 0.07 * Double(index)) / 0.5)
                        guard appear > 0.001 else { continue }

                        // Последний удар по этому кругу (круг index бьётся на долях index, index+beats, ...)
                        let beatsSinceOwnHit = ((beatIndex - index) % beats + beats) % beats
                        let lastOwnHitBeat = beatIndex - beatsSinceOwnHit
                        let sinceOwnHit = t - Double(lastOwnHitBeat) * interval
                        let wasHit = lastOwnHitBeat >= 0
                        // Пружинный пульс: подскок и затухающее колебание
                        let pulse = wasHit
                            ? exp(-sinceOwnHit / 0.16) * cos(sinceOwnHit * 18) * 0.14
                            : 0

                        let beanRadius = beanRadii[index] * CGFloat(appear * (1 + pulse))
                        let proximity = max(0, 1 - distance / meltRange)

                        // Предвкушение: круг замечает точку заранее (радиус 100pt)
                        // и начинает вытягиваться в «боб» ещё до её прибытия
                        let reach = max(0, 1 - Double(distance) / 100)
                        let elongation = CGFloat(pow(reach, 1.6))
                        let length = beanRadius * 2 * (1 + 0.7 * elongation)
                        let thickness = beanRadius * 2 * (1 - 0.15 * elongation)

                        // …и тянется в первую очередь к точке: почти весь прирост
                        // длины уходит в ближний к ней край (дальний стоит на месте),
                        // а когда точка входит в центр — форма выравнивается
                        let tangentX = -CGFloat(sin(beanAngles[index]))
                        let tangentY = CGFloat(cos(beanAngles[index]))
                        let dotAlongTangent = (dotPos.x - beanCenter.x) * tangentX
                            + (dotPos.y - beanCenter.y) * tangentY
                        let direction = max(-1, min(1, dotAlongTangent / 24))
                        let extraLength = length - beanRadius * 2
                        let reachOffset = direction * 0.42 * extraLength

                        var beanContext = context
                        beanContext.translateBy(x: beanCenter.x, y: beanCenter.y)
                        beanContext.rotate(by: Angle(radians: beanAngles[index] + .pi / 2))
                        let rect = CGRect(
                            x: reachOffset - length / 2, y: -thickness / 2,
                            width: length, height: thickness
                        )
                        let bean = Path(roundedRect: rect, cornerRadius: min(length, thickness) / 2)
                        beanContext.stroke(
                            bean,
                            with: .color(.white.opacity(0.75 * appear)),
                            lineWidth: 1.5
                        )
                        if proximity > 0.01 {
                            beanContext.fill(bean, with: .color(.white.opacity(pow(proximity, 1.6) * appear)))
                        }

                    }

                    // Счёт долей в центре, каждая цифра появляется
                    // с мягким «попом» на ударе и растворяется к концу доли
                    let currentBeat = beatIndex % beats
                    let beatNumber = currentBeat + 1
                    let isAccentNumber = accents.contains(currentBeat)
                    let numberAppear = smooth(sinceHit / 0.07)
                    let numberFade = 1 - smooth((phase - 0.72) / 0.28)
                    let numberOpacity = numberAppear * numberFade * 0.9
                    if numberOpacity > 0.01 {
                        var numberContext = context
                        let pop = 1 + 0.1 * exp(-sinceHit / 0.15)
                        numberContext.translateBy(x: center.x, y: center.y)
                        numberContext.scaleBy(x: pop, y: pop)
                        numberContext.opacity = numberOpacity
                        // Сильные доли и глазом весомее: крупнее и плотнее
                        numberContext.draw(
                            Text("\(beatNumber)")
                                .font(.system(
                                    size: isAccentNumber ? 66 : 60,
                                    weight: isAccentNumber ? .light : .thin
                                ))
                                .foregroundStyle(.white),
                            at: .zero
                        )
                    }

                    // Комета-шлейф: деликатный, чтобы героем оставалась точка;
                    // при Reduce Motion выключен
                    if speed > 0.15, !reduceMotion {
                        for ghost in 1...4 {
                            let ghostTime = t - Double(ghost) * 0.022
                            guard ghostTime >= 0 else { break }
                            let gBeat = Int(ghostTime / interval)
                            let gPhase = (ghostTime - Double(gBeat) * interval) / interval
                            let gEased = 0.5 - 0.5 * cos(.pi * gPhase)
                            let gAngle = -Double.pi / 2 + (Double(gBeat) + gEased) * anglePerBeat
                            let gRadius = 8 - CGFloat(ghost) * 1.3
                            let gOpacity = 0.05 * (1 - Double(ghost) / 5) * speed
                            let gRect = CGRect(
                                x: center.x + radius * CGFloat(cos(gAngle)) - gRadius,
                                y: center.y + radius * CGFloat(sin(gAngle)) - gRadius,
                                width: gRadius * 2, height: gRadius * 2
                            )
                            context.fill(Path(ellipseIn: gRect), with: .color(.white.opacity(gOpacity)))
                        }
                    }

                    // Точка: материализуется, в полёте вытягивается по ходу движения
                    // (squash & stretch), у круга вливается в его форму
                    let dotAppear = smooth(t / 0.45)
                    guard dotAppear > 0.001 else { return }

                    let targetRadius = beanRadii[nearestIndex]
                    let morph = max(0, 1 - nearestDistance / meltRange)
                    let dotDiameter: CGFloat = 22 * CGFloat(0.5 + 0.5 * dotAppear)
                    // Вытягивание по касательной, объём сохраняется; у кругов гаснет
                    let stretch = reduceMotion ? 1 : 1 + 0.22 * speed * (1 - morph)
                    var dotWidth = dotDiameter * CGFloat(stretch)
                    var dotHeight = dotDiameter / CGFloat(stretch)
                    // Цель морфа — та же боб-форма, в которую вытягивается круг:
                    // в системе координат точки ширина идёт вдоль касательной
                    let targetElongation = CGFloat(pow(morph, 1.3))
                    let targetLength = targetRadius * 2 * (1 + 0.7 * targetElongation)
                    let targetThickness = targetRadius * 2 * (1 - 0.15 * targetElongation)
                    dotWidth += (targetLength - dotWidth) * morph
                    dotHeight += (targetThickness - dotHeight) * morph

                    // «Вселение» в кружки-деления: пролетая мимо, точка ныряет
                    // в ближайший кружок — сжимается, отдавая ему свет, — а на
                    // выходе выпрыгивает с упругим отскоком
                    var possession: Double = 0
                    var possessionLeaving = false
                    var possessedTick = CGPoint.zero
                    if !reduceMotion {
                        for tick in 0..<tickSlots where tick % slotsPerGap != 0 {
                            let tickAngle = -Double.pi / 2 + Double(tick) * 2 * .pi / Double(tickSlots)
                            let tickPos = CGPoint(
                                x: center.x + radius * CGFloat(cos(tickAngle)),
                                y: center.y + radius * CGFloat(sin(tickAngle))
                            )
                            let tickDistance = hypot(dotPos.x - tickPos.x, dotPos.y - tickPos.y)
                            let p = max(0, 1 - Double(tickDistance) / 26)
                            if p > possession {
                                possession = p
                                possessedTick = tickPos
                                // Кружок уже позади по ходу движения — точка выходит
                                let angularDiff = atan2(sin(tickAngle - angle), cos(tickAngle - angle))
                                possessionLeaving = angularDiff < 0
                            }
                        }
                        // Рядом с большими кругами вселение уступает морфу в боб
                        possession *= Double(1 - morph)
                    }

                    // Нырок: сжатие до половины; выскок: перелёт с запасом
                    let dive = 1 - 0.5 * possession
                    let pop = possessionLeaving ? possession * (1 - possession) * 0.9 : 0
                    let possessionScale = CGFloat(dive + pop)
                    dotWidth *= possessionScale
                    dotHeight *= possessionScale

                    let attraction = morph * morph
                    var dotCenter = CGPoint(
                        x: dotPos.x + (beanCenters[nearestIndex].x - dotPos.x) * attraction,
                        y: dotPos.y + (beanCenters[nearestIndex].y - dotPos.y) * attraction
                    )
                    // Магнитное притяжение к кружку в момент вселения
                    let pull = CGFloat(possession * possession) * 0.6
                    dotCenter.x += (possessedTick.x - dotCenter.x) * pull
                    dotCenter.y += (possessedTick.y - dotCenter.y) * pull

                    // Рисуем в системе координат точки, повёрнутой по касательной к дуге —
                    // вытягивание всегда «по ходу полёта»
                    var dotContext = context
                    dotContext.translateBy(x: dotCenter.x, y: dotCenter.y)
                    dotContext.rotate(by: Angle(radians: angle + .pi / 2))

                    let dotRect = CGRect(
                        x: -dotWidth / 2, y: -dotHeight / 2,
                        width: dotWidth, height: dotHeight
                    )
                    let dotCornerRadius = min(dotWidth, dotHeight) / 2

                    // Свечение дышит в ритм: вспыхивает на ударе, успокаивается в полёте,
                    // а при вселении в кружок частично передаётся ему
                    let glowPulse = exp(-sinceHit / 0.15)
                    let glowOpacity = (0.6 + 0.35 * glowPulse) * dotAppear * (1 - 0.35 * possession)
                    let glowInset = -10 - CGFloat(glowPulse) * 4
                    dotContext.drawLayer { layer in
                        layer.addFilter(.blur(radius: 16))
                        layer.fill(
                            Path(roundedRect: dotRect.insetBy(dx: glowInset, dy: glowInset),
                                 cornerRadius: dotCornerRadius - glowInset),
                            with: .color(.white.opacity(glowOpacity))
                        )
                    }
                    dotContext.fill(
                        Path(roundedRect: dotRect, cornerRadius: dotCornerRadius),
                        with: .color(.white.opacity(Double(dotAppear)))
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
