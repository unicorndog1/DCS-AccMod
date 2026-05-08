// perf.h - lightweight QPC-based perf instrumentation for the OpenXR layer.
// All entry points are thread-safe (RecordDuration/RecordCounter use a CRITICAL_SECTION).
// Snapshots are flushed to the layer log AND a CSV file every 5s, or on demand.

#pragma once

#include <stdint.h>

namespace perf {

// Stable order — referenced by name in CSV/log output.
enum Key : int {
    K_xrEndFrame = 0,    // duration: full Hook_xrEndFrame
    K_renderText,        // duration: RenderTextToTexture total
    K_pixelLoop,         // duration: just the per-pixel circle drawing loop
    K_mapUnmap,          // duration: Map -> Unmap window
    K_copyResource,      // duration: CopyResource staging->swapchain
    K_udpRecvIter,       // duration: one UDP recv loop iteration that handled a packet
    K_circles,           // counter: circles.size() at frame end
    K_dirtyHits,         // counter (Phase 1+): dirty-cache short-circuit fired
    K_dirtyMisses,       // counter (Phase 1+): dirty-cache miss; full re-render
    K_COUNT
};

// Initialize QPC frequency, open CSV, read env vars (ACCMOD_RUN_ID/PHASE/SCENARIO).
void Init();
void Shutdown();

// Wall-clock-ish QPC value, in ticks.
int64_t Now();

// Record a duration sample. qpcStart should come from Now() at scope entry.
void RecordDuration(Key k, int64_t qpcStart);

// Record an arbitrary scalar (not a duration). Used for circles.size, dirty hits, etc.
void RecordCounter(Key k, double value);

// Call once per frame from xrEndFrame. Increments frame counter and flushes
// a snapshot every ~5 seconds.
void OnFrameEnd();

// Force-flush a snapshot now (UDP P command, or shutdown).
void DumpSnapshot(const char* trigger);

// Emit one-shot build/toggle/state banner lines. Safe to call repeatedly.
void EmitBuildBanner();
void EmitToggles(int useGpuRasterizer, int dirtyFlag, int swapW, int swapH, int mapDiscard);
void EmitState(double circles, double quadDistance, double quadTanHalfFov,
               double quadAspect, int useGpuRasterizer, double dirtyHitRatio);

// RAII helper.
class ScopedTimer {
    Key key_;
    int64_t start_;
public:
    explicit ScopedTimer(Key k);
    ~ScopedTimer();
};

} // namespace perf

// Concatenation helpers for unique scope-timer names per __LINE__.
#define PERF_CAT_INNER(a, b) a##b
#define PERF_CAT(a, b) PERF_CAT_INNER(a, b)
#define PERF_SCOPE(k) perf::ScopedTimer PERF_CAT(_perf_scope_, __LINE__)(k)
