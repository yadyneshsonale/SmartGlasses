import SwiftUI
import MetalKit

// MARK: - GrainientBackground
/// A full-screen animated gradient background using Metal shaders
struct GrainientBackground: UIViewRepresentable {
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        if let device = mtkView.device {
            context.coordinator.renderer = GrainientRenderer(device: device, view: mtkView)
            mtkView.delegate = context.coordinator.renderer
        }
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var renderer: GrainientRenderer?
    }
}

// MARK: - GrainientRenderer
class GrainientRenderer: NSObject, MTKViewDelegate {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLComputePipelineState?
    private var startTime: CFAbsoluteTime
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.startTime = CFAbsoluteTimeGetCurrent()
        super.init()
        
        setupPipeline()
    }
    
    private func setupPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        // Simplex noise functions
        float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
        float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
        float3 permute(float3 x) { return mod289(((x * 34.0) + 1.0) * x); }
        
        float snoise(float2 v) {
            const float4 C = float4(0.211324865405187, 0.366025403784439,
                                    -0.577350269189626, 0.024390243902439);
            float2 i  = floor(v + dot(v, C.yy));
            float2 x0 = v - i + dot(i, C.xx);
            float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
            float4 x12 = x0.xyxy + C.xxzz;
            x12.xy -= i1;
            i = mod289(i);
            float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
            float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
            m = m * m;
            m = m * m;
            float3 x = 2.0 * fract(p * C.www) - 1.0;
            float3 h = abs(x) - 0.5;
            float3 ox = floor(x + 0.5);
            float3 a0 = x - ox;
            m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
            float3 g;
            g.x = a0.x * x0.x + h.x * x0.y;
            g.yz = a0.yz * x12.xz + h.yz * x12.yw;
            return 130.0 * dot(m, g);
        }
        
        float fbm(float2 p) {
            float value = 0.0;
            float amplitude = 0.5;
            for (int i = 0; i < 5; i++) {
                value += amplitude * snoise(p);
                p *= 2.0;
                amplitude *= 0.5;
            }
            return value;
        }
        
        kernel void grainientKernel(texture2d<float, access::write> output [[texture(0)]],
                                    constant float &time [[buffer(0)]],
                                    uint2 gid [[thread_position_in_grid]]) {
            float2 resolution = float2(output.get_width(), output.get_height());
            float2 uv = float2(gid) / resolution;
            
            // Slow time for smooth animation
            float t = time * 0.15;
            
            // Create flowing noise patterns
            float2 p = uv * 2.0;
            float noise1 = fbm(p + float2(t * 0.3, t * 0.2));
            float noise2 = fbm(p * 1.5 + float2(-t * 0.2, t * 0.3) + noise1 * 0.5);
            float noise3 = fbm(p * 0.8 + float2(t * 0.1, -t * 0.15) + noise2 * 0.3);
            
            // Premium color palette - deep purples, blues, and subtle warm accents
            float3 color1 = float3(0.08, 0.04, 0.15);  // Deep purple-black
            float3 color2 = float3(0.12, 0.08, 0.25);  // Rich purple
            float3 color3 = float3(0.06, 0.12, 0.22);  // Deep blue
            float3 color4 = float3(0.15, 0.06, 0.18);  // Warm purple
            float3 color5 = float3(0.04, 0.08, 0.16);  // Ocean blue
            
            // Blend colors based on noise
            float3 col = mix(color1, color2, smoothstep(-0.3, 0.3, noise1));
            col = mix(col, color3, smoothstep(-0.2, 0.4, noise2));
            col = mix(col, color4, smoothstep(0.0, 0.5, noise3) * 0.5);
            col = mix(col, color5, smoothstep(-0.4, 0.2, noise1 * noise2));
            
            // Add subtle grain
            float grain = fract(sin(dot(uv * time, float2(12.9898, 78.233))) * 43758.5453);
            col += (grain - 0.5) * 0.015;
            
            // Subtle vignette
            float2 vignetteUV = uv - 0.5;
            float vignette = 1.0 - dot(vignetteUV, vignetteUV) * 0.4;
            col *= vignette;
            
            // Subtle glow spots
            float glow1 = exp(-length(uv - float2(0.3 + sin(t) * 0.1, 0.4 + cos(t * 0.7) * 0.1)) * 4.0);
            float glow2 = exp(-length(uv - float2(0.7 + cos(t * 0.8) * 0.1, 0.6 + sin(t * 0.6) * 0.1)) * 4.0);
            col += float3(0.1, 0.05, 0.15) * glow1 * 0.3;
            col += float3(0.05, 0.08, 0.15) * glow2 * 0.3;
            
            output.write(float4(col, 1.0), gid);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let kernel = library.makeFunction(name: "grainientKernel") else { return }
            pipelineState = try device.makeComputePipelineState(function: kernel)
        } catch {
            print("Failed to create pipeline: \(error)")
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        var time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(drawable.texture, index: 0)
        computeEncoder.setBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (drawable.texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (drawable.texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Preview
#Preview {
    GrainientBackground()
        .ignoresSafeArea()
}
