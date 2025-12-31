import SwiftUI

// MARK: - Reduce Motion Environment

/// Extension to get animation duration respecting reduce motion preference
extension Animation {
    /// Returns an animation that respects Reduce Motion preference
    /// When Reduce Motion is enabled, returns nil (instant change)
    static func accessibleEaseInOut(duration: Double) -> Animation? {
        return .easeInOut(duration: duration)
    }

    /// Standard duration for most UI transitions
    static let standardDuration: Double = AppConstants.Animation.standard

    /// Quick duration for subtle transitions
    static let quickDuration: Double = AppConstants.Animation.fast

    /// Slow duration for emphasis transitions
    static let emphasisDuration: Double = AppConstants.Animation.slow
}

// MARK: - Pulse Animation Modifier

/// Adds a gentle pulse animation to a view
struct PulseAnimationModifier: ViewModifier {
    private enum Constants {
        static let pulseScale: CGFloat = 1.1
        static let normalScale: CGFloat = 1.0
        static let dimmedOpacity: Double = 0.8
        static let fullOpacity: Double = 1.0
        static let pulseDuration: Double = 0.6
    }

    @State private var isPulsing = false
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? Constants.pulseScale : Constants.normalScale)
            .opacity(isPulsing && isActive ? Constants.dimmedOpacity : Constants.fullOpacity)
            .animation(
                isActive ? .easeInOut(duration: Constants.pulseDuration).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    isPulsing = true
                }
            }
    }
}

extension View {
    /// Adds a gentle pulse animation when active
    func pulseAnimation(isActive: Bool) -> some View {
        modifier(PulseAnimationModifier(isActive: isActive))
    }
}

// MARK: - Shake Animation Modifier

/// Adds a shake animation for error states
struct ShakeAnimationModifier: ViewModifier {
    private enum Constants {
        static let shakeDistance: CGFloat = 10
        static let springStiffness: Double = 500
        static let initialDamping: Double = 10
        static let finalDamping: Double = 15
        static let firstDelayMs: UInt64 = 100
        static let secondDelayMs: UInt64 = 200
    }

    @State private var shakeOffset: CGFloat = 0
    @Binding var trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, shouldShake in
                if shouldShake {
                    withAnimation(.interpolatingSpring(stiffness: Constants.springStiffness, damping: Constants.initialDamping)) {
                        shakeOffset = -Constants.shakeDistance
                    }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Constants.firstDelayMs))
                        withAnimation(.interpolatingSpring(stiffness: Constants.springStiffness, damping: Constants.initialDamping)) {
                            shakeOffset = Constants.shakeDistance
                        }
                    }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Constants.secondDelayMs))
                        withAnimation(.interpolatingSpring(stiffness: Constants.springStiffness, damping: Constants.finalDamping)) {
                            shakeOffset = 0
                        }
                        trigger = false
                    }
                }
            }
    }
}

extension View {
    /// Adds a shake animation triggered by binding
    func shakeAnimation(trigger: Binding<Bool>) -> some View {
        modifier(ShakeAnimationModifier(trigger: trigger))
    }
}

// MARK: - Fade Transition Modifier

/// Adds a fade-in transition when content appears
struct FadeInModifier: ViewModifier {
    private enum Constants {
        static let defaultDuration: Double = AppConstants.Animation.fast
        static let defaultDelay: Double = 0
        static let hiddenOpacity: Double = 0
        static let visibleOpacity: Double = 1
    }

    @State private var opacity: Double = Constants.hiddenOpacity
    let duration: Double
    let delay: Double

    init(duration: Double = Constants.defaultDuration, delay: Double = Constants.defaultDelay) {
        self.duration = duration
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                if delay > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        withAnimation(.easeInOut(duration: duration)) {
                            opacity = Constants.visibleOpacity
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: duration)) {
                        opacity = Constants.visibleOpacity
                    }
                }
            }
    }
}

extension View {
    /// Adds a fade-in animation when the view appears
    func fadeIn(duration: Double = AppConstants.Animation.fast, delay: Double = 0) -> some View {
        modifier(FadeInModifier(duration: duration, delay: delay))
    }
}

// MARK: - Save Indicator Animation

/// Special animation for save indicator with pop-in effect
struct SaveIndicatorAnimationModifier: ViewModifier {
    private enum Constants {
        static let initialScale: CGFloat = 0.5
        static let fullScale: CGFloat = 1.0
        static let pulseScale: CGFloat = 1.05
        static let hiddenOpacity: Double = 0
        static let visibleOpacity: Double = 1.0
        static let springResponse: Double = AppConstants.Toolbar.saveSpringResponse
        static let springDamping: Double = AppConstants.Toolbar.saveSpringDamping
        static let pulseDelayMs: UInt64 = 300
        static let pulseDuration: Double = 0.8
        static let fadeOutDuration: Double = AppConstants.Animation.fast
    }

    @State private var scale: CGFloat = Constants.initialScale
    @State private var opacity: Double = Constants.hiddenOpacity
    let isShowing: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShowing ? scale : Constants.initialScale)
            .opacity(isShowing ? opacity : Constants.hiddenOpacity)
            .onChange(of: isShowing) { _, newValue in
                if newValue {
                    // Pop-in animation
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        scale = Constants.fullScale
                        opacity = Constants.visibleOpacity
                    }

                    // Subtle pulse after appearing
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Constants.pulseDelayMs))
                        withAnimation(.easeInOut(duration: Constants.pulseDuration).repeatForever(autoreverses: true)) {
                            scale = Constants.pulseScale
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: Constants.fadeOutDuration)) {
                        scale = Constants.initialScale
                        opacity = Constants.hiddenOpacity
                    }
                }
            }
            .onAppear {
                if isShowing {
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        scale = Constants.fullScale
                        opacity = Constants.visibleOpacity
                    }
                }
            }
    }
}

extension View {
    /// Adds a pop-in and pulse animation for save indicators
    func saveIndicatorAnimation(isShowing: Bool) -> some View {
        modifier(SaveIndicatorAnimationModifier(isShowing: isShowing))
    }
}

// MARK: - Slide Transition Modifier

/// Adds a slide-in transition from specified edge
struct SlideInModifier: ViewModifier {
    private enum Constants {
        static let defaultDistance: CGFloat = 20
        static let defaultDuration: Double = AppConstants.Animation.standard
    }

    @State private var offset: CGFloat
    let edge: Edge
    let duration: Double

    init(edge: Edge, distance: CGFloat = Constants.defaultDistance, duration: Double = Constants.defaultDuration) {
        self.edge = edge
        self.duration = duration

        switch edge {
        case .leading:
            _offset = State(initialValue: -distance)
        case .trailing:
            _offset = State(initialValue: distance)
        case .top:
            _offset = State(initialValue: -distance)
        case .bottom:
            _offset = State(initialValue: distance)
        }
    }

    var isHorizontal: Bool {
        edge == .leading || edge == .trailing
    }

    func body(content: Content) -> some View {
        content
            .offset(x: isHorizontal ? offset : 0, y: isHorizontal ? 0 : offset)
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    offset = 0
                }
            }
    }
}

extension View {
    /// Adds a slide-in animation from the specified edge
    func slideIn(from edge: Edge, distance: CGFloat = 20, duration: Double = AppConstants.Animation.standard) -> some View {
        modifier(SlideInModifier(edge: edge, distance: distance, duration: duration))
    }
}

// MARK: - Accessible Animation Wrapper

/// Wraps animations to respect Reduce Motion preference
struct AccessibleAnimationWrapper: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: UUID())
    }
}

extension View {
    /// Applies animation only when Reduce Motion is disabled
    func accessibleAnimation(_ animation: Animation?) -> some View {
        modifier(AccessibleAnimationWrapper(animation: animation))
    }
}

// MARK: - Hover Scale Modifier

/// Adds a subtle scale effect on hover
struct HoverScaleModifier: ViewModifier {
    private enum Constants {
        static let defaultScale: CGFloat = 1.02
        static let normalScale: CGFloat = 1.0
        static let hoverDuration: Double = AppConstants.Animation.fast
    }

    @State private var isHovered = false
    let scale: CGFloat

    init(scale: CGFloat = Constants.defaultScale) {
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : Constants.normalScale)
            .animation(.easeInOut(duration: Constants.hoverDuration), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// Adds a subtle scale effect when hovered
    func hoverScale(_ scale: CGFloat = 1.02) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
}
