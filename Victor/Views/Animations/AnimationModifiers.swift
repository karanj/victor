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
    static let standardDuration: Double = 0.2

    /// Quick duration for subtle transitions
    static let quickDuration: Double = 0.15

    /// Slow duration for emphasis transitions
    static let emphasisDuration: Double = 0.3
}

// MARK: - Pulse Animation Modifier

/// Adds a gentle pulse animation to a view
struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? 1.1 : 1.0)
            .opacity(isPulsing && isActive ? 0.8 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
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
    @State private var shakeOffset: CGFloat = 0
    @Binding var trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, shouldShake in
                if shouldShake {
                    withAnimation(.interpolatingSpring(stiffness: 500, damping: 10)) {
                        shakeOffset = -10
                    }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation(.interpolatingSpring(stiffness: 500, damping: 10)) {
                            shakeOffset = 10
                        }
                    }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        withAnimation(.interpolatingSpring(stiffness: 500, damping: 15)) {
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
    @State private var opacity: Double = 0
    let duration: Double
    let delay: Double

    init(duration: Double = 0.15, delay: Double = 0) {
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
                            opacity = 1
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: duration)) {
                        opacity = 1
                    }
                }
            }
    }
}

extension View {
    /// Adds a fade-in animation when the view appears
    func fadeIn(duration: Double = 0.15, delay: Double = 0) -> some View {
        modifier(FadeInModifier(duration: duration, delay: delay))
    }
}

// MARK: - Save Indicator Animation

/// Special animation for save indicator with pop-in effect
struct SaveIndicatorAnimationModifier: ViewModifier {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    let isShowing: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShowing ? scale : 0.5)
            .opacity(isShowing ? opacity : 0)
            .onChange(of: isShowing) { _, newValue in
                if newValue {
                    // Pop-in animation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.0
                        opacity = 1.0
                    }

                    // Subtle pulse after appearing
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            scale = 1.05
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        scale = 0.5
                        opacity = 0
                    }
                }
            }
            .onAppear {
                if isShowing {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.0
                        opacity = 1.0
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
    @State private var offset: CGFloat
    let edge: Edge
    let duration: Double

    init(edge: Edge, distance: CGFloat = 20, duration: Double = 0.2) {
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
    func slideIn(from edge: Edge, distance: CGFloat = 20, duration: Double = 0.2) -> some View {
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
    @State private var isHovered = false
    let scale: CGFloat

    init(scale: CGFloat = 1.02) {
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
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
