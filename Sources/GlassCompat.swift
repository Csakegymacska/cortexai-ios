import SwiftUI

// MARK: - Liquid Glass (iOS 26)
//
// A 26-os rendszer új anyaga az üveg: a felület a mögötte lévő tartalmat töri meg,
// és fénytöréssel emelkedik ki. Ez a fájl egy helyre teszi, hogy az egész appban
// ugyanaz legyen a viselkedés, és hogy a régebbi rendszerre épített felület se
// törjön el, ha valaki lejjebb veszi a deployment targetet.
//
// A `GlassEffectContainer` azért kell, hogy az egymás mellett lévő üvegfelületek
// összeolvadjanak, amikor közel kerülnek — enélkül minden külön üvegnek látszik,
// és a hatás elveszik.

extension View {
    /// Üveg háttér, ami visszafelé kompatibilis: 26 alatt ugyanaz a felület, csak
    /// a régi, tömör háttérrel.
    ///
    /// A `COMPAT_SDK` kapcsoló azért kell, mert a `.glassEffect` szimbólum nem
    /// létezik a régi SDK-ban: az `if #available` csak futásidőben dönt, fordításkor
    /// nem. Régi Xcode-dal (SDK < 26) ezért ezt a kapcsolót adjuk át, és a fájl a
    /// tömör hátteret fordítja — így is lesz IPA, csak Liquid Glass nélkül.
    @ViewBuilder
    func cortexGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if !COMPAT_SDK
        if #available(iOS 26.0, *) {
            let base: Glass = .regular
            let withTint = tint.map { base.tint($0) } ?? base
            let glass = interactive ? withTint.interactive(true) : withTint
            self.glassEffect(glass, in: shape)
        } else {
            self.background { LayeredGlass(shape: shape, tint: tint) }
        }
        #else
        self.background { LayeredGlass(shape: shape, tint: tint) }
        #endif
    }

    /// Görgetési él-hatás: a tartalom a képernyő széle felé halványul, ahogy az
    /// üveg alatt elhalad. 26-on a rendszeres lágy átmenet, korábban semmi.
    @ViewBuilder
    func cortexScrollEdge() -> some View {
        #if !COMPAT_SDK
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Az üvegfelületek csoportja. A `spacing` mondja meg, milyen közel kell lenniük
/// ahhoz, hogy összeolvadjanak.
struct CortexGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if !COMPAT_SDK
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Folyadék-kiemelés
//
// Nyomáskor a felület kicsit „megnyúlik", mint egy vízcsepp. Ez az iOS 26-os
// interakciós nyelv, és a meglévő spring-animációnkkal együtt adja a textúrát.

struct LiquidPress: ButtonStyle {
    var tint: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(CortexMotion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Színátmenetes él
//
// A 26-os dizájn egyik jellemzője, hogy a panelek éle nem vonal, hanem fény:
// felül világosabb, alul eltűnik. Ez a modifier ezt adja bármelyik lekerekített
// téglalapra, és ugyanazt a színvilágot használja, mint a márka.

struct GradientEdge: ViewModifier {
    var radius: CGFloat = Theme.radiusSmall
    var strength: Double = 0.18

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(strength),
                                 Color.white.opacity(strength * 0.18),
                                 Theme.violet.opacity(strength * 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

extension View {
    func gradientEdge(radius: CGFloat = Theme.radiusSmall, strength: Double = 0.18) -> some View {
        modifier(GradientEdge(radius: radius, strength: strength))
    }
}


/// Réteges üveg-hatás 26 alá: anyag + fénymenetes felső réteg + gradiens él +
/// mély árnyék. A 26-os igazi Liquid Glass helyett ez adja a minőséget ott,
/// ahol a rendszer nem tud üveget (kompatibilitási build, régebbi iOS).
struct LayeredGlass<S: InsettableShape>: View {
    let shape: S
    var tint: Color?

    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.11), Color.white.opacity(0.02),
                             (tint ?? Color.white).opacity(0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.24), Color.white.opacity(0.05),
                             (tint ?? Color.white).opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
            .shadow(color: .black.opacity(0.38), radius: 11, y: 6)
    }
}
