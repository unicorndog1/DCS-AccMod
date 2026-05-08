// OpenXR rendering implementation for circle/dot overlays
// This file handles the OpenXR frame submission and quad layer rendering

#include "common.h"
#include "perf.h"
#include <d3d11.h>
#include <DirectXMath.h>
#include <memory>
#include <cstring>
#include <cmath>

// Graphics state for rendering
struct RenderState {
    ID3D11Device* device;
    ID3D11DeviceContext* context;
    XrSwapchain textSwapchain;
    XrSession session;
    XrSpace viewSpace;
    XrInstance instance;
    bool initialized;
    uint32_t swapchainWidth;
    uint32_t swapchainHeight;
    std::vector<XrSwapchainImageD3D11KHR> swapchainImages;
    int frameCount;
    ID3D11Texture2D* stagingTexture;
    // Number of consecutive frames where the circles list was empty.
    // After we've cleared the swapchain at least once with no circles
    // (emptyStreak >= 2), subsequent empty-frame work can be skipped entirely.
    int emptyStreak;
    // Hash of the last successfully-rasterized scene (circles+quad config).
    // When the next frame's hash matches, we skip the Map/rasterize/Unmap
    // and just CopyResource the persistent staging texture into the swapchain.
    uint64_t lastSceneHash;
    bool lastSceneHashValid;

    RenderState() : device(nullptr), context(nullptr), textSwapchain(XR_NULL_HANDLE),
                    session(XR_NULL_HANDLE), viewSpace(XR_NULL_HANDLE), 
                    instance(XR_NULL_HANDLE), initialized(false),
                    swapchainWidth(2048), swapchainHeight(1024), frameCount(0),
                    stagingTexture(nullptr), emptyStreak(0),
                    lastSceneHash(0), lastSceneHashValid(false) {}
};

static RenderState g_renderState;

static char NormalizeBitmapFontChar(char c) {
    unsigned char uc = static_cast<unsigned char>(c);

    if (uc >= 'a' && uc <= 'z') {
        uc = static_cast<unsigned char>(uc - ('a' - 'A'));
    }

    if (uc < 32 || uc > 90) {
        return '?';
    }

    return static_cast<char>(uc);
}

static float GetSingleEyeOffsetX(XrEyeVisibility eyeVisibility) {
    switch (eyeVisibility) {
    case XR_EYE_VISIBILITY_LEFT:
        return 0.5f;
    case XR_EYE_VISIBILITY_RIGHT:
        return -0.5f;
    case XR_EYE_VISIBILITY_BOTH:
    default:
        return 0.0f;
    }
}

// Simple 5x7 bitmap font data for basic ASCII characters (space to ~)
// Each character is 5x7 pixels, stored as 7 bytes (one per row)
static const uint8_t FONT_5X7[][7] = {
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00}, // Space (32)
    {0x04,0x04,0x04,0x04,0x00,0x04,0x00}, // !
    {0x0A,0x0A,0x0A,0x00,0x00,0x00,0x00}, // "
    {0x0A,0x1F,0x0A,0x1F,0x0A,0x00,0x00}, // #
    {0x04,0x0F,0x14,0x0E,0x05,0x1E,0x04}, // $
    {0x18,0x19,0x02,0x04,0x08,0x13,0x03}, // %
    {0x0C,0x12,0x14,0x08,0x15,0x12,0x0D}, // &
    {0x04,0x04,0x04,0x00,0x00,0x00,0x00}, // '
    {0x02,0x04,0x08,0x08,0x08,0x04,0x02}, // (
    {0x08,0x04,0x02,0x02,0x02,0x04,0x08}, // )
    {0x00,0x0A,0x04,0x1F,0x04,0x0A,0x00}, // *
    {0x00,0x04,0x04,0x1F,0x04,0x04,0x00}, // +
    {0x00,0x00,0x00,0x00,0x00,0x04,0x08}, // ,
    {0x00,0x00,0x00,0x1F,0x00,0x00,0x00}, // -
    {0x00,0x00,0x00,0x00,0x00,0x04,0x00}, // .
    {0x00,0x01,0x02,0x04,0x08,0x10,0x00}, // /
    {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E}, // 0
    {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E}, // 1
    {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F}, // 2
    {0x1F,0x02,0x04,0x02,0x01,0x11,0x0E}, // 3
    {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02}, // 4
    {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E}, // 5
    {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E}, // 6
    {0x1F,0x01,0x02,0x04,0x08,0x08,0x08}, // 7
    {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E}, // 8
    {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C}, // 9
    {0x00,0x00,0x04,0x00,0x00,0x04,0x00}, // :
    {0x00,0x00,0x04,0x00,0x00,0x04,0x08}, // ;
    {0x02,0x04,0x08,0x10,0x08,0x04,0x02}, // <
    {0x00,0x00,0x1F,0x00,0x1F,0x00,0x00}, // =
    {0x08,0x04,0x02,0x01,0x02,0x04,0x08}, // >
    {0x0E,0x11,0x01,0x02,0x04,0x00,0x04}, // ?
    {0x0E,0x11,0x01,0x0D,0x15,0x15,0x0E}, // @
    {0x0E,0x11,0x11,0x11,0x1F,0x11,0x11}, // A
    {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E}, // B
    {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E}, // C
    {0x1C,0x12,0x11,0x11,0x11,0x12,0x1C}, // D
    {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F}, // E
    {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10}, // F
    {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F}, // G
    {0x11,0x11,0x11,0x1F,0x11,0x11,0x11}, // H
    {0x0E,0x04,0x04,0x04,0x04,0x04,0x0E}, // I
    {0x07,0x02,0x02,0x02,0x02,0x12,0x0C}, // J
    {0x11,0x12,0x14,0x18,0x14,0x12,0x11}, // K
    {0x10,0x10,0x10,0x10,0x10,0x10,0x1F}, // L
    {0x11,0x1B,0x15,0x15,0x11,0x11,0x11}, // M
    {0x11,0x11,0x19,0x15,0x13,0x11,0x11}, // N
    {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E}, // O
    {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10}, // P
    {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D}, // Q
    {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11}, // R
    {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E}, // S
    {0x1F,0x04,0x04,0x04,0x04,0x04,0x04}, // T
    {0x11,0x11,0x11,0x11,0x11,0x11,0x0E}, // U
    {0x11,0x11,0x11,0x11,0x11,0x0A,0x04}, // V
    {0x11,0x11,0x11,0x15,0x15,0x15,0x0A}, // W
    {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11}, // X
    {0x11,0x11,0x11,0x0A,0x04,0x04,0x04}, // Y
    {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F}, // Z
};

// Draw a single character at position (px, py) with given color and alpha
static void DrawChar(uint8_t* pixels, int rowPitch, int W, int H, char c, int px, int py, 
                     uint8_t r, uint8_t g, uint8_t b, float alpha) {
    c = NormalizeBitmapFontChar(c);
    
    const uint8_t* glyph = FONT_5X7[c - 32];
    
    for (int row = 0; row < 7; row++) {
        int y = py + row;
        if (y < 0 || y >= H) continue;
        
        uint8_t rowData = glyph[row];
        for (int col = 0; col < 5; col++) {
            if (rowData & (1 << (4 - col))) {  // Check bit from left to right
                int x = px + col;
                if (x >= 0 && x < W) {
                    uint8_t* p = pixels + y * rowPitch + x * 4;
                    
                    // Alpha blend
                    float dstA = p[3] / 255.0f;
                    float outA = alpha + dstA * (1.0f - alpha);
                    if (outA > 0.0f) {
                        float invOutA = 1.0f / outA;
                        float dstContrib = dstA * (1.0f - alpha);
                        p[0] = (uint8_t)((r * alpha + p[0] * dstContrib) * invOutA);
                        p[1] = (uint8_t)((g * alpha + p[1] * dstContrib) * invOutA);
                        p[2] = (uint8_t)((b * alpha + p[2] * dstContrib) * invOutA);
                        p[3] = (uint8_t)(outA * 255.0f);
                    }
                }
            }
        }
    }
}

// Draw text string centered at (cx, cy)
static void DrawText(uint8_t* pixels, int rowPitch, int W, int H, const char* text, 
                     int cx, int cy, uint8_t r, uint8_t g, uint8_t b, float alpha) {
    if (!text || text[0] == '\0') return;
    
    int len = (int)strlen(text);
    int textWidth = len * 6 - 1;  // 5 pixels per char + 1 pixel spacing, minus last space
    int startX = cx - textWidth / 2;
    
    for (int i = 0; i < len; i++) {
        DrawChar(pixels, rowPitch, W, H, text[i], startX + i * 6, cy, r, g, b, alpha);
    }
}

// Create swapchain for overlay rendering
bool CreateOverlaySwapchain() {
    if (!g_renderState.session || g_renderState.textSwapchain != XR_NULL_HANDLE) {
        return false;
    }
    
    LogMessage("Creating overlay swapchain...");
    
    XrSwapchainCreateInfo swapchainInfo = { XR_TYPE_SWAPCHAIN_CREATE_INFO };
    swapchainInfo.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
    swapchainInfo.format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swapchainInfo.sampleCount = 1;
    swapchainInfo.width = g_renderState.swapchainWidth;
    swapchainInfo.height = g_renderState.swapchainHeight;
    swapchainInfo.faceCount = 1;
    swapchainInfo.arraySize = 1;
    swapchainInfo.mipCount = 1;
    
    if (!g_nextCreateSwapchain) {
        LogMessage("ERROR: g_nextCreateSwapchain is NULL");
        return false;
    }
    
    XrResult result = g_nextCreateSwapchain(g_renderState.session, &swapchainInfo, &g_renderState.textSwapchain);
    if (XR_FAILED(result)) {
        LogFormat("Failed to create swapchain: %d", result);
        return false;
    }
    
    // Enumerate swapchain images
    uint32_t imageCount = 0;
    g_nextEnumerateSwapchainImages(g_renderState.textSwapchain, 0, &imageCount, nullptr);
    
    g_renderState.swapchainImages.resize(imageCount, { XR_TYPE_SWAPCHAIN_IMAGE_D3D11_KHR });
    g_nextEnumerateSwapchainImages(g_renderState.textSwapchain, imageCount, &imageCount,
                                   reinterpret_cast<XrSwapchainImageBaseHeader*>(g_renderState.swapchainImages.data()));
    
    LogFormat("Created swapchain with %d images", imageCount);

    // Create upload texture for CPU-side circle drawing.
    // DYNAMIC + WRITE_DISCARD avoids GPU/CPU sync stalls (the previous
    // STAGING + MAP_WRITE path produced 92ms map spikes when the GPU was
    // still reading the texture from the prior CopyResource).
    if (g_renderState.device) {
        D3D11_TEXTURE2D_DESC stagingDesc = {};
        stagingDesc.Width = g_renderState.swapchainWidth;
        stagingDesc.Height = g_renderState.swapchainHeight;
        stagingDesc.MipLevels = 1;
        stagingDesc.ArraySize = 1;
        stagingDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        stagingDesc.SampleDesc.Count = 1;
        stagingDesc.Usage = D3D11_USAGE_DYNAMIC;
        stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        // DYNAMIC textures require at least one bind flag.
        stagingDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

        HRESULT stagingHr = g_renderState.device->CreateTexture2D(&stagingDesc, nullptr, &g_renderState.stagingTexture);
        if (SUCCEEDED(stagingHr)) {
            LogMessage("Created DYNAMIC upload texture (WRITE_DISCARD) for circle rendering");
        } else {
            LogFormat("Failed to create staging texture: 0x%08X", stagingHr);
        }
    }

    g_renderState.initialized = true;
    return true;
}

// Render text to swapchain texture
void RenderTextToTexture() {
    PERF_SCOPE(perf::K_renderText);
    if (!g_renderState.device || !g_renderState.context || g_renderState.textSwapchain == XR_NULL_HANDLE) {
        if (g_renderState.frameCount == 1) {
            LogMessage("RenderTextToTexture: Missing device, context, or swapchain!");
        }
        return;
    }
    
    // Acquire swapchain image
    XrSwapchainImageAcquireInfo acquireInfo = { XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO };
    uint32_t imageIndex = 0;
    XrResult result = g_nextAcquireSwapchainImage(g_renderState.textSwapchain, &acquireInfo, &imageIndex);
    if (XR_FAILED(result)) {
        if (g_renderState.frameCount == 1) {
            LogFormat("Failed to acquire swapchain image: %d", result);
        }
        return;
    }
    
    // Wait for image
    XrSwapchainImageWaitInfo waitInfo = { XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO };
    waitInfo.timeout = XR_INFINITE_DURATION;
    result = g_nextWaitSwapchainImage(g_renderState.textSwapchain, &waitInfo);
    if (XR_FAILED(result)) {
        if (g_renderState.frameCount == 1) {
            LogFormat("Failed to wait for swapchain image: %d", result);
        }
        return;
    }
    
    // Get texture
    ID3D11Texture2D* texture = g_renderState.swapchainImages[imageIndex].texture;
    
    if (!texture) {
        if (g_renderState.frameCount == 1) {
            LogFormat("ERROR: Swapchain texture at index %d is NULL!", imageIndex);
        }
        XrSwapchainImageReleaseInfo releaseInfo = { XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO };
        g_nextReleaseSwapchainImage(g_renderState.textSwapchain, &releaseInfo);
        return;
    }
    
    // Get texture description to verify properties
    D3D11_TEXTURE2D_DESC texDesc;
    texture->GetDesc(&texDesc);
    
    if (g_renderState.frameCount == 1) {
        LogFormat("Texture desc: Format=%d, Width=%d, Height=%d, BindFlags=0x%X", 
                 texDesc.Format, texDesc.Width, texDesc.Height, texDesc.BindFlags);
    }
    
    // Create render target view with explicit format
    D3D11_RENDER_TARGET_VIEW_DESC rtvDesc = {};
    rtvDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    rtvDesc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
    rtvDesc.Texture2D.MipSlice = 0;
    
    ID3D11RenderTargetView* rtv = nullptr;
    HRESULT hr = g_renderState.device->CreateRenderTargetView(texture, &rtvDesc, &rtv);
    
    if (SUCCEEDED(hr) && rtv) {
        // Clear to transparent black
        float clearColor[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
        g_renderState.context->ClearRenderTargetView(rtv, clearColor);
        
        // Get circles to render (thread-safe copy)
        std::vector<CircleData> circlesToRender;
        float quadTanHalfFov = 1.0f;
        float quadAspect = 1.778f;
        XrEyeVisibility quadEyeVisibility = XR_EYE_VISIBILITY_BOTH;
        float quadDistance = 1.0f;
        float zoomFactor = 1.0f;
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            circlesToRender = g_state.circles;
            quadTanHalfFov = g_state.quadTanHalfFov;
            quadAspect = g_state.quadAspect;
            quadEyeVisibility = g_state.quadEyeVisibility;
            quadDistance = g_state.quadDistance;
            zoomFactor = g_state.zoomFactor;
        }

        float quadWidthWorld = 2.0f * quadDistance * quadTanHalfFov * quadAspect;
        float eyeOffsetWorld = GetSingleEyeOffsetX(quadEyeVisibility);
        float xUvShift = (quadWidthWorld > 0.0001f) ? (eyeOffsetWorld / quadWidthWorld) : 0.0f;

        if ((g_renderState.frameCount % 120) == 0 && !circlesToRender.empty()) {
            int filledCount = 0;
            for (const auto& c : circlesToRender) {
                if (c.filled) {
                    filledCount++;
                }
            }
            LogFormat("Frame %u: circles=%u filled=%d",
                g_renderState.frameCount,
                (unsigned int)circlesToRender.size(),
                filledCount);
        }

        // Draw circles into staging texture and copy to swapchain
        if (!circlesToRender.empty() && g_renderState.stagingTexture) {
            int W = (int)g_renderState.swapchainWidth;
            int H = (int)g_renderState.swapchainHeight;
            int maxDim = W > H ? W : H;                  // 512

            // Cheap FNV-1a hash over circle data + relevant config. If the
            // scene is unchanged we skip the Map/rasterize/Unmap block and
            // just CopyResource the previously-rasterized staging texture.
            uint64_t h = 1469598103934665603ULL;
            auto hashBytes = [&](const void* p, size_t n) {
                const uint8_t* b = (const uint8_t*)p;
                for (size_t i = 0; i < n; ++i) {
                    h ^= (uint64_t)b[i];
                    h *= 1099511628211ULL;
                }
            };
            size_t cn = circlesToRender.size();
            hashBytes(&cn, sizeof(cn));
            if (cn > 0) hashBytes(circlesToRender.data(), cn * sizeof(CircleData));
            hashBytes(&quadTanHalfFov, sizeof(quadTanHalfFov));
            hashBytes(&quadAspect, sizeof(quadAspect));
            hashBytes(&quadDistance, sizeof(quadDistance));
            hashBytes(&xUvShift, sizeof(xUvShift));
            hashBytes(&zoomFactor, sizeof(zoomFactor));

            bool dirtyHit = g_renderState.lastSceneHashValid && h == g_renderState.lastSceneHash;
            if (dirtyHit) {
                perf::RecordCounter(perf::K_dirtyHits, 1.0);
                // Just upload the persistent staging texture — its contents are
                // still the last-rendered scene, which matches what we want now.
                int64_t copyStart = perf::Now();
                g_renderState.context->CopyResource(texture, g_renderState.stagingTexture);
                perf::RecordDuration(perf::K_copyResource, copyStart);
            } else {
                perf::RecordCounter(perf::K_dirtyMisses, 1.0);

            int64_t mapStart = perf::Now();
            D3D11_MAPPED_SUBRESOURCE mapped = {};
            HRESULT mapHr = g_renderState.context->Map(
                g_renderState.stagingTexture, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);

            if (SUCCEEDED(mapHr)) {
                uint8_t* pixels = reinterpret_cast<uint8_t*>(mapped.pData);
                int rowPitch = (int)mapped.RowPitch;

                int64_t pixelLoopStart = perf::Now();

                // Clear staging to transparent black
                for (int y = 0; y < H; y++) {
                    memset(pixels + y * rowPitch, 0, W * 4);
                }

                // Draw each circle (ring by default, filled if filled==true)
                // Two-pass rendering: white highlight outline, then main circle
                for (const auto& circle : circlesToRender) {
                    // Apply VR zoom scaling: scale positions toward/away from center
                    // When zoomed in (zoomFactor > 1), objects move away from center
                    float zoomedX = 0.5f + (circle.x - 0.5f) * zoomFactor;
                    float zoomedY = 0.5f + (circle.y - 0.5f) * zoomFactor;
                    
                    float correctedX = zoomedX - xUvShift;
                    float cx = correctedX * W;
                    float cy = zoomedY * H;
                    // Radius is normalized to max(winW,winH); un-normalize to texture pixels
                    // Compensate for quad distance scaling to maintain constant angular size
                    // Also scale radius with zoom to maintain apparent size
                    float r = circle.radius * (float)maxDim / quadDistance * zoomFactor;
                    if (r < 1.0f) r = 1.0f;

                    uint8_t cr = (uint8_t)(circle.r * 255.0f);
                    uint8_t cg = (uint8_t)(circle.g * 255.0f);
                    uint8_t cb = (uint8_t)(circle.b * 255.0f);
                    float baseAlpha = circle.a;

                    // Ring width from LUA-calculated thickness (normalized); un-normalize to pixels
                    // Compensate for quad distance scaling to maintain constant ring thickness
                    float ringWidth = circle.thickness * (float)maxDim / quadDistance;
                    if (circle.filled) {
                        if (ringWidth < 0.75f) ringWidth = 0.75f;
                    } else {
                        ringWidth *= 1.15f;
                        if (ringWidth < 0.85f) ringWidth = 0.85f;
                    }
                    float outerR = r;
                    float innerR = outerR - ringWidth;
                    if (innerR < 0.0f) innerR = 0.0f;

                    // Keep the white highlight narrow so the colored band remains dominant.
                    float highlightWidth = circle.filled ? 0.55f : 0.65f;
                    float highlightAlphaScale = circle.filled ? 0.18f : 0.18f;
                    
                    int minX = (int)(cx - outerR - highlightWidth - 1.5f);
                    int maxX = (int)(cx + outerR + highlightWidth + 1.5f);
                    int minY = (int)(cy - outerR - highlightWidth - 1.5f);
                    int maxY = (int)(cy + outerR + highlightWidth + 1.5f);
                    if (minX < 0) minX = 0;
                    if (maxX >= W) maxX = W - 1;
                    if (minY < 0) minY = 0;
                    if (maxY >= H) maxY = H - 1;

                    // Pass 1: Draw white highlight outline
                    for (int py = minY; py <= maxY; py++) {
                        for (int px = minX; px <= maxX; px++) {
                            float dx = (float)px - cx;
                            float dy = (float)py - cy;
                            float dist = sqrtf(dx * dx + dy * dy);

                            float alpha = 0.0f;
                            if (circle.filled) {
                                // White outline around filled circle
                                float outerHighlight = outerR + highlightWidth + 0.5f - dist;
                                float innerHighlight = dist - outerR + 0.5f;
                                float oa = outerHighlight < 1.0f ? outerHighlight : 1.0f;
                                float ia = innerHighlight < 1.0f ? innerHighlight : 1.0f;
                                alpha = oa < ia ? oa : ia;
                                if (alpha < 0.0f) alpha = 0.0f;
                            } else {
                                // White outline around ring (both outer and inner edges)
                                float outerHighlightOuter = outerR + highlightWidth + 0.5f - dist;
                                float outerHighlightInner = dist - outerR + 0.5f;
                                float outerAlpha = outerHighlightOuter < 1.0f ? outerHighlightOuter : 1.0f;
                                outerAlpha = outerAlpha < outerHighlightInner ? outerAlpha : outerHighlightInner;
                                
                                float innerHighlightOuter = innerR + 0.5f - dist;
                                float innerHighlightInner = dist - (innerR - highlightWidth) + 0.5f;
                                float innerAlpha = innerHighlightOuter < 1.0f ? innerHighlightOuter : 1.0f;
                                innerAlpha = innerAlpha < innerHighlightInner ? innerAlpha : innerHighlightInner;
                                
                                alpha = outerAlpha > innerAlpha ? outerAlpha : innerAlpha;
                                if (alpha < 0.0f) alpha = 0.0f;
                            }

                            alpha *= baseAlpha * highlightAlphaScale;
                            if (alpha <= 0.003f) continue;

                            // Draw white pixel
                            uint8_t* p = pixels + py * rowPitch + px * 4;
                            float dstA = p[3] / 255.0f;
                            float outA = alpha + dstA * (1.0f - alpha);
                            if (outA > 0.0f) {
                                float invOutA = 1.0f / outA;
                                float dstContrib = dstA * (1.0f - alpha);
                                p[0] = (uint8_t)((255 * alpha + p[0] * dstContrib) * invOutA);
                                p[1] = (uint8_t)((255 * alpha + p[1] * dstContrib) * invOutA);
                                p[2] = (uint8_t)((255 * alpha + p[2] * dstContrib) * invOutA);
                                p[3] = (uint8_t)(outA * 255.0f);
                            }
                        }
                    }

                    // Pass 2: Draw main circle/ring on top
                    for (int py = minY; py <= maxY; py++) {
                        for (int px = minX; px <= maxX; px++) {
                            float dx = (float)px - cx;
                            float dy = (float)py - cy;
                            float dist = sqrtf(dx * dx + dy * dy);

                            float alpha;
                            if (circle.filled) {
                                // Filled circle with 0.5px anti-aliased edge
                                float edge = outerR + 0.5f - dist;
                                alpha = edge < 1.0f ? edge : 1.0f;
                                if (alpha < 0.0f) alpha = 0.0f;
                            } else {
                                // Ring: anti-alias at both outer and inner edges
                                float outerEdge = outerR + 0.5f - dist;
                                float innerEdge = dist - innerR + 0.5f;
                                float oa = outerEdge < 1.0f ? outerEdge : 1.0f;
                                float ia = innerEdge < 1.0f ? innerEdge : 1.0f;
                                alpha = oa < ia ? oa : ia;
                                if (alpha < 0.0f) alpha = 0.0f;
                            }

                            alpha *= baseAlpha;
                            if (alpha <= 0.003f) continue;

                            // Alpha-blend (srcOver) with existing pixel
                            uint8_t* p = pixels + py * rowPitch + px * 4;
                            float dstA = p[3] / 255.0f;
                            float outA = alpha + dstA * (1.0f - alpha);
                            if (outA > 0.0f) {
                                float invOutA = 1.0f / outA;
                                float dstContrib = dstA * (1.0f - alpha);
                                p[0] = (uint8_t)((cr * alpha + p[0] * dstContrib) * invOutA);
                                p[1] = (uint8_t)((cg * alpha + p[1] * dstContrib) * invOutA);
                                p[2] = (uint8_t)((cb * alpha + p[2] * dstContrib) * invOutA);
                                p[3] = (uint8_t)(outA * 255.0f);
                            }
                        }
                    }
                }

                // Draw text labels above circles
                for (const auto& circle : circlesToRender) {
                    if (circle.labelA <= 0.001f) continue;  // Explicitly disabled by sender
                    if (circle.label[0] == '\0') continue;  // Skip if no label
                    
                    // Apply VR zoom scaling (same as circle positions)
                    float zoomedX = 0.5f + (circle.x - 0.5f) * zoomFactor;
                    float zoomedY = 0.5f + (circle.y - 0.5f) * zoomFactor;
                    
                    float correctedX = zoomedX - xUvShift;
                    float cx = correctedX * W;
                    float cy = zoomedY * H;
                    float r = circle.radius * (float)maxDim / quadDistance * zoomFactor;
                    if (r < 1.0f) r = 1.0f;
                    
                    // Position text 10 pixels above the circle's top edge
                    int textX = (int)cx;
                    int textY = (int)(cy - r - 10);

                    DrawText(pixels, rowPitch, W, H, circle.label, textX, textY,
                             255, 255, 255, circle.labelA);
                }

                perf::RecordDuration(perf::K_pixelLoop, pixelLoopStart);

                g_renderState.context->Unmap(g_renderState.stagingTexture, 0);
                perf::RecordDuration(perf::K_mapUnmap, mapStart);

                // Upload CPU pixels to GPU swapchain texture
                int64_t copyStart = perf::Now();
                g_renderState.context->CopyResource(texture, g_renderState.stagingTexture);
                perf::RecordDuration(perf::K_copyResource, copyStart);

                if (g_renderState.frameCount <= 5) {
                    LogFormat("Frame %u: Rendered %d circles to texture, quad size: %.3f x %.3f",
                        g_renderState.frameCount,
                        (int)circlesToRender.size(),
                        2.0f * g_state.quadTanHalfFov * g_state.quadAspect,
                        2.0f * g_state.quadTanHalfFov);
                }

                // Record the scene hash so the next frame can short-circuit.
                g_renderState.lastSceneHash = h;
                g_renderState.lastSceneHashValid = true;
            } else {
                if (g_renderState.frameCount <= 2) {
                    LogFormat("Failed to map staging texture: 0x%08X", mapHr);
                }
            }
            } // end dirtyHit else (rasterize path)
        }
        
        rtv->Release();
    } else {
        if (g_renderState.frameCount == 1) {
            LogFormat("Failed to create render target view: HRESULT=0x%08X", hr);
        }
    }
    
    // Release swapchain image
    XrSwapchainImageReleaseInfo releaseInfo = { XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO };
    g_nextReleaseSwapchainImage(g_renderState.textSwapchain, &releaseInfo);
}

// Hooked xrCreateSession to capture D3D11 device and session
XrResult XRAPI_CALL Hook_xrCreateSession(XrInstance instance, const XrSessionCreateInfo* createInfo, XrSession* session) {
    LogMessage("Hook_xrCreateSession called");
    
    // Call next layer first
    XrResult result = XR_ERROR_RUNTIME_FAILURE;
    if (g_nextCreateSession) {
        result = g_nextCreateSession(instance, createInfo, session);
    }
    
    if (XR_SUCCEEDED(result)) {
        g_renderState.session = *session;
        g_renderState.instance = instance;
        LogMessage("Session created successfully");
        
        // Extract D3D11 device if available
        if (createInfo && createInfo->next) {
            const XrGraphicsBindingD3D11KHR* d3d11Binding = 
                reinterpret_cast<const XrGraphicsBindingD3D11KHR*>(createInfo->next);
            
            if (d3d11Binding && d3d11Binding->type == XR_TYPE_GRAPHICS_BINDING_D3D11_KHR) {
                g_renderState.device = d3d11Binding->device;
                if (g_renderState.device) {
                    g_renderState.device->GetImmediateContext(&g_renderState.context);
                    LogMessage("Captured D3D11 device from session");
                }
            }
        }
        
        // Create reference space for positioning overlay
        if (g_nextCreateReferenceSpace) {
            XrReferenceSpaceCreateInfo spaceInfo = { XR_TYPE_REFERENCE_SPACE_CREATE_INFO };
            spaceInfo.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_VIEW;
            spaceInfo.poseInReferenceSpace.orientation.w = 1.0f;
            g_nextCreateReferenceSpace(*session, &spaceInfo, &g_renderState.viewSpace);
            LogMessage("Created VIEW reference space");
        }
    }
    
    return result;
}

// Hooked xrDestroySession to clean up resources
XrResult XRAPI_CALL Hook_xrDestroySession(XrSession session) {
    LogMessage("Hook_xrDestroySession called");
    
    // Clean up our resources
    if (g_renderState.stagingTexture) {
        g_renderState.stagingTexture->Release();
        g_renderState.stagingTexture = nullptr;
    }

    if (g_renderState.textSwapchain != XR_NULL_HANDLE && g_nextDestroySwapchain) {
        g_nextDestroySwapchain(g_renderState.textSwapchain);
        g_renderState.textSwapchain = XR_NULL_HANDLE;
    }
    
    if (g_renderState.viewSpace != XR_NULL_HANDLE && g_nextDestroySpace) {
        g_nextDestroySpace(g_renderState.viewSpace);
        g_renderState.viewSpace = XR_NULL_HANDLE;
    }
    
    g_renderState.device = nullptr;
    g_renderState.context = nullptr;
    g_renderState.session = XR_NULL_HANDLE;
    g_renderState.initialized = false;
    
    // Chain to next layer
    if (g_nextDestroySession) {
        return g_nextDestroySession(session);
    }
    
    return XR_SUCCESS;
}

// Hooked xrLocateViews to detect VR zoom by monitoring FOV changes
XrResult XRAPI_CALL Hook_xrLocateViews(
    XrSession session,
    const XrViewLocateInfo* viewLocateInfo,
    XrViewState* viewState,
    uint32_t viewCapacityInput,
    uint32_t* viewCountOutput,
    XrView* views)
{
    // Call original function first
    XrResult result = XR_ERROR_RUNTIME_FAILURE;
    if (g_nextLocateViews) {
        result = g_nextLocateViews(session, viewLocateInfo, viewState, 
                                   viewCapacityInput, viewCountOutput, views);
    }
    
    // If successful and we got view data, extract FOV for zoom detection
    if (XR_SUCCEEDED(result) && views && viewCountOutput && *viewCountOutput > 0) {
        // Use first view's FOV (left eye) for zoom calculation
        const XrFovf& fov = views[0].fov;
        
        // Calculate vertical FOV span in radians
        float verticalFOV = fov.angleUp - fov.angleDown;
        
        // Thread-safe update of zoom state
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            
            // Capture baseline FOV on first frame (unzoomed state)
            if (!g_state.fovInitialized && verticalFOV > 0.1f) {
                g_state.baselineVerticalFOV = verticalFOV;
                g_state.currentVerticalFOV = verticalFOV;
                g_state.zoomFactor = 1.0f;
                g_state.fovInitialized = true;
                
                LogFormat("VR Zoom: Baseline FOV captured = %.4f radians (%.1f degrees)",
                         verticalFOV, verticalFOV * 57.2958f);
            }
            else if (g_state.fovInitialized && verticalFOV > 0.1f) {
                // Update current FOV and calculate zoom factor
                g_state.currentVerticalFOV = verticalFOV;
                g_state.zoomFactor = g_state.baselineVerticalFOV / verticalFOV;
                
                // Log zoom changes (only when zoom factor changes significantly)
                static float lastLoggedZoom = 1.0f;
                if (fabsf(g_state.zoomFactor - lastLoggedZoom) > 0.1f) {
                    LogFormat("VR Zoom: Factor = %.2fx (FOV: %.4f rad, %.1f deg)",
                             g_state.zoomFactor, verticalFOV, verticalFOV * 57.2958f);
                    lastLoggedZoom = g_state.zoomFactor;
                }
            }
        }
    }
    
    return result;
}

// Hooked xrEndFrame to inject quad layer overlay
XrResult XRAPI_CALL Hook_xrEndFrame(XrSession session, const XrFrameEndInfo* frameEndInfo) {
    PERF_SCOPE(perf::K_xrEndFrame);
    g_renderState.frameCount++;

    // Periodic state emission (every ~30s, gated by frame count to keep cost trivial).
    if ((g_renderState.frameCount % 1800) == 0) {
        size_t cs = 0;
        float qd = 1.0f, tf = 1.0f, ar = 1.0f;
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            cs = g_state.circles.size();
            qd = g_state.quadDistance;
            tf = g_state.quadTanHalfFov;
            ar = g_state.quadAspect;
        }
        perf::RecordCounter(perf::K_circles, (double)cs);
        perf::EmitState((double)cs, qd, tf, ar, 0, 0.0);
    }

    perf::OnFrameEnd();
    
    // Create swapchain on first frame
    if (!g_renderState.initialized && g_renderState.session != XR_NULL_HANDLE) {
        CreateOverlaySwapchain();
    }
    
    // Render overlay every frame
    if (g_renderState.initialized && (g_renderState.frameCount % 60 == 0)) {
        // Only log every 60 frames to avoid spam
        std::vector<CircleData> circlesToRender;
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            circlesToRender = g_state.circles;
        }
        
        LogFormat("Frame %d: %d circles", g_renderState.frameCount, (int)circlesToRender.size());
    }
    
    // If we have our swapchain, render and inject overlay
    if (g_renderState.initialized && g_renderState.textSwapchain != XR_NULL_HANDLE && 
        g_renderState.viewSpace != XR_NULL_HANDLE && frameEndInfo) {

        // Zero-circle fast path: once we've drawn (or cleared) one empty frame
        // we don't need to keep submitting our quad layer at all. The quad
        // would only show stale/transparent content. Skipping saves the entire
        // swapchain acquire/wait/release + RTV creation + clear + quad layer
        // composition cost (~500us p50 measured pre-optimization).
        size_t circleCountQuick = 0;
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            circleCountQuick = g_state.circles.size();
        }
        if (circleCountQuick == 0) {
            g_renderState.emptyStreak++;
            // Invalidate the cached hash so when circles return we re-rasterize.
            g_renderState.lastSceneHashValid = false;
            if (g_renderState.emptyStreak >= 2) {
                // Skip render + skip quad submission entirely.
                if (g_nextEndFrame) {
                    return g_nextEndFrame(session, frameEndInfo);
                }
                return XR_SUCCESS;
            }
            // First empty frame: still render once to clear stale pixels.
        } else {
            g_renderState.emptyStreak = 0;
        }

        // Render text to swapchain
        RenderTextToTexture();
        
        // Snapshot config updated by UDP thread under lock.
        float quadTanHalfFov = 1.0f;
        float quadAspect = 1.778f;
        XrEyeVisibility quadEyeVisibility = XR_EYE_VISIBILITY_BOTH;
        float quadDistance = 1.0f;
        {
            CriticalSectionLock lock(g_state.circlesMutex);
            quadTanHalfFov = g_state.quadTanHalfFov;
            quadAspect = g_state.quadAspect;
            quadEyeVisibility = g_state.quadEyeVisibility;
            quadDistance = g_state.quadDistance;
        }

        // Create quad layer
        XrCompositionLayerQuad quadLayer = { XR_TYPE_COMPOSITION_LAYER_QUAD };
        quadLayer.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
        quadLayer.space = g_renderState.viewSpace;
        // Explicit eye-selection path (rather than raw assignment) so behavior is
        // obvious in code and easier to debug per mode.
        float SINGLE_EYE_OFFSET_X = GetSingleEyeOffsetX(quadEyeVisibility);
        // Eye isolation is handled by quad position offset in our current setup.
        // Keep OpenXR eye visibility at BOTH to avoid runtime-specific behavior.
        quadLayer.eyeVisibility = XR_EYE_VISIBILITY_BOTH;

        quadLayer.pose.orientation.x = 0.0f;
        quadLayer.pose.orientation.y = 0.0f;
        quadLayer.pose.orientation.z = 0.0f;
        quadLayer.pose.orientation.w = 1.0f;
        quadLayer.pose.position.x = SINGLE_EYE_OFFSET_X;
        quadLayer.pose.position.y = 0.0f;
        quadLayer.pose.position.z = -quadDistance;  // Position at -distance in world coordinates
        
        // Size the quad to exactly match the DCS camera projection so normalized
        // 0..1 circle coordinates map to the correct view angles.
        // quadHeight = 2 * D * tan(vertFOV/2), quadWidth = quadHeight * aspect
        float quadHeight = 2.0f * quadDistance * quadTanHalfFov;
        float quadWidth  = quadHeight * quadAspect;
        quadLayer.size.width  = quadWidth;
        quadLayer.size.height = quadHeight;

        if (g_renderState.frameCount % 120 == 0) {
            LogFormat("Frame %d: applying eyeVisibility=%d (layer forced=%d)",
                      g_renderState.frameCount,
                      (int)quadEyeVisibility,
                      (int)quadLayer.eyeVisibility);
        }
        
        // Swapchain subimage
        quadLayer.subImage.swapchain = g_renderState.textSwapchain;
        quadLayer.subImage.imageRect.offset.x = 0;
        quadLayer.subImage.imageRect.offset.y = 0;
        quadLayer.subImage.imageRect.extent.width = g_renderState.swapchainWidth;
        quadLayer.subImage.imageRect.extent.height = g_renderState.swapchainHeight;
        quadLayer.subImage.imageArrayIndex = 0;
        
        // Create modified frame end info with our quad layer
        XrFrameEndInfo modifiedFrameInfo = *frameEndInfo;
        
        // Allocate new layer array (original layers + our quad)
        std::vector<const XrCompositionLayerBaseHeader*> allLayers;
        for (uint32_t i = 0; i < frameEndInfo->layerCount; i++) {
            allLayers.push_back(frameEndInfo->layers[i]);
        }
        allLayers.push_back(reinterpret_cast<const XrCompositionLayerBaseHeader*>(&quadLayer));
        
        modifiedFrameInfo.layerCount = (uint32_t)allLayers.size();
        modifiedFrameInfo.layers = allLayers.data();
        
        // Log once to confirm we're submitting the quad
        if (g_renderState.frameCount == 1) {
            LogFormat("Submitting quad layer! Original layers: %d, Total with overlay: %d", 
                     frameEndInfo->layerCount, modifiedFrameInfo.layerCount);
        }
        
        // Chain to next layer with modified info
        if (g_nextEndFrame) {
            XrResult result = g_nextEndFrame(session, &modifiedFrameInfo);
            if (XR_FAILED(result) && g_renderState.frameCount < 5) {
                LogFormat("xrEndFrame returned error: %d", result);
            }
            return result;
        }
    }
    
    // No overlay, just pass through
    if (g_nextEndFrame) {
        return g_nextEndFrame(session, frameEndInfo);
    }
    
    return XR_SUCCESS;
}

// xrGetInstanceProcAddr hook to intercept function calls  
XrResult XRAPI_CALL Hook_xrGetInstanceProcAddr(XrInstance instance, const char* name, PFN_xrVoidFunction* function) {
    // Intercept functions we want to hook
    if (strcmp(name, "xrCreateSession") == 0) {
        LogMessage("Intercepting xrCreateSession");
        // Get the real function first
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextCreateSession));
        }
        *function = reinterpret_cast<PFN_xrVoidFunction>(Hook_xrCreateSession);
        return XR_SUCCESS;
    }
    
    if (strcmp(name, "xrDestroySession") == 0) {
        LogMessage("Intercepting xrDestroySession");
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextDestroySession));
        }
        *function = reinterpret_cast<PFN_xrVoidFunction>(Hook_xrDestroySession);
        return XR_SUCCESS;
    }
    
    if (strcmp(name, "xrEndFrame") == 0) {
        LogMessage("Intercepting xrEndFrame");
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextEndFrame));
        }
        *function = reinterpret_cast<PFN_xrVoidFunction>(Hook_xrEndFrame);
        return XR_SUCCESS;
    }
    
    if (strcmp(name, "xrLocateViews") == 0) {
        LogMessage("Intercepting xrLocateViews");
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextLocateViews));
        }
        *function = reinterpret_cast<PFN_xrVoidFunction>(Hook_xrLocateViews);
        return XR_SUCCESS;
    }
    
    // Also get swapchain functions we need
    if (strcmp(name, "xrCreateSwapchain") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextCreateSwapchain));
        }
    }
    
    if (strcmp(name, "xrDestroySwapchain") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextDestroySwapchain));
        }
    }
    
    if (strcmp(name, "xrEnumerateSwapchainImages") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextEnumerateSwapchainImages));
        }
    }
    
    if (strcmp(name, "xrAcquireSwapchainImage") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextAcquireSwapchainImage));
        }
    }
    
    if (strcmp(name, "xrWaitSwapchainImage") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextWaitSwapchainImage));
        }
    }
    
    if (strcmp(name, "xrReleaseSwapchainImage") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextReleaseSwapchainImage));
        }
    }
    
    if (strcmp(name, "xrCreateReferenceSpace") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextCreateReferenceSpace));
        }
    }
    
    if (strcmp(name, "xrDestroySpace") == 0) {
        if (g_nextGetInstanceProcAddr) {
            g_nextGetInstanceProcAddr(instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&g_nextDestroySpace));
        }
    }
    
    // For everything else, chain to next layer
    if (!g_nextGetInstanceProcAddr) {
        LogMessage("ERROR: g_nextGetInstanceProcAddr is NULL!");
        return XR_ERROR_FUNCTION_UNSUPPORTED;
    }
    
    return g_nextGetInstanceProcAddr(instance, name, function);
}

// Create API Layer Instance - this is where we get the next layer's dispatch table
XrResult XRAPI_CALL Hook_xrCreateApiLayerInstance(
    const XrInstanceCreateInfo* info,
    const XrApiLayerCreateInfo* layerInfo,
    XrInstance* instance) {
    
    LogMessage("Hook_xrCreateApiLayerInstance called");
    
    // Get the next layer's getInstanceProcAddr from the layer info chain
    if (layerInfo && layerInfo->nextInfo && layerInfo->nextInfo->nextGetInstanceProcAddr) {
        g_nextGetInstanceProcAddr = layerInfo->nextInfo->nextGetInstanceProcAddr;
        LogMessage("Stored next layer's getInstanceProcAddr from createInstance");
    } else {
        LogMessage("ERROR: No next layer info in createInstance!");
        return XR_ERROR_INITIALIZATION_FAILED;
    }
    
    // Call the next layer's createInstance
    if (layerInfo->nextInfo && layerInfo->nextInfo->nextCreateApiLayerInstance) {
        return layerInfo->nextInfo->nextCreateApiLayerInstance(info, layerInfo, instance);
    } else {
        LogMessage("ERROR: No next createInstance!");
        return XR_ERROR_INITIALIZATION_FAILED;
    }
}

// Layer initialization - export the negotiate function
extern "C" {
    __declspec(dllexport) XrResult XRAPI_CALL xrNegotiateLoaderApiLayerInterface(
        const XrNegotiateLoaderInfo* loaderInfo,
        const char* layerName,
        XrNegotiateApiLayerRequest* apiLayerRequest) {
        
        LogFormat("xrNegotiateLoaderApiLayerInterface: layer=%s", layerName);
        
        // Check if this is a DCS process - bail out early for other VR apps
        if (!IsDcsHostProcess()) {
            LogMessage("Not a DCS process - layer will not activate");
            return XR_ERROR_INITIALIZATION_FAILED;
        }
        
        // Validate loader info
        if (!loaderInfo || loaderInfo->structType != XR_LOADER_INTERFACE_STRUCT_LOADER_INFO ||
            loaderInfo->structVersion != XR_LOADER_INFO_STRUCT_VERSION) {
            LogMessage("ERROR: Invalid loaderInfo!");
            return XR_ERROR_INITIALIZATION_FAILED;
        }
        
        // Set our hook functions
        apiLayerRequest->layerInterfaceVersion = XR_CURRENT_LOADER_API_LAYER_VERSION;
        apiLayerRequest->layerApiVersion = XR_CURRENT_API_VERSION;
        apiLayerRequest->getInstanceProcAddr = reinterpret_cast<PFN_xrGetInstanceProcAddr>(Hook_xrGetInstanceProcAddr);
        apiLayerRequest->createApiLayerInstance = reinterpret_cast<PFN_xrCreateApiLayerInstance>(Hook_xrCreateApiLayerInstance);
        
        LogMessage("Negotiation successful");
        return XR_SUCCESS;
    }
}
