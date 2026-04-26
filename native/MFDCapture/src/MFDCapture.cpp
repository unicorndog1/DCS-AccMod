#include "MFDCapture.h"
#include <vector>
#include <thread>
#include <chrono>
#include <dxgi.h>

namespace AccMod {

MFDCapture::MFDCapture()
    : m_initialized(false)
    , m_frameCount(0)
    , m_lastCaptureTime(0)
    , m_displayWidth(0)
    , m_displayHeight(0)
    , m_captureTimeIndex(0)
{
    ZeroMemory(&m_stats, sizeof(m_stats));
    ZeroMemory(&m_lastFrameInfo, sizeof(m_lastFrameInfo));
    ZeroMemory(&m_outputDesc, sizeof(m_outputDesc));
    ZeroMemory(m_captureTimesMs, sizeof(m_captureTimesMs));
}

MFDCapture::~MFDCapture()
{
    Shutdown();
}

bool MFDCapture::Initialize(const Config& config)
{
    if (m_initialized) {
        Shutdown();
    }

    m_config = config;

    // Step 1: Create D3D11 device
    if (!CreateD3D11Device()) {
        return false;
    }

    // Step 2: Find target output (virtual monitor)
    if (!FindTargetOutput()) {
        return false;
    }

    // Step 3: Create desktop duplication
    if (!CreateDuplication()) {
        return false;
    }

    m_initialized = true;
    m_frameCount = 0;
    m_statStartTime = GetTickCount64();

    return true;
}

bool MFDCapture::CreateD3D11Device()
{
    // Feature levels to try
    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0
    };

    D3D_FEATURE_LEVEL featureLevel;
    HRESULT hr = D3D11CreateDevice(
        nullptr,                    // Use default adapter
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        0,
        featureLevels,
        ARRAYSIZE(featureLevels),
        D3D11_SDK_VERSION,
        &m_device,
        &featureLevel,
        &m_context
    );

    if (FAILED(hr)) {
        // Try with WARP software renderer as fallback
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            0,
            featureLevels,
            ARRAYSIZE(featureLevels),
            D3D11_SDK_VERSION,
            &m_device,
            &featureLevel,
            &m_context
        );
    }

    return SUCCEEDED(hr);
}

bool MFDCapture::FindTargetOutput()
{
    // Get DXGI device from D3D11 device
    ComPtr<IDXGIDevice> dxgiDevice;
    HRESULT hr = m_device.As(&dxgiDevice);
    if (FAILED(hr)) return false;

    // Get adapter
    ComPtr<IDXGIAdapter> adapter;
    hr = dxgiDevice->GetAdapter(&adapter);
    if (FAILED(hr)) return false;

    hr = adapter.As(&m_adapter);
    if (FAILED(hr)) return false;

    // Enumerate outputs to find target monitor
    ComPtr<IDXGIOutput> output;
    int outputIndex = 0;

    while (m_adapter->EnumOutputs(outputIndex, &output) != DXGI_ERROR_NOT_FOUND) {
        DXGI_OUTPUT_DESC desc;
        output->GetDesc(&desc);

        // Check if this is the target monitor
        bool isTarget = (outputIndex == m_config.monitorIndex);

        // Optionally filter by name
        if (!m_config.monitorName.empty()) {
            isTarget = isTarget && (m_config.monitorName == desc.DeviceName);
        }

        if (isTarget) {
            m_outputDesc = desc;
            m_displayWidth = desc.DesktopCoordinates.right - desc.DesktopCoordinates.left;
            m_displayHeight = desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top;

            hr = output.As(&m_output);
            return SUCCEEDED(hr);
        }

        outputIndex++;
        output.Reset();
    }

    return false; // Target output not found
}

bool MFDCapture::CreateDuplication()
{
    HRESULT hr = m_output->DuplicateOutput(m_device.Get(), &m_duplication);
    
    if (hr == DXGI_ERROR_NOT_CURRENTLY_AVAILABLE) {
        // Too many duplications already active
        return false;
    }

    return SUCCEEDED(hr);
}

bool MFDCapture::CaptureFrame(ID3D11Texture2D** outTexture, FrameInfo* outInfo, int timeoutMs)
{
    if (!m_initialized || !outTexture) {
        return false;
    }

    // Release previous frame if still held
    if (m_acquiredFrame) {
        ReleaseFrame();
    }

    auto captureStart = std::chrono::high_resolution_clock::now();

    // Try to acquire next frame
    ComPtr<IDXGIResource> desktopResource;
    DXGI_OUTDUPL_FRAME_INFO frameInfo;
    ZeroMemory(&frameInfo, sizeof(frameInfo));

    HRESULT hr = m_duplication->AcquireNextFrame(timeoutMs, &frameInfo, &desktopResource);

    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
        // No new frame available yet (not an error)
        return false;
    }

    if (hr == DXGI_ERROR_ACCESS_LOST) {
        // Desktop duplication interface lost (happens on mode changes, etc.)
        // Need to recreate duplication
        m_duplication.Reset();
        if (!CreateDuplication()) {
            return false;
        }
        return false;
    }

    if (FAILED(hr)) {
        return false;
    }

    // Query for ID3D11Texture2D interface
    hr = desktopResource.As(&m_acquiredFrame);
    if (FAILED(hr)) {
        m_duplication->ReleaseFrame();
        return false;
    }

    // Return texture to caller (caller must call ReleaseFrame after use)
    *outTexture = m_acquiredFrame.Get();
    (*outTexture)->AddRef();

    // Process and return frame info if requested
    if (outInfo) {
        ProcessFrameMetadata(frameInfo);
        *outInfo = m_lastFrameInfo;
    }

    // Update statistics
    auto captureEnd = std::chrono::high_resolution_clock::now();
    float captureMs = std::chrono::duration<float, std::milli>(captureEnd - captureStart).count();
    m_captureTimesMs[m_captureTimeIndex] = captureMs;
    m_captureTimeIndex = (m_captureTimeIndex + 1) % 60;

    m_stats.totalFramesCaptured++;
    UpdateStats();

    return true;
}

bool MFDCapture::GetFrameData(uint8_t* outBuffer, size_t bufferSize)
{
    if (!m_acquiredFrame || !outBuffer) {
        return false;
    }

    size_t requiredSize = m_displayWidth * m_displayHeight * 4; // BGRA
    if (bufferSize < requiredSize) {
        return false;
    }

    // Create staging texture for CPU readback
    D3D11_TEXTURE2D_DESC desc;
    m_acquiredFrame->GetDesc(&desc);

    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;

    ComPtr<ID3D11Texture2D> stagingTexture;
    HRESULT hr = m_device->CreateTexture2D(&desc, nullptr, &stagingTexture);
    if (FAILED(hr)) return false;

    // Copy GPU texture to staging texture
    m_context->CopyResource(stagingTexture.Get(), m_acquiredFrame.Get());

    // Map staging texture to CPU memory
    D3D11_MAPPED_SUBRESOURCE mapped;
    hr = m_context->Map(stagingTexture.Get(), 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) return false;

    // Copy to output buffer
    if (mapped.RowPitch == m_displayWidth * 4) {
        // Contiguous memory, single copy
        memcpy(outBuffer, mapped.pData, requiredSize);
    } else {
        // Row-by-row copy (handle pitch)
        for (int y = 0; y < m_displayHeight; y++) {
            memcpy(
                outBuffer + y * m_displayWidth * 4,
                (uint8_t*)mapped.pData + y * mapped.RowPitch,
                m_displayWidth * 4
            );
        }
    }

    m_context->Unmap(stagingTexture.Get(), 0);
    return true;
}

void MFDCapture::ReleaseFrame()
{
    if (m_acquiredFrame) {
        m_acquiredFrame.Reset();
    }

    if (m_duplication) {
        m_duplication->ReleaseFrame();
    }
}

void MFDCapture::Shutdown()
{
    if (m_acquiredFrame) {
        ReleaseFrame();
    }

    m_duplication.Reset();
    m_output.Reset();
    m_adapter.Reset();
    m_context.Reset();
    m_device.Reset();

    m_initialized = false;
}

void MFDCapture::GetResolution(int* outWidth, int* outHeight) const
{
    if (outWidth) *outWidth = m_displayWidth;
    if (outHeight) *outHeight = m_displayHeight;
}

void MFDCapture::ProcessFrameMetadata(const DXGI_OUTDUPL_FRAME_INFO& frameInfo)
{
    m_lastFrameInfo.frameNumber = m_frameCount++;
    m_lastFrameInfo.presentTime = frameInfo.LastPresentTime.QuadPart;
    m_lastFrameInfo.cursorVisible = frameInfo.PointerPosition.Visible != 0;
    
    if (m_lastFrameInfo.cursorVisible) {
        m_lastFrameInfo.pointerX = frameInfo.PointerPosition.Position.x;
        m_lastFrameInfo.pointerY = frameInfo.PointerPosition.Position.y;
    } else {
        m_lastFrameInfo.pointerX = -1;
        m_lastFrameInfo.pointerY = -1;
    }

    // TODO: Process dirty and move rectangles if enabled
    m_lastFrameInfo.dirtyRegionCount = 0;
    m_lastFrameInfo.moveRegionCount = 0;
}

void MFDCapture::UpdateStats()
{
    uint64_t elapsed = GetTickCount64() - m_statStartTime;
    if (elapsed > 0) {
        m_stats.averageFPS = (float)m_stats.totalFramesCaptured / ((float)elapsed / 1000.0f);
    }

    // Calculate average capture time from rolling window
    float sum = 0.0f;
    int count = 0;
    for (int i = 0; i < 60; i++) {
        if (m_captureTimesMs[i] > 0.0f) {
            sum += m_captureTimesMs[i];
            count++;
        }
    }
    if (count > 0) {
        m_stats.averageCaptureTimeMs = sum / count;
    }
}

int MFDCapture::EnumerateDisplays(std::wstring* outDisplays, int maxDisplays)
{
    // Create temporary D3D device for enumeration
    ComPtr<ID3D11Device> device;
    D3D_FEATURE_LEVEL featureLevel;
    D3D_FEATURE_LEVEL featureLevels[] = { D3D_FEATURE_LEVEL_11_0 };

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        0,
        featureLevels,
        1,
        D3D11_SDK_VERSION,
        &device,
        &featureLevel,
        nullptr
    );

    if (FAILED(hr)) return 0;

    ComPtr<IDXGIDevice> dxgiDevice;
    hr = device.As(&dxgiDevice);
    if (FAILED(hr)) return 0;

    ComPtr<IDXGIAdapter> adapter;
    hr = dxgiDevice->GetAdapter(&adapter);
    if (FAILED(hr)) return 0;

    // Enumerate outputs
    int count = 0;
    ComPtr<IDXGIOutput> output;
    
    for (int i = 0; i < maxDisplays && adapter->EnumOutputs(i, &output) != DXGI_ERROR_NOT_FOUND; i++) {
        DXGI_OUTPUT_DESC desc;
        output->GetDesc(&desc);
        
        if (outDisplays) {
            outDisplays[count] = desc.DeviceName;
        }
        
        count++;
        output.Reset();
    }

    return count;
}

} // namespace AccMod
