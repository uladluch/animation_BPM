//
//  FocusMetronome.swift
//  BPM Animation
//
//  Created by Ulad Luch on 19/08/2026.
//
//  Метроном фокус-режима: классический маятник — светящаяся точка ездит
//  слева направо между двумя бобами, одна доля = один пролёт.
//  Ритм задаётся пресетом: у каждой доли свой акцент (mute / средний /
//  сильный) и свой цвет. Под маятником — точки-доли, над ним — номер такта.
//

import SwiftUI

/// Сила удара доли
enum BeatAccent {
    /// Беззвучная доля: нет щелчка, вспышки и волны — только движение точки
    case mute
    /// Обычный удар
    case medium
    /// Сильный акцент: ярче вспышка, плотнее пульс, крупнее метки
    case strong
}

/// Стиль одной доли такта: акцент и цвет (белый по умолчанию)
struct BeatStyle {
    var accent: BeatAccent = .medium
    var color: Color = .white
}

/// Палитра цветов долей
extension Color {
    static let beatLime = Color(red: 178 / 255, green: 1, blue: 0)         // B2FF00
    static let beatAmber = Color(red: 1, green: 177 / 255, blue: 44 / 255) // FFB12C
    static let beatCyan = Color(red: 0, green: 227 / 255, blue: 227 / 255) // 00E3E3
    static let beatCoral = Color(red: 1, green: 95 / 255, blue: 51 / 255)  // FF5F33
}

/// Ритмический пресет: классические размеры и экспериментальный рисунок
/// со сложным ритмом — паузами, разными акцентами и цветными долями
enum RhythmPreset: String, CaseIterable, Identifiable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case twoFour = "2/4"
    case sixEight = "6/8"
    case twelveEight = "12/8"
    case experimental = "Experimental"

    var id: String { rawValue }

    /// Рисунок такта: стиль каждой доли
    var pattern: [BeatStyle] {
        switch self {
        case .fourFour: Self.simpleMeter(beats: 4)
        case .threeFour: Self.simpleMeter(beats: 3)
        case .twoFour: Self.simpleMeter(beats: 2)
        case .sixEight: Self.compoundMeter(beats: 6, groupSize: 3)
        case .twelveEight: Self.compoundMeter(beats: 12, groupSize: 3)
        case .experimental:
            // Синкопированный рисунок на 8 долей: цветные акценты и паузы
            [
                BeatStyle(accent: .strong, color: .beatLime),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .medium, color: .beatCyan),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .strong, color: .beatAmber),
                BeatStyle(accent: .medium),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .medium, color: .beatCoral)
            ]
        }
    }

    /// Простой размер: сильная первая доля, остальные обычные
    private static func simpleMeter(beats: Int) -> [BeatStyle] {
        (0..<beats).map { BeatStyle(accent: $0 == 0 ? .strong : .medium) }
    }

    /// Составной размер: сильная доля в начале каждой группы восьмых
    private static func compoundMeter(beats: Int, groupSize: Int) -> [BeatStyle] {
        (0..<beats).map { BeatStyle(accent: $0 % groupSize == 0 ? .strong : .medium) }
    }
}

/// Общая геометрия маятника — одна для метронома и вспышки,
/// чтобы источник света совпадал с бобом удара
private enum PendulumGeometry {
    /// Бобы по краям — вертикальные капсулы, главный визуальный акцент
    static let beanWidth: CGFloat = 48
    static let beanHeight: CGFloat = 90
    static let margin: CGFloat = 62

    static func leftX(_ size: CGSize) -> CGFloat { margin + beanWidth / 2 }
    static func rightX(_ size: CGSize) -> CGFloat { size.width - margin - beanWidth / 2 }
    static func midY(_ size: CGSize) -> CGFloat { size.height / 2 }
}

/// Полноэкранная вспышка удара — отдельный слой, чтобы не сжиматься вместе
/// с метрономом при удержании для выхода. Свет расходится радиально от боба,
/// в который только что ударила точка, в цвете доли; сильная доля ярче,
/// беззвучная не вспыхивает вовсе. На быстрых темпах и при Reduce Motion /
/// Dim Flashing Lights приглушается.
struct MetronomeFlashView: View {
    let startDate: Date
    let bpm: Int
    let pattern: [BeatStyle]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights

    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let beats = max(1, pattern.count)
                let interval = 60.0 / Double(max(bpm, 1))
                let t = max(0, timeline.date.timeIntervalSince(startDate))
                let sinceHit = t.truncatingRemainder(dividingBy: interval)
                let beatIndex = Int(t / interval)
                let style = pattern[beatIndex % beats]

                // Удар по чётным долям приходится в левый боб, по нечётным — в правый
                let hitX = beatIndex % 2 == 0
                    ? PendulumGeometry.leftX(size)
                    : PendulumGeometry.rightX(size)
                let hitCenter = CGPoint(x: hitX, y: PendulumGeometry.midY(size))

                let accentPeak: Double = switch style.accent {
                case .mute: 0
                case .medium: 0.18
                case .strong: 0.32
                }
                let tempoDim = 0.35 + 0.65 * min(1, interval / 0.5)
                let calmFactor = (reduceMotion || dimFlashingLights) ? 0.12 : 1.0
                // Нежный световой «выдох» в цвете доли: невысокий пик
                // и плавное затухание
                let flashPeak = accentPeak * tempoDim * calmFactor
                let flash = flashPeak * exp(-sinceHit / 0.16) * smooth(t / 0.4)
                if flash > 0.01 {
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            Gradient(colors: [
                                style.color.opacity(flash),
                                style.color.opacity(flash * 0.2)
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

/// Маятник фокус-режима: точка ездит между двумя бобами (одна доля — один
/// пролёт), под линией — точки-доли такта, над линией — номер такта.
///
/// Живая хореография в стиле Apple:
/// — на первом такте точка «рисует» маятник: бобы и метки рождаются
///   в момент, когда она их впервые проходит,
/// — squash & stretch точки в полёте (вытягивается по ходу движения),
/// — бобы замечают точку заранее и тянутся ей навстречу ближним краем,
/// — при слиянии точка и боб окрашиваются в цвет доли и пружинят на ударе,
/// — беззвучные доли проходят тихо: без вспышки, волны и пульса,
/// — комета-шлейф на скорости, свечение «дышит» в ритм.
struct MetronomePendulumView: View {
    let startDate: Date
    let bpm: Int
    let pattern: [BeatStyle]

    /// Доступность: убираем стробирующие и «летающие» эффекты
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Плавная S-кривая (smoothstep) для появлений
    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Стиль доли по абсолютному номеру удара
    private func style(ofBeat beatIndex: Int) -> BeatStyle {
        let beats = max(1, pattern.count)
        return pattern[((beatIndex % beats) + beats) % beats]
    }

    /// Амплитуда пружинного пульса боба по силе удара
    private func pulseAmplitude(for accent: BeatAccent) -> Double {
        switch accent {
        case .mute: 0
        case .medium: 0.14
        case .strong: 0.2
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let interval = 60.0 / Double(max(bpm, 1))
                let t = max(0, timeline.date.timeIntervalSince(startDate))
                let sinceHit = t.truncatingRemainder(dividingBy: interval)

                let beats = max(1, pattern.count)

                let midY = PendulumGeometry.midY(size)
                let beanWidth = PendulumGeometry.beanWidth
                let beanHeight = PendulumGeometry.beanHeight
                let leftX = PendulumGeometry.leftX(size)
                let rightX = PendulumGeometry.rightX(size)
                let span = rightX - leftX
                let centerX = size.width / 2

                // Движение: одна доля — один пролёт, чётные доли бьют в левый боб.
                // Косинусное сглаживание: у бобов точка замедляется, как маятник.
                let beatIndex = Int(t / interval)
                let phase = (t - Double(beatIndex) * interval) / interval
                let eased = 0.5 - 0.5 * cos(.pi * phase)
                let movingRight = beatIndex % 2 == 0
                let x = movingRight
                    ? leftX + span * CGFloat(eased)
                    : rightX - span * CGFloat(eased)
                // Мгновенная скорость (0 у бобов, максимум в середине пролёта)
                let speed = sin(.pi * phase)

                // Позиция в такте
                let currentBeat = beatIndex % beats
                let barDuration = interval * Double(beats)
                let barIndex = Int(t / barDuration)

                // Ближайший по времени удар: до середины пролёта — прошедший,
                // после — предстоящий. Его цвет несут точка и боб при слиянии.
                let nearestHitBeat = phase < 0.5 ? beatIndex : beatIndex + 1
                let nearestHitStyle = style(ofBeat: nearestHitBeat)

                // «Температура» сцены: каждый удар оставляет в бобах остаточное
                // свечение — ступенькой ярче с каждой долей. К концу такта бобы
                // тлеют, а на сильной доле сбрасываются в серый с «выдохом».
                let barHeat: Double
                if beats <= 1 {
                    barHeat = 0
                } else if currentBeat == 0 {
                    // Выдох на сильной доле: накопленный накал плавно отпускается.
                    // В самом первом такте копить ещё нечего — остаёмся холодными.
                    barHeat = barIndex == 0 ? 0 : 1 - smooth(sinceHit / 0.55)
                } else {
                    // Очередной удар добавляет ступеньку тепла (с мягким фронтом)
                    let step = 1.0 / Double(beats - 1)
                    barHeat = (Double(currentBeat - 1) + smooth(sinceHit / 0.25)) * step
                }

                // Эхо-волна: каждый звучащий удар пускает от боба тусклую волну
                // из точек в цвете своей доли — круги от камня в тёмной воде.
                // Беззвучные доли волну не рождают.
                let waveDuration = 1.25
                let gridSpacing: CGFloat = 26
                let cols = Int(size.width / gridSpacing)
                let rows = Int(size.height / gridSpacing)
                let xInset = (size.width - CGFloat(cols - 1) * gridSpacing) / 2
                let yInset = (size.height - CGFloat(rows - 1) * gridSpacing) / 2

                // Живы волны от последних трёх ударов
                var waves: [(center: CGPoint, age: Double, style: BeatStyle)] = []
                for back in 0..<3 {
                    let hitBeat = beatIndex - back
                    guard hitBeat >= 0 else { continue }
                    let hitStyle = style(ofBeat: hitBeat)
                    guard hitStyle.accent != .mute else { continue }
                    let age = t - Double(hitBeat) * interval
                    guard age < waveDuration else { continue }
                    let waveX = hitBeat % 2 == 0 ? leftX : rightX
                    waves.append((CGPoint(x: waveX, y: midY), age, hitStyle))
                }

                if !waves.isEmpty {
                    for row in 0..<rows {
                        for col in 0..<cols {
                            let point = CGPoint(
                                x: xInset + CGFloat(col) * gridSpacing,
                                y: yInset + CGFloat(row) * gridSpacing
                            )
                            // Точку красит сильнейшая волна в этом месте
                            var intensity: Double = 0
                            var waveColor = Color.white
                            for wave in waves {
                                let progress = wave.age / waveDuration
                                let farX = max(wave.center.x, size.width - wave.center.x)
                                let farY = max(wave.center.y, size.height - wave.center.y)
                                let maxRadius = hypot(farX, farY) + 34
                                let waveRadius = maxRadius * (1 - pow(1 - progress, 2.2))
                                let distance = hypot(point.x - wave.center.x, point.y - wave.center.y)
                                let delta = distance - waveRadius
                                let bandWidth = delta < 0 ? 54.0 : 34.0
                                let band = exp(-pow(Double(delta) / bandWidth, 2))
                                let fade = pow(1 - progress, 1.3)
                                let contribution = band * fade * (wave.style.accent == .strong ? 1.25 : 1)
                                if contribution > intensity {
                                    intensity = contribution
                                    waveColor = wave.style.color
                                }
                            }
                            guard intensity > 0.03 else { continue }
                            let dotRadius = 0.8 + 0.6 * intensity
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: point.x - dotRadius, y: point.y - dotRadius,
                                    width: dotRadius * 2, height: dotRadius * 2
                                )),
                                with: .color(waveColor.opacity(0.14 * intensity))
                            )
                        }
                    }
                }

                // Бобы по краям: рождаются при первом ударе точки,
                // тянутся ей навстречу и вытягиваются в каплю при слиянии
                let meltRange: CGFloat = 60
                var nearestBeanX = leftX
                var nearestDistance = CGFloat.infinity
                for side in 0..<2 {
                    let beanX = side == 0 ? leftX : rightX
                    let distance = abs(x - beanX)
                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearestBeanX = beanX
                    }

                    // Левый боб рождается на первом ударе (t = 0),
                    // правый — когда точка впервые доезжает до него
                    let bornTime = side == 0 ? 0 : interval
                    let appear = smooth((t - bornTime) / 0.4)
                    guard appear > 0.001 else { continue }

                    // Последний удар по этому бобу (левый бьётся на чётных долях)
                    let beatsSinceOwnHit = ((beatIndex - side) % 2 + 2) % 2
                    let lastOwnHitBeat = beatIndex - beatsSinceOwnHit
                    let sinceOwnHit = t - Double(lastOwnHitBeat) * interval
                    let wasHit = lastOwnHitBeat >= 0
                    // Пружинный пульс по силе удара: сильная доля бьёт плотнее,
                    // беззвучная проходит без пульса
                    let ownAccent = style(ofBeat: lastOwnHitBeat).accent
                    let pulse = wasHit
                        ? exp(-sinceOwnHit / 0.16) * cos(sinceOwnHit * 18) * pulseAmplitude(for: ownAccent)
                        : 0

                    let scale = CGFloat(appear * (1 + pulse))
                    let proximity = max(0, 1 - distance / meltRange)

                    // Предвкушение: боб замечает точку заранее (радиус 100pt)
                    // и начинает раздуваться ещё до её прибытия — сильнее вширь,
                    // чуть-чуть в рост
                    let reach = max(0, 1 - Double(distance) / 100)
                    let inflate = CGFloat(pow(reach, 1.6))
                    let width = beanWidth * (1 + 0.55 * inflate) * scale
                    let height = beanHeight * (1 + 0.18 * inflate) * scale

                    // …и подаётся навстречу точке: прирост ширины уходит
                    // в ближний к ней край, а когда точка входит в центр —
                    // боб выравнивается
                    let dotAlong = x - beanX
                    let direction = max(-1, min(1, dotAlong / 24))
                    let extraWidth = width - beanWidth * scale
                    let reachOffset = direction * 0.42 * extraWidth

                    let rect = CGRect(
                        x: beanX + reachOffset - width / 2, y: midY - height / 2,
                        width: width, height: height
                    )
                    let bean = Path(roundedRect: rect, cornerRadius: min(width, height) / 2)

                    // Базовый серый теплеет с каждым ударом такта
                    let base = 0.22 + 0.3 * barHeat
                    context.fill(bean, with: .color(.white.opacity(base * appear)))
                    // При приближении точки боб разгорается в цвете своей доли
                    if proximity > 0.01 {
                        context.fill(
                            bean,
                            with: .color(nearestHitStyle.color.opacity(pow(proximity, 1.6) * appear))
                        )
                    }
                }

                // Счёт тактов над маятником: цифра меняется раз в такт
                // (на сильной доле) и идёт по кругу до размера —
                // для 4/4: такт 1, 2, 3, 4 → снова 1
                let barNumber = barIndex % beats + 1
                let sinceBarStart = t - Double(barIndex) * barDuration
                let barPhase = sinceBarStart / barDuration
                let numberAppear = smooth(sinceBarStart / 0.07)
                let numberFade = 1 - smooth((barPhase - 0.85) / 0.15)
                let numberOpacity = numberAppear * numberFade * 0.9
                if numberOpacity > 0.01 {
                    var numberContext = context
                    let pop = 1 + 0.1 * exp(-sinceBarStart / 0.15)
                    numberContext.translateBy(x: centerX, y: midY - 120)
                    numberContext.scaleBy(x: pop, y: pop)
                    numberContext.opacity = numberOpacity
                    numberContext.draw(
                        Text("\(barNumber)")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(.white),
                        at: .zero
                    )
                }

                // Точки-доли такта под маятником: позиция в такте всегда видна.
                // Каждая метка в цвете своей доли: сильные крупнее, беззвучные —
                // едва заметные. Рождаются по одной на первом такте.
                let indicatorSpacing: CGFloat = beats > 8 ? 16 : 22
                let indicatorY = midY + 96
                let rowWidth = indicatorSpacing * CGFloat(beats - 1)
                for beat in 0..<beats {
                    let bornTime = Double(beat) * interval
                    let indicatorAppear = smooth((t - bornTime) / 0.35)
                    guard indicatorAppear > 0.001 else { continue }

                    let beatStyle = pattern[beat]
                    var brightness: Double
                    var indicatorRadius: CGFloat
                    switch beatStyle.accent {
                    case .mute:
                        brightness = 0.12
                        indicatorRadius = 2.5
                    case .medium:
                        brightness = 0.25
                        indicatorRadius = 3
                    case .strong:
                        brightness = 0.4
                        indicatorRadius = 4.5
                    }
                    if beat == currentBeat {
                        let heat = exp(-sinceHit / 0.35)
                        brightness = min(1, brightness + 0.6 * heat + 0.15)
                        indicatorRadius += CGFloat(1.2 * heat)
                    }
                    let indicatorX = centerX - rowWidth / 2 + indicatorSpacing * CGFloat(beat)
                    let indicatorRect = CGRect(
                        x: indicatorX - indicatorRadius, y: indicatorY - indicatorRadius,
                        width: indicatorRadius * 2, height: indicatorRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: indicatorRect),
                        with: .color(beatStyle.color.opacity(brightness * indicatorAppear))
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
                        let gX = gBeat % 2 == 0
                            ? leftX + span * CGFloat(gEased)
                            : rightX - span * CGFloat(gEased)
                        let gRadius = 8 - CGFloat(ghost) * 1.3
                        let gOpacity = 0.05 * (1 - Double(ghost) / 5) * speed
                        let gRect = CGRect(
                            x: gX - gRadius, y: midY - gRadius,
                            width: gRadius * 2, height: gRadius * 2
                        )
                        context.fill(Path(ellipseIn: gRect), with: .color(.white.opacity(gOpacity)))
                    }
                }

                // Точка: материализуется, в полёте вытягивается по ходу движения
                // (squash & stretch), у боба вливается в его форму
                let dotAppear = smooth(t / 0.45)
                guard dotAppear > 0.001 else { return }

                let morph = max(0, 1 - nearestDistance / meltRange)
                let dotDiameter: CGFloat = 22 * CGFloat(0.5 + 0.5 * dotAppear)
                // Вытягивание по ходу движения, объём сохраняется; у бобов гаснет
                let stretch = reduceMotion ? 1 : 1 + 0.22 * speed * (1 - morph)
                var dotWidth = dotDiameter * CGFloat(stretch)
                var dotHeight = dotDiameter / CGFloat(stretch)
                // Цель морфа — тот же раздутый вертикальный боб:
                // в момент слияния формы совпадают один в один
                let targetInflate = CGFloat(pow(morph, 1.3))
                let targetWidth = beanWidth * (1 + 0.55 * targetInflate)
                let targetHeight = beanHeight * (1 + 0.18 * targetInflate)
                dotWidth += (targetWidth - dotWidth) * morph
                dotHeight += (targetHeight - dotHeight) * morph

                let attraction = morph * morph
                let dotCenterX = x + (nearestBeanX - x) * attraction

                let dotRect = CGRect(
                    x: dotCenterX - dotWidth / 2, y: midY - dotHeight / 2,
                    width: dotWidth, height: dotHeight
                )
                let dotCornerRadius = min(dotWidth, dotHeight) / 2
                let dotShape = Path(roundedRect: dotRect, cornerRadius: dotCornerRadius)

                // Свечение дышит в ритм: вспыхивает на ударе, успокаивается в полёте
                let glowPulse = exp(-sinceHit / 0.15)
                let glowOpacity = (0.6 + 0.35 * glowPulse) * dotAppear
                let glowInset = -10 - CGFloat(glowPulse) * 4
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 16))
                    layer.fill(
                        Path(roundedRect: dotRect.insetBy(dx: glowInset, dy: glowInset),
                             cornerRadius: dotCornerRadius - glowInset),
                        with: .color(.white.opacity(glowOpacity))
                    )
                }
                context.fill(dotShape, with: .color(.white.opacity(Double(dotAppear))))
                // Подлетая к бобу, точка окрашивается в цвет ближайшего удара
                let mergeTint = Double(morph) * 0.85
                if mergeTint > 0.01 {
                    context.fill(
                        dotShape,
                        with: .color(nearestHitStyle.color.opacity(mergeTint * Double(dotAppear)))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
