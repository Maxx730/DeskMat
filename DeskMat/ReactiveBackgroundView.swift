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
    private var metalView:        MTKView!
    private var device:           MTLDevice!
    private var commandQueue:     MTLCommandQueue!
    private var pipelineState:           MTLRenderPipelineState?
    private var crtPipelineState:        MTLRenderPipelineState?
    private var crtWarpPipelineState:    MTLRenderPipelineState?
    private var cornerMaskPipelineState: MTLRenderPipelineState?
    private var offscreenTexture:     MTLTexture?
    private var offscreenTexture2:    MTLTexture?

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
        case .none:       return ""
        case .lockOn:     return "lockOnFragment"
        case .liquidFill: return "liquidFillFragment"
        case .rainbow:    return "rainbowFragment"
        case .dvd:        return "dvdFragment"
        case .eighties:   return "eightiesFragment"
        case .voronoi:    return "voronoiFragment"
        case .subpixel:   return "subpixelFragment"
        case .joker:      return "jokerFragment"
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

        func makePipeline(vertex: String, fragment: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction   = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            let att = desc.colorAttachments[0]!
            att.pixelFormat                 = .bgra8Unorm
            att.isBlendingEnabled           = true
            att.sourceRGBBlendFactor        = .sourceAlpha
            att.destinationRGBBlendFactor   = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor      = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        pipelineState           = makePipeline(vertex: vertexShaderName, fragment: fragmentShaderName)
        crtPipelineState        = makePipeline(vertex: "reactiveVertex", fragment: "crtFragment")
        crtWarpPipelineState    = makePipeline(vertex: "reactiveVertex", fragment: "crtWarpFragment")
        cornerMaskPipelineState = makePipeline(vertex: "reactiveVertex", fragment: "cornerMaskFragment")
    }

    private func makeOffscreenTexture(size: CGSize) {
        guard let device, size.width > 0, size.height > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:       Int(size.width),
            height:      Int(size.height),
            mipmapped:   false
        )
        desc.usage = [.renderTarget, .shaderRead]
        offscreenTexture  = device.makeTexture(descriptor: desc)
        offscreenTexture2 = device.makeTexture(descriptor: desc)
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeOffscreenTexture(size: size)
    }

    func draw(in view: MTKView) {
        guard let pipelineState,
              let crtPipelineState,
              let crtWarpPipelineState,
              let cornerMaskPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable      = view.currentDrawable else { return }

        if offscreenTexture == nil { makeOffscreenTexture(size: view.drawableSize) }
        guard let offscreenTexture, let offscreenTexture2 else { return }

        let now = CACurrentMediaTime()
        if isHovering {
            indicatorOpacity = Float(min((now - hoverStartTime) / 0.1, 1.0))
        } else {
            indicatorOpacity = Float(max(1.0 - (now - hoverEndTime) / 0.2, 0.0))
        }

        let elapsed = Float(now - startTime)
        var uniforms = makeUniforms(time: elapsed, opacity: indicatorOpacity)

        func offscreenPass(to texture: MTLTexture) -> MTLRenderPassDescriptor {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture     = texture
            desc.colorAttachments[0].loadAction  = .clear
            desc.colorAttachments[0].storeAction = .store
            desc.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0)
            return desc
        }

        func encode(_ enc: MTLRenderCommandEncoder, pipeline: MTLRenderPipelineState,
                    texture: MTLTexture? = nil, configure: Bool = false) {
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<ReactiveUniforms>.stride, index: 0)
            if let texture { enc.setFragmentTexture(texture, index: 0) }
            if configure { configureEncoder(enc, uniforms: &uniforms) }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        let useCRT = reactiveStyle == .eighties || reactiveStyle == .dvd

        // The final texture whose contents get corner-masked to screen
        let premaskedTexture: MTLTexture

        if useCRT {
            // Pass 1 — reactive → offscreenTexture
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass(to: offscreenTexture)) {
                encode(enc, pipeline: pipelineState, configure: true)
            }
            // Pass 2 — CRT scanlines/aberration → offscreenTexture2
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass(to: offscreenTexture2)) {
                encode(enc, pipeline: crtPipelineState, texture: offscreenTexture)
            }
            // Pass 3 — CRT warp → offscreenTexture (safe to reuse: pass 2 has finished reading it)
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass(to: offscreenTexture)) {
                encode(enc, pipeline: crtWarpPipelineState, texture: offscreenTexture2)
            }
            premaskedTexture = offscreenTexture
        } else {
            // Pass 1 — reactive → offscreenTexture
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass(to: offscreenTexture)) {
                encode(enc, pipeline: pipelineState, configure: true)
            }
            premaskedTexture = offscreenTexture
        }

        // Final pass — corner mask → screen (all styles)
        if let screenPass = view.currentRenderPassDescriptor,
           let enc = commandBuffer.makeRenderCommandEncoder(descriptor: screenPass) {
            encode(enc, pipeline: cornerMaskPipelineState, texture: premaskedTexture)
        }

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
