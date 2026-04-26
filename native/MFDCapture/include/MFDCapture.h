#pragma once

#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <cstdint>
#include <string>

using Microsoft::WRL::ComPtr;

namespace AccMod {

/**
 * @brief Captures screen output from a specific monitor using DXGI Desktop Duplication API
 * 
 * This class provides efficient frame capture from virtual monitors where DCS renders MFDs.
 * Uses GPU-direct capture with dirty region tracking for optimal performance.
 */
class MFDCapture {
public:
    struct Config {
        int monitorIndex;           // Monitor to capture (0 = primary, 1+ = additional)
        int expectedWidth;          // Expected resolution width
        int expectedHeight;         // Expected resolution height
        int targetFPS;              // Target frame capture rate (0 = unlimited)
        bool enableDirtyRegions;    // Track only changed regions for optimization
        std::wstring monitorName;   // Optional: filter by name (e.g., "DCS_MFD_LEFT")
    };

    struct FrameInfo {
        uint64_t frameNumber;       // Sequential frame number
        uint64_t presentTime;       // When frame was presented (QPC ticks)
        int pointerX;               // Mouse cursor X position (-1 if invisible)
        int pointerY;               // Mouse cursor Y position (-1 if invisible)
        bool cursorVisible;         // Is cursor visible on this display
        int dirtyRegionCount;       // Number of dirty rectangles
        int moveRegionCount;        // Number of move rectangles
    };

    MFDCapture();
    ~MFDCapture();

    // Disable copy
    MFDCapture(const MFDCapture&) = delete;
    MFDCapture& operator=(const MFDCapture&) = delete;

    /**
     * @brief Initialize the capture system for the specified monitor
     * @param config Configuration parameters
     * @return true if initialization succeeded
     */
    bool Initialize(const Config& config);

    /**
     * @brief Capture the next frame from the virtual monitor
     * @param outTexture Output texture containing the captured frame (caller must release)
     * @param outInfo Optional frame metadata
     * @param timeoutMs Timeout in milliseconds (0 = non-blocking)
     * @return true if a new frame was captured
     */
    bool CaptureFrame(ID3D11Texture2D** outTexture, FrameInfo* outInfo = nullptr, int timeoutMs = 100);

    /**
     * @brief Get the captured frame as raw BGRA bytes (CPU copy)
     * @param outBuffer Output buffer (must be at least width * height * 4 bytes)
     * @param bufferSize Size of output buffer
     * @return true if copy succeeded
     * @note This is slower than CaptureFrame() - use only when GPU texture is not sufficient
     */
    bool GetFrameData(uint8_t* outBuffer, size_t bufferSize);

    /**
     * @brief Release the current frame (must be called after CaptureFrame before next capture)
     */
    void ReleaseFrame();

    /**
     * @brief Shutdown and release all resources
     */
    void Shutdown();

    /**
     * @brief Check if capture is currently active
     */
    bool IsInitialized() const { return m_initialized; }

    /**
     * @brief Get the actual resolution of the captured display
     */
    void GetResolution(int* outWidth, int* outHeight) const;

    /**
     * @brief Get statistics about capture performance
     */
    struct Stats {
        uint64_t totalFramesCaptured;
        uint64_t framesDropped;
        float averageCaptureTimeMs;
        float averageFPS;
    };
    Stats GetStats() const { return m_stats; }

    /**
     * @brief Enumerate available displays
     * @param outDisplays Array to receive display info
     * @param maxDisplays Maximum number of displays to enumerate
     * @return Number of displays found
     */
    static int EnumerateDisplays(std::wstring* outDisplays, int maxDisplays);

private:
    bool CreateD3D11Device();
    bool FindTargetOutput();
    bool CreateDuplication();
    void ProcessFrameMetadata(const DXGI_OUTDUPL_FRAME_INFO& frameInfo);
    void UpdateStats();

    Config m_config;
    bool m_initialized;

    // DirectX resources
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<IDXGIAdapter1> m_adapter;
    ComPtr<IDXGIOutput1> m_output;
    ComPtr<IDXGIOutputDuplication> m_duplication;
    ComPtr<ID3D11Texture2D> m_acquiredFrame;

    // Frame tracking
    uint64_t m_frameCount;
    uint64_t m_lastCaptureTime;
    FrameInfo m_lastFrameInfo;

    // Statistics
    Stats m_stats;
    uint64_t m_statStartTime;
    float m_captureTimesMs[60];  // Rolling window for average calculation
    int m_captureTimeIndex;

    // Display metadata
    int m_displayWidth;
    int m_displayHeight;
    DXGI_OUTPUT_DESC m_outputDesc;
};

} // namespace AccMod
