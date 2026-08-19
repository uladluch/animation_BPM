//
//  ContentView.swift
//  BPM Animation
//
//  Created by Ulad Luch on 18/08/2026.
//

import SwiftUI

/// Одна волна из точек, расходящаяся от места касания
private struct Ripple: Identifiable {
    let id = UUID()
    let center: CGPoint
    let startDate: Date
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
        VStack(spacing: 48) {
            bpmBlock

            // Демо-волна внизу: зацикленный «тап» по центру — только точки,
            // без рамки, букв и цифр
            DotWaveLoopView()
                .frame(width: 349, height: 172)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Зацикленная демо-волна: точки расходятся от центра, как от прожатого тапа
private struct DotWaveLoopView: View {
    // Те же параметры, что у волны основного компонента
    private let dotSpacing: CGFloat = 13
    private let rippleDuration: TimeInterval = 1.4
    private let rippleBandWidth: Double = 38
    /// Полный цикл: волна + короткая пауза перед следующим «тапом»
    private let loopPeriod: TimeInterval = 2.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: loopPeriod)
                guard cycle < rippleDuration else { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let cols = Int(size.width / dotSpacing)
                let rows = Int(size.height / dotSpacing)
                let xInset = (size.width - CGFloat(cols - 1) * dotSpacing) / 2
                let yInset = (size.height - CGFloat(rows - 1) * dotSpacing) / 2

                let maxRadius = hypot(size.width / 2, size.height / 2) + rippleBandWidth
                let progress = cycle / rippleDuration
                let waveRadius = maxRadius * (1 - pow(1 - progress, 2.2))
                let fade = pow(1 - progress, 1.2)

                for row in 0..<rows {
                    for col in 0..<cols {
                        let point = CGPoint(
                            x: xInset + CGFloat(col) * dotSpacing,
                            y: yInset + CGFloat(row) * dotSpacing
                        )

                        let distance = hypot(point.x - center.x, point.y - center.y)
                        let delta = distance - waveRadius
                        let width = delta < 0 ? rippleBandWidth * 1.8 : rippleBandWidth
                        let intensity = exp(-pow(delta / width, 2)) * fade
                        guard intensity > 0.02 else { continue }

                        var pushX = 0.0
                        var pushY = 0.0
                        if distance > 0.001 {
                            let push = 4.0 * intensity
                            pushX = (point.x - center.x) / distance * push
                            pushY = (point.y - center.y) / distance * push
                        }

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
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
