//
//  FocusMetronome.swift
//  BPM Animation
//
//  Created by Ulad Luch on 19/08/2026.
//
//  Круговой метроном фокус-режима: модель музыкального размера,
//  полноэкранная вспышка удара и «живая» анимация орбиты с точкой.
//

import SwiftUI

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


/// Полноэкранная вспышка удара — отдельный слой, чтобы не сжиматься вместе
/// с метрономом при удержании для выхода. Свет расходится радиально от круга,
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
                    // На первом круге точка «рисует» контур: каждый кружок рождается
                    // ровно в момент, когда она его проходит (с учётом косинусного
                    // сглаживания дуги). Подсвечиваются, когда точка пролетает мимо.
                    let slotsPerGap = signature.ticksPerGap + 1
                    let tickSlots = beats * slotsPerGap
                    for tick in 0..<tickSlots where tick % slotsPerGap != 0 {
                        // Момент пролёта: доля + фаза внутри дуги (обратная easing-кривой)
                        let gapIndex = Double(tick / slotsPerGap)
                        let fraction = Double(tick % slotsPerGap) / Double(slotsPerGap)
                        let phaseAtTick = acos(1 - 2 * fraction) / .pi
                        let bornTime = (gapIndex + phaseAtTick) * interval
                        let tickAppear = smooth((t - bornTime) / 0.35)
                        guard tickAppear > 0.001 else { continue }

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
                        let tickRadius = (2 + 1.2 * glow + 5.5 * swallow * swallow) * tickAppear
                        let tickRect = CGRect(
                            x: tickPos.x - tickRadius, y: tickPos.y - tickRadius,
                            width: tickRadius * 2, height: tickRadius * 2
                        )
                        context.fill(
                            Path(ellipseIn: tickRect),
                            with: .color(.white.opacity(
                                min(0.95, 0.18 + 0.5 * glow + 0.35 * swallow) * tickAppear
                            ))
                        )
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

                        // Круг доли рождается в момент, когда точка впервые
                        // доезжает до него — точка «рисует» контур на первом круге
                        let bornTime = Double(index) * interval
                        let appear = smooth((t - bornTime) / 0.4)
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
