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
    /// Текущее (последнее вычисленное) значение BPM
    @State private var bpm = 119
    /// Время каждого тапа в текущей сессии настукивания
    @State private var tapTimes: [Date] = []
    /// Бордер виден, пока пользователь взаимодействует с компонентом
    @State private var strokeVisible = false
    /// Отложенная задача завершения сессии (сбрасывается каждым новым тапом)
    @State private var sessionEndTask: Task<Void, Never>?
    /// Активные волны из точек
    @State private var ripples: [Ripple] = []
    /// Время запуска последней волны — чтобы не стробить при быстром ритме
    @State private var lastRippleDate: Date?
    /// Счётчик тапов — триггер тактильного отклика
    @State private var tapCount = 0

    /// Пауза, после которой считаем, что пользователь закончил настукивать
    private let sessionTimeout: TimeInterval = 2.0
    /// Максимальный BPM, который можно настучать
    private let maxBPM = 360

    // Параметры волны из точек
    private let dotSpacing: CGFloat = 13           // шаг сетки точек
    private let rippleDuration: TimeInterval = 1.4 // время жизни волны
    private let rippleBandWidth: Double = 38       // ширина светящегося фронта
    private let rippleMinInterval: TimeInterval = 0.3 // не чаще одной волны в 0.3с

    /// Первые 3 тапа показываем прочерки (-, --, ---), с 4-го — настуканный BPM
    private var displayText: String {
        if !tapTimes.isEmpty && tapTimes.count < 4 {
            return String(repeating: "-", count: tapTimes.count)
        }
        return "\(bpm)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(displayText)
                .font(.system(size: 130))
                .foregroundStyle(.primary)
                .frame(height: 154)

            Text("tap the bpm")
                .textCase(.uppercase)
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
                .opacity(strokeVisible ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .onTapGesture(coordinateSpace: .local) { location in
            registerTap(at: location)
        }
        // Компонент мягко «раздувается» при взаимодействии — синхронно
        // с появлением и исчезновением бордера
        .scaleEffect(strokeVisible ? 1.03 : 1.0)
        // Мягкий тактильный отклик на каждый тап
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: tapCount)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Сетка точек, по которой от места касания расходится мягкая волна
    private var dotWave: some View {
        TimelineView(.animation(minimumInterval: nil, paused: ripples.isEmpty)) { timeline in
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

                        // Яркость точки — максимум по всем активным волнам
                        var intensity: Double = 0
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
                            intensity = max(intensity, band * fade)
                        }

                        guard intensity > 0.02 else { continue }

                        // Точка деликатно увеличивается на пике волны
                        let radius = 0.6 + 0.5 * intensity
                        let rect = CGRect(
                            x: point.x - radius, y: point.y - radius,
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

    /// Регистрирует тап: запускает волну, обновляет BPM с 4-го тапа и перезапускает таймер сессии
    private func registerTap(at location: CGPoint) {
        sessionEndTask?.cancel()
        tapTimes.append(Date())
        tapCount += 1

        // Волна из точек рождается под пальцем.
        // При быстром ритме (вплоть до 360 BPM) волны запускаем не на каждый тап,
        // а не чаще rippleMinInterval — иначе анимация стробит.
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

        // Подсветка плавно появляется, как только пользователь начал взаимодействовать
        withAnimation(.easeOut(duration: 0.35)) {
            strokeVisible = true
        }

        if tapTimes.count >= 4 {
            bpm = computedBPM()
        }

        sessionEndTask = Task {
            try? await Task.sleep(for: .seconds(sessionTimeout))
            guard !Task.isCancelled else { return }
            endSession()
        }
    }

    /// Пользователь перестал настукивать: сбрасываем сессию, подсветка плавно затухает
    private func endSession() {
        tapTimes = []
        withAnimation(.easeOut(duration: 0.45)) {
            strokeVisible = false
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

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
