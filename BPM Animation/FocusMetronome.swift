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
    /// Беззвучная доля (пауза): нет щелчка, вспышки и волны — только движение точки
    case mute
    /// Слабый удар: звучит, но вспышка и пульс приглушены
    case weak
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
    case pausePause = "Pause Pause"
    case pauseStart = "Pause Start"
    case fourFourTriplets = "4/4 Triplets"
    case experimental = "Experimental"

    var id: String { rawValue }

    /// Рисунок такта: стиль каждой доли. Первая звучащая доля такта выделена
    /// цветом — так «раз» видно и по бобу, в который свет приходит, и по вспышке.
    /// Метка идёт именно на звучащую: если такт открывают паузы, красить нечего —
    /// они не дают ни вспышки, ни отклика боба.
    var pattern: [BeatStyle] {
        var beats = basePattern
        if let downbeat = beats.firstIndex(where: { $0.accent != .mute }) {
            beats[downbeat].color = .beatLime
        }
        return beats
    }

    /// Рисунок без цветовой разметки — акценты и паузы
    private var basePattern: [BeatStyle] {
        switch self {
        case .fourFour: Self.simpleMeter(beats: 4)
        case .fourFourTriplets: Self.tripletMeter(quarters: 4)
        case .threeFour: Self.simpleMeter(beats: 3)
        case .twoFour: Self.simpleMeter(beats: 2)
        case .sixEight: Self.compoundMeter(beats: 6, groupSize: 3)
        case .twelveEight: Self.compoundMeter(beats: 12, groupSize: 3)
        case .pausePause:
            // 4/4: сильная доля, две паузы подряд, затем обычная доля
            [
                BeatStyle(accent: .strong),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .medium)
            ]
        case .pauseStart:
            // 4/4: такт начинается с двух пауз — маятник эти две доли ходит
            // вхолостую, бобы молчат, — и вступает на третьей
            [
                BeatStyle(accent: .mute),
                BeatStyle(accent: .mute),
                BeatStyle(accent: .strong),
                BeatStyle(accent: .medium)
            ]
        case .experimental:
            // Джент в духе Meshuggah: такт из 16 шестнадцатых,
            // удары группами 2+3+2+3+3+3 (старты групп), между ними тишина.
            // Единственный сильный акцент — на единице.
            Self.meshuggah()
        }
    }

    /// На сколько субударов делится одна четверть. Маятник всегда идёт
    /// по четвертям — деление живёт только в звуке и в пульсации света,
    /// не меняя ни скорости хода, ни направления.
    var subdivision: Int {
        switch self {
        case .fourFourTriplets: 3
        default: 1
        }
    }

    /// Сколько четвертей в такте пресета
    var quartersPerBar: Int {
        max(1, pattern.count / subdivision)
    }

    /// Простой размер: сильная первая доля, остальные обычные
    private static func simpleMeter(beats: Int) -> [BeatStyle] {
        (0..<beats).map { BeatStyle(accent: $0 == 0 ? .strong : .medium) }
    }

    /// Триольное деление: каждая четверть — три пролёта маятника.
    /// Начало четверти акцентировано, два внутренних удара тише.
    private static func tripletMeter(quarters: Int) -> [BeatStyle] {
        (0..<quarters * 3).map { index in
            guard index % 3 == 0 else { return BeatStyle(accent: .weak) }
            return BeatStyle(accent: index == 0 ? .strong : .medium)
        }
    }

    /// Составной размер: сильная доля в начале каждой группы восьмых
    private static func compoundMeter(beats: Int, groupSize: Int) -> [BeatStyle] {
        (0..<beats).map { BeatStyle(accent: $0 % groupSize == 0 ? .strong : .medium) }
    }

    /// Джент-рисунок: 12 шестнадцатых непрерывного «чуга» слабыми ударами,
    /// акценты на стартах групп 2+3+2+3+3+3 (единица — единственный сильный),
    /// одна пауза-«вдох» перед возвратом на единицу.
    private static func meshuggah() -> [BeatStyle] {
        var beats = Array(repeating: BeatStyle(accent: .weak), count: 12)
        beats[0] = BeatStyle(accent: .strong, color: .beatLime)
        beats[2] = BeatStyle(accent: .medium)
        beats[5] = BeatStyle(accent: .medium, color: .beatCyan)
        beats[7] = BeatStyle(accent: .medium, color: .beatAmber)
        beats[9] = BeatStyle(accent: .medium, color: .beatCoral)
        beats[11] = BeatStyle(accent: .mute)
        return beats
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

    /// Насколько точка останавливается, не доходя до центра боба: полуширина
    /// спокойной капсулы плюс радиус самой точки. Свет ложится ровно на грань,
    /// касаясь её, но внутрь не заходит.
    static let contactInset: CGFloat = beanWidth / 2 + 11

    static func contactLeftX(_ size: CGSize) -> CGFloat { leftX(size) + contactInset }
    static func contactRightX(_ size: CGSize) -> CGFloat { rightX(size) - contactInset }

    /// Положение света по номеру четверти и фазе внутри неё: одна четверть —
    /// один полный проход от боба к бобу. Косинусное сглаживание даёт
    /// замедление у краёв и максимальную скорость в центре.
    ///
    /// Принимает четверть и фазу, а не абсолютное время, намеренно: субударный
    /// интервал получается делением четверти, и обратное умножение промахивается
    /// мимо границы на доли наносекунды. Через floor это превращается в
    /// предыдущую четверть с фазой 0.999 — то есть в противоположный край.
    static func x(quarter: Int, phase: Double, size: CGSize) -> CGFloat {
        let eased = 0.5 - 0.5 * cos(.pi * phase)
        let l = contactLeftX(size)
        let span = contactRightX(size) - l
        return l + span * CGFloat(quarter % 2 == 0 ? eased : 1 - eased)
    }

    /// То же для произвольного момента непрерывного времени (шлейф кометы)
    static func x(at time: Double, quarterInterval: Double, size: CGSize) -> CGFloat {
        let quarter = Int(floor(time / quarterInterval))
        let phase = (time - Double(quarter) * quarterInterval) / quarterInterval
        return x(quarter: quarter, phase: phase, size: size)
    }
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
    let flashBrightness: Double
    /// На сколько субударов делится четверть: вспышка внутреннего субудара
    /// исходит из текущего положения света, а не от края
    var subdivision: Int = 1

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
                let quarterInterval = 60.0 / Double(max(bpm, 1))
                let subs = max(1, subdivision)
                let t = max(0, timeline.date.timeIntervalSince(startDate))
                // Субударная сетка выводится из четвертной, а не считается
                // отдельно: иначе на границе четверти они расходятся
                let quarterIndex = Int(t / quarterInterval)
                let quarterPhase = (t - Double(quarterIndex) * quarterInterval) / quarterInterval
                let subInQuarter = min(subs - 1, Int(quarterPhase * Double(subs)))
                let beatIndex = quarterIndex * subs + subInQuarter
                let style = pattern[beatIndex % beats]

                // Полноэкранная вспышка — событие основного пульса: она бывает
                // только на четвертных долях. Промежуточные субудары экран не
                // засвечивают, иначе триоль забивает сам пульс.
                let isMainBeat = subInQuarter == 0
                let hitX = PendulumGeometry.x(quarter: quarterIndex, phase: 0, size: size)
                let hitCenter = CGPoint(x: hitX, y: PendulumGeometry.midY(size))

                // Вспышка строго следует иерархии акцентов
                let quarterAccent: Double = switch style.accent {
                case .mute: 0
                case .weak: 0.22
                case .medium: 0.5
                case .strong: 1.0
                }
                let accentPeak = isMainBeat ? quarterAccent : 0
                let sinceQuarter = quarterPhase * quarterInterval
                let tempoDim = 0.35 + 0.65 * min(1, quarterInterval / 0.5)
                let calmFactor = (reduceMotion || dimFlashingLights) ? 0.12 : 1.0
                // Нежный световой «выдох» в цвете доли: невысокий пик
                // и плавное затухание, с учётом настройки яркости пользователя
                let flashPeak = accentPeak * tempoDim * calmFactor * flashBrightness
                let flash = flashPeak * exp(-sinceQuarter / 0.16)
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

/// Маятник фокус-режима: точка ездит между двумя бобами (одна четверть —
/// один полный проход), под линией — доли такта, над линией — номер такта.
/// Субудары (триоли) не меняют ход: они видны пульсацией самой точки.
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
    let indicatorsOnTop: Bool
    let topIndicatorY: CGFloat?
    let barCounterMode: BarCounterMode
    let barCounterBars: Int
    let barCounterMinutes: Int
    let countInBars: Int
    /// На сколько субударов делится четверть. Ход маятника от этого
    /// не зависит — субудары только пульсируют на летящей точке.
    var subdivision: Int = 1

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

    /// Субударов в четверти (1 — деления нет)
    private var subs: Int { max(1, subdivision) }

    /// Четвертей в такте
    private var quartersPerBar: Int { max(1, max(1, pattern.count) / subs) }

    /// Стиль четвертной доли — по её первому субудару
    private func style(ofQuarter quarter: Int) -> BeatStyle {
        style(ofBeat: quarter * subs)
    }

    /// Импульс субудара: короткий толчок с пиком ровно на щелчке, гаснет
    /// за 80–120 мс. Не двигает точку и не меняет её курс — только пульсирует
    /// форму и свечение там, где точка сейчас находится.
    private func subPulse(sinceHit: Double, subInterval: Double) -> Double {
        let decay = min(0.12, max(0.05, subInterval * 0.55))
        return exp(-sinceHit / decay)
    }

    /// Амплитуда пружинного пульса боба по силе удара
    private func pulseAmplitude(for accent: BeatAccent) -> Double {
        switch accent {
        case .mute: 0
        case .weak: 0.08
        case .medium: 0.14
        case .strong: 0.2
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                // Две сетки: четвертная задаёт ход маятника, субударная —
                // щелчки и пульсации. При subdivision = 1 они совпадают.
                let quarterInterval = 60.0 / Double(max(bpm, 1))
                let subInterval = quarterInterval / Double(subs)
                let t = max(0, timeline.date.timeIntervalSince(startDate))

                let beats = max(1, pattern.count)
                let barDuration = quarterInterval * Double(quartersPerBar)
                
                // Count-in: показываем только маятник между бобами с цифрой обратного отсчёта
                let countInDuration = barDuration * Double(countInBars)
                let isCountingIn = countInBars > 0 && t < countInDuration
                
                if isCountingIn {
                    let centerX = size.width / 2
                    let centerY = size.height / 2
                    
                    // Отсчёт идёт четвертями: 4 → 3 → 2 → 1, независимо от того,
                    // делится ли четверть на субудары
                    let quarterIndex = Int(t / quarterInterval)

                    let totalQuarters = countInBars * quartersPerBar
                    let quartersRemaining = totalQuarters - quarterIndex

                    let currentQuarter = quarterIndex % quartersPerBar
                    let countNumber = quartersPerBar - currentQuarter

                    // Прогресс внутри текущей четверти
                    let beatProgress = (t - Double(quarterIndex) * quarterInterval) / quarterInterval
                    
                    // Бобы по краям — КРУПНЕЕ в count-in
                    let midY = PendulumGeometry.midY(size)
                    let beanWidthBase = PendulumGeometry.beanWidth * 1.3  // Увеличили на 30%
                    let beanHeightBase = PendulumGeometry.beanHeight * 1.3
                    let leftX = PendulumGeometry.leftX(size)
                    let rightX = PendulumGeometry.rightX(size)
                    
                    let beanAppear = smooth(t / 0.3)
                    
                    // Последняя четверть count-in для спец-эффектов
                    let isLastBeat = quartersRemaining == 1
                    
                    // Бобы в count-in статичны — не мигают, только отсчёт меняется
                    for side in 0..<2 {
                        let beanX = side == 0 ? leftX : rightX

                        let scale = CGFloat(beanAppear)
                        let rect = CGRect(
                            x: beanX - beanWidthBase / 2 * scale,
                            y: midY - beanHeightBase / 2 * scale,
                            width: beanWidthBase * scale,
                            height: beanHeightBase * scale
                        )
                        let bean = Path(roundedRect: rect, cornerRadius: min(beanWidthBase, beanHeightBase) / 2 * scale)

                        // Базовый серый цвет — без пульса и вспышек
                        context.fill(bean, with: .color(.white.opacity(0.25 * beanAppear)))
                    }
                    
                    // Магическая трансформация цифры в точку на последнем ударе
                    if isLastBeat {
                        let rawProgress = beatProgress

                        // Многофазная трансформация
                        let shrinkPhase = min(1, rawProgress / 0.25)          // 0-25%: сжатие + вспышка
                        let morphPhase = max(0, min(1, (rawProgress - 0.25) / 0.35))  // 25-60%: морфинг
                        let movePhase = max(0, min(1, (rawProgress - 0.6) / 0.4))     // 60-100%: полёт
                        
                        // Позиция с плавным ускорением
                        let startX = leftX
                        let easedMove = movePhase * movePhase * (3 - 2 * movePhase)
                        let morphX = centerX + (startX - centerX) * easedMove
                        
                        // Размеры с драматичным сжатием
                        let baseSize: CGFloat = 80
                        let shrinkScale = 1.0 - shrinkPhase * 0.2
                        let morphScale = 1.0 - morphPhase * 0.75
                        let numberSize = baseSize * shrinkScale * morphScale
                        let dotSize: CGFloat = 26 * morphPhase
                        
                        // Драматическая вспышка в начале
                        let flashIntensity = exp(-shrinkPhase * 6) * 0.7
                        let numberOpacity = (1 - morphPhase) * (0.85 + flashIntensity) * beanAppear
                        let dotOpacity = morphPhase * beanAppear
                        
                        // Рисуем цифру с вспышкой
                        if numberOpacity > 0.01 && morphPhase < 0.95 {
                            // Внешнее гало
                            if shrinkPhase < 0.7 {
                                context.drawLayer { layer in
                                    layer.addFilter(.blur(radius: 25 * flashIntensity))
                                    layer.draw(
                                        Text("\(countNumber)")
                                            .font(.system(size: numberSize * (1 + flashIntensity * 0.6), weight: .semibold))
                                            .foregroundStyle(.white.opacity(flashIntensity * 0.5)),
                                        at: CGPoint(x: morphX, y: centerY)
                                    )
                                }
                            }
                            
                            // Основная цифра
                            context.draw(
                                Text("\(countNumber)")
                                    .font(.system(size: numberSize, weight: .semibold))
                                    .foregroundStyle(.white.opacity(numberOpacity)),
                                at: CGPoint(x: morphX, y: centerY)
                            )
                        }
                        
                        // Точка с многослойным свечением и motion blur
                        if dotOpacity > 0.01 {
                            let dotRect = CGRect(
                                x: morphX - dotSize / 2, y: centerY - dotSize / 2,
                                width: dotSize, height: dotSize
                            )
                            
                            // Внешний слой - мягкое свечение
                            context.drawLayer { layer in
                                layer.addFilter(.blur(radius: 26 * morphPhase))
                                layer.fill(
                                    Path(ellipseIn: dotRect.insetBy(dx: -20 * morphPhase, dy: -20 * morphPhase)),
                                    with: .color(.white.opacity(0.25 * dotOpacity))
                                )
                            }
                            
                            // Средний слой - яркое ядро
                            context.drawLayer { layer in
                                layer.addFilter(.blur(radius: 14 * morphPhase))
                                layer.fill(
                                    Path(ellipseIn: dotRect.insetBy(dx: -10 * morphPhase, dy: -10 * morphPhase)),
                                    with: .color(.white.opacity(0.65 * dotOpacity))
                                )
                            }
                            
                            // Motion blur trail
                            if movePhase > 0.15 {
                                for i in 1...6 {
                                    let trailProg = Double(i) / 6.0
                                    let trailX = morphX + (centerX - morphX) * trailProg * 0.35
                                    let trailAlpha = (1 - trailProg) * 0.12 * movePhase * dotOpacity
                                    let trailSize = dotSize * (1 - trailProg * 0.25)
                                    
                                    let trailRect = CGRect(
                                        x: trailX - trailSize / 2, y: centerY - trailSize / 2,
                                        width: trailSize, height: trailSize
                                    )
                                    context.fill(Path(ellipseIn: trailRect), with: .color(.white.opacity(trailAlpha)))
                                }
                            }
                            
                            // Основная точка
                            context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(dotOpacity)))
                            
                            // Внутренний блик
                            let highlight = dotRect.insetBy(dx: dotSize * 0.3, dy: dotSize * 0.3)
                            context.fill(Path(ellipseIn: highlight), with: .color(.white.opacity(0.5 * dotOpacity)))
                        }
                    } else {
                        // Обычная цифра с spring пульсом
                        let pulseFactor = 1.0 + 0.1 * exp(-beatProgress * 7) * cos(beatProgress * 12)
                        let numberSize = 80 * CGFloat(max(0.95, pulseFactor))
                        let numberOpacity = 0.85 * beanAppear
                        
                        context.draw(
                            Text("\(countNumber)")
                                .font(.system(size: numberSize, weight: .semibold))
                                .foregroundStyle(.white.opacity(numberOpacity)),
                            at: CGPoint(x: centerX, y: centerY)
                        )
                    }
                    
                    // Не показываем остальной UI во время count-in
                    return
                }

                let midY = PendulumGeometry.midY(size)
                let beanWidth = PendulumGeometry.beanWidth
                let beanHeight = PendulumGeometry.beanHeight
                let leftX = PendulumGeometry.leftX(size)
                let rightX = PendulumGeometry.rightX(size)
                let centerX = size.width / 2

                // Ход маятника считается по четверти: полный проход от края
                // до края занимает ровно одну четвертную долю, и края он
                // касается только на них. Субудары ход не трогают.
                let quarterIndex = Int(t / quarterInterval)
                let phase = (t - Double(quarterIndex) * quarterInterval) / quarterInterval
                let x = PendulumGeometry.x(quarter: quarterIndex, phase: phase, size: size)
                let speed = sin(.pi * phase)

                // Субудары выводятся из фазы четверти, а не из отдельного
                // деления времени: так граница четверти для них ровно та же,
                // и акцент не может «опоздать» на кадр
                let subInQuarter = min(subs - 1, Int(phase * Double(subs)))
                let subBeat = quarterIndex * subs + subInQuarter
                let isMainBeat = subInQuarter == 0
                let sinceHit = (phase - Double(subInQuarter) / Double(subs)) * quarterInterval

                // Импульс субудара считаем один раз: его несут и летящая точка,
                // и активный индикатор. Беззвучный субудар импульса не даёт.
                let subStyle = style(ofBeat: subBeat)
                let subHit = (subs > 1 && !isMainBeat && subStyle.accent != .mute)
                    ? subPulse(sinceHit: sinceHit, subInterval: subInterval)
                    : 0

                // Позиция в такте (с учётом count-in)
                let currentQuarter = quarterIndex % quartersPerBar
                let barIndex = Int(t / barDuration) - countInBars
                
                // Плавное появление UI после count-in и уменьшение бобов
                // UI появляется быстрее (0.7s), бобы уменьшаются чуть дольше (0.6s)
                // Переходы «выхода из отсчёта» имеют смысл только если отсчёт был:
                // иначе сцена на старте зря съезжает с увеличенного размера
                // и проявляется как раз в тот момент, когда бьёт первая доля
                let hadCountIn = countInBars > 0
                let timeSinceCountIn = max(0, t - countInDuration)
                let uiAppear = hadCountIn ? smooth(min(1, timeSinceCountIn / 0.7)) : 1

                // Бобы плавно уменьшаются от увеличенного размера count-in до нормального
                let beanSizeTransition = hadCountIn && timeSinceCountIn < 0.6
                    ? 1.3 - 0.3 * smooth(timeSinceCountIn / 0.6)
                    : 1.0

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
                    let hitBeat = subBeat - back
                    guard hitBeat >= 0 else { continue }
                    let hitStyle = style(ofBeat: hitBeat)
                    guard hitStyle.accent != .mute else { continue }
                    let hitQuarter = hitBeat / subs
                    let hitSub = hitBeat % subs
                    let hitTime = Double(hitQuarter) * quarterInterval + Double(hitSub) * subInterval
                    let age = t - hitTime
                    guard age < waveDuration else { continue }
                    // Волна расходится оттуда, где свет был на этом ударе:
                    // на четверти — ровно от края, на субударе — из середины пути
                    let waveX = PendulumGeometry.x(
                        quarter: hitQuarter,
                        phase: Double(hitSub) / Double(subs),
                        size: size
                    )
                    waves.append((CGPoint(x: waveX, y: midY), age, hitStyle))
                }

                if !waves.isEmpty && uiAppear > 0.01 {
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
                                let accentBoost: Double = switch wave.style.accent {
                                case .strong: 1.25
                                case .weak: 0.65
                                default: 1
                                }
                                let contribution = band * fade * accentBoost
                                if contribution > intensity {
                                    intensity = contribution
                                    waveColor = wave.style.color
                                }
                            }
                            guard intensity > 0.03 else { continue }
                            let dotRadius = 0.8 + 0.6 * intensity
                            let accessibilityDim = reduceMotion ? 0.7 : 1.0
                            let finalOpacity = 0.18 * intensity * accessibilityDim * uiAppear
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: point.x - dotRadius, y: point.y - dotRadius,
                                    width: dotRadius * 2, height: dotRadius * 2
                                )),
                                with: .color(waveColor.opacity(finalOpacity))
                            )
                        }
                    }
                }

                // Бобы по краям: рождаются при первом ударе точки и взрываются,
                // когда свет в них попадает
                for side in 0..<2 {
                    let beanX = side == 0 ? leftX : rightX

                    // Сцена стоит на месте с первого кадра: экран фокус-режима
                    // и так въезжает целиком, а собственный фейд съедал бы
                    // ровно первый удар — вспышку, взрыв боба и старт полёта
                    let appear = 1.0

                    // Боб принимает только четвертные доли: левый — чётные,
                    // правый — нечётные. Субудары его не трогают, иначе край
                    // вспыхивал бы, когда точка летит посередине.
                    let quartersSinceOwnHit = ((quarterIndex - side) % 2 + 2) % 2
                    let lastOwnQuarter = quarterIndex - quartersSinceOwnHit
                    let sinceOwnHit = t - Double(lastOwnQuarter) * quarterInterval
                    let wasHit = lastOwnQuarter >= 0
                    // Пружинный пульс по силе удара: сильная доля бьёт плотнее,
                    // беззвучная проходит без пульса
                    let ownStyle = style(ofQuarter: lastOwnQuarter)
                    let pulse = wasHit
                        ? exp(-sinceOwnHit / 0.16) * cos(sinceOwnHit * 18) * pulseAmplitude(for: ownStyle.accent)
                        : 0

                    let scale = CGFloat(appear * (1 + pulse))

                    // Контакт: боб на подлёте стоит спокойно, а удар принимает
                    // телом — сначала его вдавливает (уже и выше), затем он
                    // отпружинивает с перелётом и оседает. Разность экспонент
                    // даёт естественную двухфазность: сжатие, потом отдача.
                    // Насколько боб податлив: беззвучный — камень, удар его
                    // не деформирует, свет просто отскакивает прочь
                    let give: Double = switch ownStyle.accent {
                    case .mute: 0
                    case .weak: 0.55
                    case .medium: 0.85
                    case .strong: 1.0
                    }
                    let squash = wasHit ? exp(-sinceOwnHit / 0.04) * give : 0
                    let reboundRaw = wasHit
                        ? (exp(-sinceOwnHit / 0.07) - exp(-sinceOwnHit / 0.04)) * give
                        : 0
                    let rebound = max(0, reboundRaw) / 0.203

                    let widthFactor = 1 - 0.26 * squash + 0.5 * rebound
                    let heightFactor = 1 + 0.2 * squash - 0.08 * rebound
                    let width = beanWidth * beanSizeTransition * CGFloat(widthFactor) * scale
                    let height = beanHeight * beanSizeTransition * CGFloat(heightFactor) * scale

                    // Отдача: под ударом боб подаётся прочь от точки и возвращается
                    let recoil = CGFloat(squash * 7) * (side == 0 ? -1 : 1)

                    let rect = CGRect(
                        x: beanX + recoil - width / 2, y: midY - height / 2,
                        width: width, height: height
                    )
                    let bean = Path(roundedRect: rect, cornerRadius: min(width, height) / 2)

                    // Ровный серый: боб светится только от собственного удара
                    let base = 0.22
                    context.fill(bean, with: .color(.white.opacity(base * appear)))

                    // Цвет — событие удара, а не подлёта: боб растёт и раздувается
                    // серым, а вспыхивает своим цветом ровно в момент попадания
                    // и тут же гаснет. Яркость по иерархии акцентов: пауза
                    // не светится, слабый — вполсилы, сильный — ярче обычного
                    if wasHit, ownStyle.accent != .mute {
                        let glowScale: Double = switch ownStyle.accent {
                        case .weak: 0.5
                        case .strong: 1.15
                        default: 1.0
                        }
                        let ignite = exp(-sinceOwnHit / 0.18)
                        let glow = min(0.95, ignite * glowScale)
                        if glow > 0.01 {
                            context.fill(
                                bean,
                                with: .color(ownStyle.color.opacity(glow * appear))
                            )
                        }
                    }
                }

                // Мини-бобы долей под маятником: форма кодирует акцент —
                // длинный залитый боб — сильная доля, обычный залитый — средняя,
                // сплющенный маленький контур — беззвучная (mute). Цвет — цвет
                // доли. Весь рисунок такта виден сразу, целиком.
                // Доли паттерна сворачиваются в группы: у триолей ряд
                // показывает четыре четверти 4/4, а не двенадцать пролётов
                let indicatorCount = quartersPerBar
                let indicatorSpacing: CGFloat = indicatorCount > 8 ? 18 : 24
                let indicatorY: CGFloat
                if indicatorsOnTop {
                    indicatorY = topIndicatorY ?? (midY - 96)
                } else {
                    indicatorY = midY + 96
                }
                let rowWidth = indicatorSpacing * CGFloat(indicatorCount - 1)
                let rowAppear = uiAppear
                // Внутри группы «горит» вся четверть: её тепло считаем от
                // момента, когда прозвучала первая доля группы
                // Активная доля переключается только на новой четверти:
                // субудары внутри неё основной индикатор не трогают
                let currentIndicator = currentQuarter
                let sinceIndicatorHit = t - Double(quarterIndex) * quarterInterval
                for beat in 0..<indicatorCount {
                    let beatStyle = style(ofQuarter: beat)
                    let heat = beat == currentIndicator ? exp(-sinceIndicatorHit / 0.35) : 0
                    // Субудары отзываются внутри активной доли — короче и слабее
                    // четвертного отклика, и сам индикатор они не переключают
                    let subHeat = beat == currentIndicator ? subHit : 0

                    var miniWidth: CGFloat
                    var miniHeight: CGFloat
                    switch beatStyle.accent {
                    case .mute:
                        miniWidth = 8
                        miniHeight = 4
                    case .weak:
                        miniWidth = 8
                        miniHeight = 5
                    case .medium:
                        miniWidth = 6
                        miniHeight = 14
                    case .strong:
                        miniWidth = 7
                        miniHeight = 22
                    }
                    // На своей доле мини-боб подрастает и вспыхивает
                    let growth: Double = 1 + 0.25 * heat + 0.16 * subHeat
                    let grow = CGFloat(growth)
                    miniWidth *= grow
                    miniHeight *= grow

                    let indicatorX = centerX - rowWidth / 2 + indicatorSpacing * CGFloat(beat)
                    let miniRect = CGRect(
                        x: indicatorX - miniWidth / 2, y: indicatorY - miniHeight / 2,
                        width: miniWidth, height: miniHeight
                    )
                    let miniBean = Path(
                        roundedRect: miniRect,
                        cornerRadius: min(miniWidth, miniHeight) / 2
                    )
                    let isActive = beat == currentIndicator
                    // Цвет: верхние неактивные — единый серый; активная — цвет доли
                    let baseColor: Color = isActive ? beatStyle.color : (indicatorsOnTop ? Color.white.opacity(0.8) : beatStyle.color)

                    switch beatStyle.accent {
                    case .mute:
                        // Пауза — пустой сплющенный контур
                        let strokeOpacity: Double = isActive ? (0.3 + 0.5 * heat + 0.3 * subHeat) * rowAppear : (indicatorsOnTop ? 0.35 * rowAppear : (0.3 + 0.5 * heat) * rowAppear)
                        context.stroke(
                            miniBean,
                            with: .color(baseColor.opacity(strokeOpacity)),
                            lineWidth: 1
                        )
                    case .weak, .medium, .strong:
                        // Залитые: нормализуем непрозрачность для верхних неактивных,
                        // чтобы длина боба не воспринималась как бОльшая яркость
                        let activeBase: Double = switch beatStyle.accent {
                        case .strong: 0.45
                        case .medium: 0.3
                        default: 0.25
                        }
                        let activeOpacity = min(1, activeBase + 0.55 * heat + 0.3 * subHeat) * rowAppear
                        let passiveOpacity = indicatorsOnTop ? (0.38 * rowAppear) : activeOpacity
                        let finalOpacity = isActive ? activeOpacity : passiveOpacity
                        context.fill(
                            miniBean,
                            with: .color(baseColor.opacity(finalOpacity))
                        )
                    }
                }

                // Счётчик тактов или таймер под мини-бобами
                if barCounterMode != .off && uiAppear > 0.01 {
                    let counterY = indicatorY + 32
                    let counterText: String
                    
                    if barCounterMode == .byBar {
                        // Обратный отсчёт тактов с суффиксом "b"
                        let totalBars = barCounterBars
                        let barsRemaining = max(0, totalBars - barIndex)
                        counterText = "\(barsRemaining) b"
                    } else {
                        // Обратный отсчёт времени (by counter)
                        let totalSeconds = barCounterMinutes * 60
                        let elapsed = Int(t)
                        let remaining = max(0, totalSeconds - elapsed)
                        let minutes = remaining / 60
                        let seconds = remaining % 60
                        counterText = String(format: "%d:%02d", minutes, seconds)
                    }
                    
                    context.draw(Text(counterText)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5 * rowAppear * uiAppear)),
                        at: CGPoint(x: centerX, y: counterY)
                    )
                }

                // Комета-шлейф: деликатный, чтобы героем оставалась точка;
                // при Reduce Motion выключен
                if speed > 0.15, !reduceMotion {
                    for ghost in 1...4 {
                        let ghostTime = t - Double(ghost) * 0.022
                        guard ghostTime >= 0 else { break }
                        let gX = PendulumGeometry.x(
                            at: ghostTime, quarterInterval: quarterInterval, size: size
                        )
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
                let dotAppear: CGFloat = 1

                // Базовый размер точки: увеличен в count-in, плавно уменьшается после
                let dotBaseDiameter: CGFloat = hadCountIn && timeSinceCountIn < 0.6
                    ? 26 - 4 * CGFloat(smooth(timeSinceCountIn / 0.6))
                    : 22
                let dotDiameter: CGFloat = dotBaseDiameter * CGFloat(0.5 + 0.5 * dotAppear)
                
                // Вытягивание по ходу движения, объём сохраняется. В боб точка
                // не превращается: она в него бьёт и остаётся собой
                let stretch = reduceMotion ? 1.0 : (1 + 0.22 * speed)
                var dotWidth = dotDiameter * CGFloat(stretch)
                var dotHeight = dotDiameter / CGFloat(stretch)

                // Удар о боб: на контакте точка расплющивается о капсулу и
                // упруго восстанавливается, как мяч о стену. На беззвучной доле
                // удара нет вовсе — бить не обо что, поэтому точка не пружинит,
                // а просто разворачивается. Траектория при этом одна для всех.
                let impactQuarter = phase < 0.5 ? quarterIndex : quarterIndex + 1
                let strikes = style(ofQuarter: impactQuarter).accent != .mute
                let impact = strikes
                    ? exp(-(phase < 0.5 ? phase : 1 - phase) * quarterInterval / 0.06)
                    : 0
                if impact > 0.01, !reduceMotion {
                    dotWidth *= CGFloat(1 - 0.42 * impact)
                    dotHeight *= CGFloat(1 + 0.3 * impact)
                }

                let dotRect = CGRect(
                    x: x - dotWidth / 2, y: midY - dotHeight / 2,
                    width: dotWidth, height: dotHeight
                )
                let dotCornerRadius = min(dotWidth, dotHeight) / 2
                let dotShape = Path(roundedRect: dotRect, cornerRadius: dotCornerRadius)

                // Свечение дышит в ритм: вспыхивает на ударе, успокаивается
                // в полёте. Субудары его не трогают — маятник живёт четвертями,
                // а триоль отзывается только в мини-бобах
                let glowPulse = style(ofQuarter: quarterIndex).accent == .mute
                    ? 0
                    : exp(-phase * quarterInterval / 0.15)
                // Более яркое свечение в count-in, плавно уменьшается
                let glowBase = timeSinceCountIn < 0.6
                    ? 0.65 - 0.05 * smooth(timeSinceCountIn / 0.6)
                    : 0.6
                let glowOpacity = (glowBase + 0.35 * glowPulse) * dotAppear
                // Более широкое свечение в count-in
                let glowBlur = timeSinceCountIn < 0.6
                    ? 18 - 2 * CGFloat(smooth(timeSinceCountIn / 0.6))
                    : 16
                let glowInsetBase = timeSinceCountIn < 0.6
                    ? -12 + 2 * CGFloat(smooth(timeSinceCountIn / 0.6))
                    : -10
                let glowInset = glowInsetBase - CGFloat(glowPulse) * (timeSinceCountIn < 0.6 ? 5 : 4)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: glowBlur))
                    layer.fill(
                        Path(roundedRect: dotRect.insetBy(dx: glowInset, dy: glowInset),
                             cornerRadius: dotCornerRadius - glowInset),
                        with: .color(.white.opacity(glowOpacity))
                    )
                }
                // Точка всегда белая: цвет доли несёт боб, который она взрывает
                context.fill(dotShape, with: .color(.white.opacity(Double(dotAppear))))
            }
        }
        .allowsHitTesting(false)
    }
}

struct FocusMetronomeContainer: View {
    @State private var startDate = Date()
    @State private var bpm: Int = 90
    @State private var preset: RhythmPreset = .fourFour

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            MetronomeFlashView(startDate: startDate, bpm: bpm, pattern: preset.pattern, flashBrightness: 0.8)

            MetronomePendulumView(
                startDate: startDate,
                bpm: bpm,
                pattern: preset.pattern,
                indicatorsOnTop: false,
                topIndicatorY: nil,
                barCounterMode: .off,
                barCounterBars: 16,
                barCounterMinutes: 5,
                countInBars: 0
            )
        }
    }
}


#Preview {
    FocusMetronomeContainer()
}
