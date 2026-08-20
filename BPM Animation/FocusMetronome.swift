//
//  FocusMetronome.swift
//  BPM Animation
//
//  Created by Ulad Luch on 19/08/2026.
//
//  Метроном фокус-режима: классический маятник — светящаяся точка ездит
//  слева направо между двумя бобами, одна доля = один пролёт.
//  Под маятником — ряд точек-долей выбранного размера, над ним — номер такта.
//

import SwiftUI

/// Музыкальный размер: определяет число долей в такте,
/// акцентные доли и плотность делений на линии маятника
enum TimeSignature: String, CaseIterable, Identifiable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case twoFour = "2/4"
    case sixEight = "6/8"
    case twelveEight = "12/8"

    var id: String { rawValue }

    /// Число долей в такте
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
/// в который только что ударила точка; сильная доля ярче. На быстрых темпах
/// и при Reduce Motion / Dim Flashing Lights приглушается.
struct MetronomeFlashView: View {
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

                // Удар по чётным долям приходится в левый боб, по нечётным — в правый
                let hitX = beatIndex % 2 == 0
                    ? PendulumGeometry.leftX(size)
                    : PendulumGeometry.rightX(size)
                let hitCenter = CGPoint(x: hitX, y: PendulumGeometry.midY(size))

                let currentBeat = beatIndex % signature.beatsPerBar
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

/// Маятник фокус-режима: точка ездит между двумя бобами (одна доля — один
/// пролёт), под линией — точки-доли такта, над линией — номер такта.
///
/// Живая хореография в стиле Apple:
/// — на первом такте точка «рисует» маятник: бобы и деления рождаются
///   в момент, когда она их впервые проходит,
/// — squash & stretch точки в полёте (вытягивается по ходу движения),
/// — бобы замечают точку заранее и тянутся ей навстречу ближним краем,
/// — при слиянии точка и боб становятся одной каплей, пружинный пульс на ударе,
/// — точка «вселяется» в кружки-деления и выпрыгивает из них,
/// — комета-шлейф на скорости, свечение «дышит» в ритм.
struct MetronomePendulumView: View {
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

                let beats = signature.beatsPerBar
                let accents = signature.accentBeats

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

                // Короткая тёмная линия по центру. На первом пролёте точка
                // «рисует» её за собой; пролетая, точка вселяется в линию
                // и бежит по ней световым импульсом
                let lineHalfLength: CGFloat = 32
                let lineStart = centerX - lineHalfLength
                let lineEnd = centerX + lineHalfLength
                let revealedEnd = t < interval
                    ? min(lineEnd, x)
                    : lineEnd
                if revealedEnd > lineStart {
                    var line = Path()
                    line.move(to: CGPoint(x: lineStart, y: midY))
                    line.addLine(to: CGPoint(x: revealedEnd, y: midY))
                    context.stroke(line, with: .color(.white.opacity(0.15)), lineWidth: 1.5)
                }

                // Насколько точка «внутри» линии: 0 снаружи, 1 в глубине
                // (мягкие края по 24pt, чтобы вход и выход были плавными)
                let depthInLine = min(x - lineStart, lineEnd - x)
                let linePossession = smooth(Double(depthInLine) / 24)

                // Линия светится под точкой — бегущий по ней световой след
                if linePossession > 0.01 {
                    let glowStart = max(lineStart, x - 18)
                    let glowEnd = min(revealedEnd, x + 18)
                    if glowEnd > glowStart {
                        var glowSegment = Path()
                        glowSegment.move(to: CGPoint(x: glowStart, y: midY))
                        glowSegment.addLine(to: CGPoint(x: glowEnd, y: midY))
                        context.stroke(
                            glowSegment,
                            with: .color(.white.opacity(0.5 * linePossession)),
                            lineWidth: 2
                        )
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
                    // Пружинный пульс: подскок и затухающее колебание
                    let pulse = wasHit
                        ? exp(-sinceOwnHit / 0.16) * cos(sinceOwnHit * 18) * 0.14
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
                    // Серый боб загорается белым по мере приближения точки
                    let brightness = 0.22 + 0.78 * pow(proximity, 1.6)
                    context.fill(bean, with: .color(.white.opacity(brightness * appear)))
                }

                // Счёт тактов над маятником: цифра меняется раз в такт
                // (на сильной доле) и идёт по кругу до размера —
                // для 4/4: такт 1, 2, 3, 4 → снова 1
                let currentBeat = beatIndex % beats
                let barDuration = interval * Double(beats)
                let barIndex = Int(t / barDuration)
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

                // Точки-доли такта под маятником: текущая горит и остывает,
                // сильные доли крупнее. Рождаются по одной на первом такте.
                let indicatorSpacing: CGFloat = beats > 8 ? 16 : 22
                let indicatorY = midY + 64
                let rowWidth = indicatorSpacing * CGFloat(beats - 1)
                for beat in 0..<beats {
                    let bornTime = Double(beat) * interval
                    let indicatorAppear = smooth((t - bornTime) / 0.35)
                    guard indicatorAppear > 0.001 else { continue }

                    let isAccent = accents.contains(beat)
                    var brightness = isAccent ? 0.4 : 0.25
                    var indicatorRadius: CGFloat = isAccent ? 4.5 : 3
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
                        with: .color(.white.opacity(brightness * indicatorAppear))
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

                // «Вселение» в линию: над ней точка сплющивается в световой
                // импульс, бегущий внутри, а на выходе восстанавливает форму
                let lineMorph = CGFloat(linePossession) * (1 - morph)
                dotWidth += (34 - dotWidth) * lineMorph
                dotHeight += (7 - dotHeight) * lineMorph

                let attraction = morph * morph
                let dotCenterX = x + (nearestBeanX - x) * attraction

                let dotRect = CGRect(
                    x: dotCenterX - dotWidth / 2, y: midY - dotHeight / 2,
                    width: dotWidth, height: dotHeight
                )
                let dotCornerRadius = min(dotWidth, dotHeight) / 2

                // Свечение дышит в ритм: вспыхивает на ударе, успокаивается в полёте,
                // а внутри линии частично передаётся ей
                let glowPulse = exp(-sinceHit / 0.15)
                let glowOpacity = (0.6 + 0.35 * glowPulse) * dotAppear * (1 - 0.3 * Double(lineMorph))
                let glowInset = -10 - CGFloat(glowPulse) * 4
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 16))
                    layer.fill(
                        Path(roundedRect: dotRect.insetBy(dx: glowInset, dy: glowInset),
                             cornerRadius: dotCornerRadius - glowInset),
                        with: .color(.white.opacity(glowOpacity))
                    )
                }
                context.fill(
                    Path(roundedRect: dotRect, cornerRadius: dotCornerRadius),
                    with: .color(.white.opacity(Double(dotAppear)))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
