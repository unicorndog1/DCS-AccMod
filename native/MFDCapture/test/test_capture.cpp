#include "MFDCapture.h"
#include <iostream>
#include <fstream>
#include <chrono>
#include <thread>
#include <vector>

using namespace AccMod;

void SaveFrameToBMP(const uint8_t* data, int width, int height, const char* filename)
{
    // BMP file header
    #pragma pack(push, 1)
    struct BMPHeader {
        uint16_t signature = 0x4D42; // "BM"
        uint32_t fileSize;
        uint32_t reserved = 0;
        uint32_t dataOffset = 54;
        uint32_t headerSize = 40;
        int32_t width;
        int32_t height;
        uint16_t planes = 1;
        uint16_t bitsPerPixel = 32;
        uint32_t compression = 0;
        uint32_t imageSize;
        int32_t xPixelsPerMeter = 0;
        int32_t yPixelsPerMeter = 0;
        uint32_t colorsUsed = 0;
        uint32_t colorsImportant = 0;
    };
    #pragma pack(pop)

    BMPHeader header;
    header.width = width;
    header.height = -height; // Negative for top-down
    header.imageSize = width * height * 4;
    header.fileSize = 54 + header.imageSize;

    std::ofstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Failed to create BMP file: " << filename << std::endl;
        return;
    }

    file.write(reinterpret_cast<const char*>(&header), sizeof(header));
    file.write(reinterpret_cast<const char*>(data), header.imageSize);
    
    std::cout << "Saved frame to: " << filename << std::endl;
}

int main(int argc, char** argv)
{
    std::cout << "=== MFD Capture Test ===" << std::endl;
    std::cout << std::endl;

    // Enumerate available displays
    std::cout << "Available displays:" << std::endl;
    std::wstring displays[10];
    int displayCount = MFDCapture::EnumerateDisplays(displays, 10);
    
    for (int i = 0; i < displayCount; i++) {
        std::wcout << "  [" << i << "] " << displays[i] << std::endl;
    }
    std::cout << std::endl;

    // Get monitor index from user
    int monitorIndex = 0;
    if (argc > 1) {
        monitorIndex = atoi(argv[1]);
    } else {
        std::cout << "Enter monitor index to capture (0-" << (displayCount - 1) << "): ";
        std::cin >> monitorIndex;
    }

    if (monitorIndex < 0 || monitorIndex >= displayCount) {
        std::cerr << "Invalid monitor index!" << std::endl;
        return 1;
    }

    std::cout << std::endl;
    std::cout << "Capturing from monitor " << monitorIndex << "..." << std::endl;

    // Initialize capture
    MFDCapture capture;
    MFDCapture::Config config;
    config.monitorIndex = monitorIndex;
    config.expectedWidth = 800;
    config.expectedHeight = 800;
    config.targetFPS = 30;
    config.enableDirtyRegions = true;

    if (!capture.Initialize(config)) {
        std::cerr << "Failed to initialize MFD capture!" << std::endl;
        std::cerr << "Make sure:" << std::endl;
        std::cerr << "  - Virtual Display Driver is installed" << std::endl;
        std::cerr << "  - Virtual monitors are enabled" << std::endl;
        std::cerr << "  - DCS is rendering to the selected monitor" << std::endl;
        return 1;
    }

    int width, height;
    capture.GetResolution(&width, &height);
    std::cout << "Capture initialized: " << width << "x" << height << std::endl;
    std::cout << std::endl;

    // Allocate buffer for frame data
    std::vector<uint8_t> frameBuffer(width * height * 4);

    std::cout << "Capturing frames (Press Ctrl+C to stop)..." << std::endl;
    std::cout << "Frames will be saved every 5 seconds" << std::endl;
    std::cout << std::endl;

    int framesCaptured = 0;
    int framesSaved = 0;
    auto lastSaveTime = std::chrono::steady_clock::now();
    auto startTime = std::chrono::steady_clock::now();

    while (framesCaptured < 1000) { // Capture 1000 frames then stop
        ID3D11Texture2D* frame = nullptr;
        MFDCapture::FrameInfo info;

        if (capture.CaptureFrame(&frame, &info, 500)) {
            framesCaptured++;

            // Print frame info every 30 frames
            if (framesCaptured % 30 == 0) {
                auto stats = capture.GetStats();
                std::cout << "Frame " << framesCaptured 
                          << " | FPS: " << stats.averageFPS 
                          << " | Capture: " << stats.averageCaptureTimeMs << "ms"
                          << std::endl;
            }

            // Save frame every 5 seconds
            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - lastSaveTime);
            
            if (elapsed.count() >= 5) {
                // Copy frame to CPU
                if (capture.GetFrameData(frameBuffer.data(), frameBuffer.size())) {
                    char filename[256];
                    sprintf_s(filename, "mfd_capture_%03d.bmp", framesSaved);
                    SaveFrameToBMP(frameBuffer.data(), width, height, filename);
                    framesSaved++;
                }
                lastSaveTime = now;
            }

            // Release frame
            frame->Release();
            capture.ReleaseFrame();
        }

        // Sleep to match target FPS
        if (config.targetFPS > 0) {
            int sleepMs = 1000 / config.targetFPS;
            std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
        }
    }

    // Print final statistics
    auto endTime = std::chrono::steady_clock::now();
    auto totalTime = std::chrono::duration_cast<std::chrono::seconds>(endTime - startTime);
    auto stats = capture.GetStats();

    std::cout << std::endl;
    std::cout << "=== Capture Statistics ===" << std::endl;
    std::cout << "Total frames captured: " << stats.totalFramesCaptured << std::endl;
    std::cout << "Frames dropped: " << stats.framesDropped << std::endl;
    std::cout << "Average FPS: " << stats.averageFPS << std::endl;
    std::cout << "Average capture time: " << stats.averageCaptureTimeMs << " ms" << std::endl;
    std::cout << "Total time: " << totalTime.count() << " seconds" << std::endl;
    std::cout << "Frames saved: " << framesSaved << std::endl;

    capture.Shutdown();

    std::cout << std::endl;
    std::cout << "Test completed successfully!" << std::endl;

    return 0;
}
