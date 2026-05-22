import AppKit
import Metal
import MetalKit
import SwiftUI

// Uniforms passed to every reactive shader.
struct ReactiveUniforms {
    var mousePosition:    SIMD2<Float>  // logical points, top-left origin
    var resolution:       SIMD2<Float>  // view size in logical points
    var time:             Float         // seconds since view creation
    var indicatorOpacity: Float         // 0-1 fade value
    var cornerRadius:     Float         // dock corner radius in logical points
}

// MARK: - Base class

class ReactiveBackgroundView: NSView, MTKViewDelegate {

    var reactiveStyle: ReactiveStyle = .lockOn {
        didSet { if oldValue != reactiveStyle { rebuildPipeline() } }
    }
    var cornerRadius: CGFloat = 0

    private(set) var mousePosition: CGPoint?
    private var trackingArea:      NSTrackingArea?
    private var localMouseMonitor: Any?

    // Metal
    private var metalView:     MTKView!
    private var device:        MTLDevice!
    private var commandQueue:  MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?

    // Fade state — interpolated in draw(in:) without a timer
    private var startTime:      CFTimeInterval = CACurrentMediaTime()
    private var isHovering      = false
    private var hoverStartTime: CFTimeInterval = 0
    private var hoverEndTime:   CFTimeInterval = 0
    private var indicatorOpacity: Float = 0

    override var isFlipped: Bool { true }

    // MARK: - Overridable appearance

    var backgroundColor: NSColor { .black }
    var indicatorColor:  NSColor { .red }
    var indicatorRadius: CGFloat { 20 }

    // MARK: - Overridable shader names

    var vertexShaderName: String { "reactiveVertex" }
    var fragmentShaderName: String {
        switch reactiveStyle {
        case .lockOn:     return "lockOnFragment"
        case .liquidFill: return "liquidFillFragment"
        }
    }

    // MARK: - Overridable lifecycle hooks

    func mouseDidEnter(at point: CGPoint) {}
    func mouseDidMove(to point:  CGPoint) {}
    func mouseDidExit() {}

    // MARK: - Overridable uniforms

    /// Override to supply custom or extended uniform data.
    func makeUniforms(time: Float, opacity: Float) -> ReactiveUniforms {
        let pos = mousePosition ?? .zero
        return ReactiveUniforms(
            mousePosition:    SIMD2<Float>(Float(pos.x), Float(pos.y)),
            resolution:       SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
            time:             time,
            indicatorOpacity: opacity,
            cornerRadius:     Float(cornerRadius)
        )
    }

    /// Override to bind additional buffers or textures to the encoder.
    func configureEncoder(_ encoder: MTLRenderCommandEncoder,
                          uniforms: inout ReactiveUniforms) {}

    // MARK: - Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device       = device
        self.commandQueue = device.makeCommandQueue()

        metalView = MTKView(frame: bounds, device: device)
        metalView.autoresizingMask    = [.width, .height]
        metalView.delegate            = self
        metalView.clearColor          = MTLClearColorMake(0, 0, 0, 0)
        metalView.layer?.isOpaque     = false
        metalView.colorPixelFormat    = .bgra8Unorm
        metalView.isPaused            = false
        metalView.enableSetNeedsDisplay = false
        addSubview(metalView)

        rebuildPipeline()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                self.mousePosition = point
                self.mouseDidMove(to: point)
            }
            return event
        }
    }

    deinit {
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Pipeline

    func rebuildPipeline() {
        guard let device,
              let library = device.makeDefaultLibrary() else { return }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = library.makeFunction(name: vertexShaderName)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentShaderName)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat                 = .bgra8Unorm
        attachment.isBlendingEnabled           = true
        attachment.sourceRGBBlendFactor        = .sourceAlpha
        attachment.destinationRGBBlendFactor   = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor      = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Layout & tracking

    override func layout() {
        super.layout()
        metalView?.frame = bounds
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse events

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mousePosition  = point
        isHovering     = true
        hoverStartTime = CACurrentMediaTime()
        mouseDidEnter(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        mousePosition = nil
        isHovering    = false
        hoverEndTime  = CACurrentMediaTime()
        mouseDidExit()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor    = view.currentRenderPassDescriptor,
              let encoder       = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let drawable      = view.currentDrawable else { return }

        let now = CACurrentMediaTime()
        if isHovering {
            indicatorOpacity = Float(min((now - hoverStartTime) / 0.1, 1.0))
        } else {
            indicatorOpacity = Float(max(1.0 - (now - hoverEndTime) / 0.2, 0.0))
        }

        let elapsed = Float(now - startTime)
        var uniforms = makeUniforms(time: elapsed, opacity: indicatorOpacity)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms,
                                 length: MemoryLayout<ReactiveUniforms>.stride,
                                 index: 0)
        configureEncoder(encoder, uniforms: &uniforms)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - SwiftUI wrapper

struct ReactiveBackgroundRepresentable: NSViewRepresentable {
    let style:        ReactiveStyle
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> ReactiveBackgroundView {
        ReactiveBackgroundView()
    }

    func updateNSView(_ nsView: ReactiveBackgroundView, context: Context) {
        nsView.reactiveStyle = style
        nsView.cornerRadius  = cornerRadius
    }
}
