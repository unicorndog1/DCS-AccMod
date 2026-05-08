// perf.cpp - implementation of the lightweight perf aggregator.

#include "perf.h"
#include "common.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>

namespace perf {

// Master kill-switch. Flip to false to re-enable instrumentation.
// When true, Init() bails immediately and all Record*/Emit*/OnFrameEnd/
// DumpSnapshot calls become no-ops via the existing `g_init` guards.
static constexpr bool kPerfDisabled = true;

namespace {

constexpr int kRing = 1024;          // samples per key (>= 5s @ ~200 Hz)
constexpr double kSnapshotSec = 5.0; // ACCMOD_PERF row interval
constexpr double kStateSec = 30.0;   // ACCMOD_STATE row interval

struct KeyState {
    double samples[kRing];
    int count;       // total samples ever recorded (for rate)
    int head;        // next write index
    int windowCount; // samples since last snapshot
    bool isCounter;  // if true, samples are not durations (us)
};

CRITICAL_SECTION g_perfCs;
bool g_init = false;
int64_t g_qpcFreq = 1;
int64_t g_initQpc = 0;
KeyState g_keys[K_COUNT];
const char* g_keyNames[K_COUNT] = {
    "xrEndFrame", "renderText", "pixelLoop", "mapUnmap", "copyResource",
    "udpRecvIter", "circles", "dirtyHits", "dirtyMisses",
};
const bool g_keyIsCounter[K_COUNT] = {
    false, false, false, false, false, false, true, true, true,
};

uint64_t g_frameCounter = 0;
double g_lastSnapshotSec = 0.0;
double g_lastStateSec = 0.0;
FILE* g_csv = nullptr;

// Env / build identity.
char g_runId[128] = "unknown";
char g_phase[64] = "unknown";
char g_scenario[64] = "unknown";

// Reported toggles (last EmitToggles values — used in periodic state lines).
int g_tUseGpu = 0;
int g_tDirtyFlag = 0;
int g_tSwapW = 0;
int g_tSwapH = 0;
int g_tMapDiscard = 0;

double SecondsSinceInit() {
    int64_t now;
    QueryPerformanceCounter(reinterpret_cast<LARGE_INTEGER*>(&now));
    return (double)(now - g_initQpc) / (double)g_qpcFreq;
}

double UsFromQpcDelta(int64_t delta) {
    return (double)delta * 1e6 / (double)g_qpcFreq;
}

void GetEnvOr(const char* name, const char* def, char* out, size_t outSize) {
    DWORD n = GetEnvironmentVariableA(name, out, (DWORD)outSize);
    if (n == 0 || n >= outSize) {
        strncpy_s(out, outSize, def, _TRUNCATE);
    }
}

bool g_runIdSynthesized = false;

void SynthesizeRunId(char* out, size_t outSize) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    DWORD pid = GetCurrentProcessId();
    _snprintf_s(out, outSize, _TRUNCATE,
        "auto-%04d%02d%02d-%02d%02d%02d-%lu",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, pid);
}

// Drop a small coordination file in %TEMP% so the Lua side can adopt the
// same run id when the user runs DCS without the wrapper script.
void WriteCurrentRunFile() {
    char path[MAX_PATH];
    GetTempPathA(MAX_PATH, path);
    strcat_s(path, "AccMod_current_run.txt");
    FILE* f = nullptr;
    fopen_s(&f, path, "w");
    if (!f) return;
    SYSTEMTIME st;
    GetSystemTime(&st);
    FILETIME ft;
    SystemTimeToFileTime(&st, &ft);
    uint64_t ftTicks = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    uint64_t unixMs = (ftTicks - 116444736000000000ULL) / 10000ULL;
    // Format: line1=runId, 2=phase, 3=scenario, 4=writeUnixMs, 5=pid
    fprintf(f, "%s\n%s\n%s\n%llu\n%lu\n",
        g_runId, g_phase, g_scenario,
        (unsigned long long)unixMs, GetCurrentProcessId());
    fclose(f);
}

// Keep at most `keep` files matching `prefix*<suffix>` in %TEMP%, deleting the
// oldest by mtime. Best-effort; failures are silently ignored.
void PrunePerfFiles(const char* prefix, const char* suffix, int keep) {
    char tempDir[MAX_PATH];
    GetTempPathA(MAX_PATH, tempDir);
    char pattern[MAX_PATH];
    _snprintf_s(pattern, sizeof(pattern), _TRUNCATE, "%s%s*%s", tempDir, prefix, suffix);

    struct Entry { char name[MAX_PATH]; FILETIME mtime; };
    std::vector<Entry> entries;
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        Entry e{};
        _snprintf_s(e.name, sizeof(e.name), _TRUNCATE, "%s%s", tempDir, fd.cFileName);
        e.mtime = fd.ftLastWriteTime;
        entries.push_back(e);
    } while (FindNextFileA(h, &fd));
    FindClose(h);

    if ((int)entries.size() <= keep) return;
    std::sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b) {
        return CompareFileTime(&a.mtime, &b.mtime) < 0; // oldest first
    });
    int toDelete = (int)entries.size() - keep;
    for (int i = 0; i < toDelete; ++i) {
        DeleteFileA(entries[i].name);
    }
}

void OpenCsv() {
    if (g_csv) return;
    char path[MAX_PATH];
    GetTempPathA(MAX_PATH, path);
    // Per-run filename so adhoc sessions don't merge into a single CSV.
    char file[128];
    _snprintf_s(file, sizeof(file), _TRUNCATE,
        "DCS_AccMod_OpenXR_perf_%s.csv", g_runId);
    strcat_s(path, file);
    fopen_s(&g_csv, path, "a");
    if (g_csv) {
        // Header only if file is empty.
        fseek(g_csv, 0, SEEK_END);
        long sz = ftell(g_csv);
        if (sz == 0) {
            fprintf(g_csv,
                "ts_ms,run_id,source,frame,key,p50_us,p95_us,max_us,count,extra\n");
        }
        fflush(g_csv);
    }
    PrunePerfFiles("DCS_AccMod_OpenXR_perf_", ".csv", 20);
}

void EmitPerfRow(const char* key, double p50, double p95, double maxV, int count, const char* extra) {
    SYSTEMTIME st;
    GetSystemTime(&st);
    FILETIME ft;
    SystemTimeToFileTime(&st, &ft);
    uint64_t ftTicks = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    // 100ns ticks since 1601 -> ms since 1970
    uint64_t unixMs = (ftTicks - 116444736000000000ULL) / 10000ULL;

    LogFormat("ACCMOD_PERF,%s,layer,%llu,%llu,%s,%.2f,%.2f,%.2f,%d,%s",
        g_runId, (unsigned long long)unixMs, (unsigned long long)g_frameCounter,
        key, p50, p95, maxV, count, extra ? extra : "");

    if (g_csv) {
        fprintf(g_csv, "%llu,%s,layer,%llu,%s,%.2f,%.2f,%.2f,%d,%s\n",
            (unsigned long long)unixMs, g_runId, (unsigned long long)g_frameCounter,
            key, p50, p95, maxV, count, extra ? extra : "");
        fflush(g_csv);
    }
}

void ComputeAndEmitKey(KeyState& ks, const char* name) {
    if (ks.windowCount == 0) {
        EmitPerfRow(name, 0.0, 0.0, 0.0, 0, ks.isCounter ? "counter" : "us");
        return;
    }

    int n = (ks.count < kRing) ? ks.count : kRing;
    if (n <= 0) return;

    std::vector<double> tmp(n);
    for (int i = 0; i < n; ++i) tmp[i] = ks.samples[i];
    std::sort(tmp.begin(), tmp.end());

    auto pct = [&](double p) -> double {
        int idx = (int)((p / 100.0) * (n - 1) + 0.5);
        if (idx < 0) idx = 0;
        if (idx >= n) idx = n - 1;
        return tmp[idx];
    };

    double p50 = pct(50.0);
    double p95 = pct(95.0);
    double mx = tmp[n - 1];

    EmitPerfRow(name, p50, p95, mx, ks.windowCount, ks.isCounter ? "counter" : "us");
    ks.windowCount = 0;
}

} // namespace

void Init() {
    if (g_init) return;
    if (kPerfDisabled) {
        // Leave g_init=false so all other entry points are no-ops.
        return;
    }
    InitializeCriticalSection(&g_perfCs);

    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    g_qpcFreq = f.QuadPart;
    g_initQpc = c.QuadPart;

    for (int i = 0; i < K_COUNT; ++i) {
        memset(g_keys[i].samples, 0, sizeof(g_keys[i].samples));
        g_keys[i].count = 0;
        g_keys[i].head = 0;
        g_keys[i].windowCount = 0;
        g_keys[i].isCounter = g_keyIsCounter[i];
    }

    GetEnvOr("ACCMOD_RUN_ID", "", g_runId, sizeof(g_runId));
    GetEnvOr("ACCMOD_PHASE", "", g_phase, sizeof(g_phase));
    GetEnvOr("ACCMOD_SCENARIO", "", g_scenario, sizeof(g_scenario));

    // No wrapper script env vars present? Tag this as an adhoc session and
    // synthesize an id so each DCS launch produces a unique, identifiable run.
    if (g_runId[0] == 0) {
        SynthesizeRunId(g_runId, sizeof(g_runId));
        g_runIdSynthesized = true;
    }
    if (g_phase[0] == 0) {
        strncpy_s(g_phase, sizeof(g_phase), "adhoc", _TRUNCATE);
    }
    if (g_scenario[0] == 0) {
        strncpy_s(g_scenario, sizeof(g_scenario), "live", _TRUNCATE);
    }

    OpenCsv();

    // Always write the coordination file so the Lua side can adopt our run id
    // when launched without the wrapper. Wrapper-driven runs also benefit from
    // having both sides agree on a single id even if env propagation differs.
    WriteCurrentRunFile();

    g_lastSnapshotSec = 0.0;
    g_lastStateSec = 0.0;
    g_init = true;
}

void Shutdown() {
    if (!g_init) return;
    DumpSnapshot("shutdown");
    if (g_csv) {
        fclose(g_csv);
        g_csv = nullptr;
    }
    DeleteCriticalSection(&g_perfCs);
    g_init = false;
}

int64_t Now() {
    int64_t v;
    QueryPerformanceCounter(reinterpret_cast<LARGE_INTEGER*>(&v));
    return v;
}

void RecordDuration(Key k, int64_t qpcStart) {
    if (!g_init || k < 0 || k >= K_COUNT) return;
    int64_t end = Now();
    double us = UsFromQpcDelta(end - qpcStart);
    CriticalSectionLock lock(g_perfCs);
    KeyState& ks = g_keys[k];
    ks.samples[ks.head] = us;
    ks.head = (ks.head + 1) % kRing;
    if (ks.count < kRing) ks.count++;
    ks.windowCount++;
}

void RecordCounter(Key k, double value) {
    if (!g_init || k < 0 || k >= K_COUNT) return;
    CriticalSectionLock lock(g_perfCs);
    KeyState& ks = g_keys[k];
    ks.samples[ks.head] = value;
    ks.head = (ks.head + 1) % kRing;
    if (ks.count < kRing) ks.count++;
    ks.windowCount++;
}

void OnFrameEnd() {
    if (!g_init) return;
    g_frameCounter++;

    double t = SecondsSinceInit();

    if (t - g_lastSnapshotSec >= kSnapshotSec) {
        g_lastSnapshotSec = t;
        DumpSnapshot("interval");
    }
    if (t - g_lastStateSec >= kStateSec) {
        g_lastStateSec = t;
        // State emission is driven by callers (they have circles/quad info).
        // We only timestamp the slot here; main.cpp / render.cpp call EmitState.
    }
}

void DumpSnapshot(const char* trigger) {
    if (!g_init) return;
    CriticalSectionLock lock(g_perfCs);
    LogFormat("ACCMOD_PERF_SNAPSHOT trigger=%s frame=%llu run_id=%s phase=%s scenario=%s",
        trigger, (unsigned long long)g_frameCounter, g_runId, g_phase, g_scenario);
    for (int i = 0; i < K_COUNT; ++i) {
        ComputeAndEmitKey(g_keys[i], g_keyNames[i]);
    }
}

void EmitBuildBanner() {
    if (!g_init) Init();
    if (!g_init) return;
    char gitSha[64];
    GetEnvOr("ACCMOD_GIT_SHA", "unknown", gitSha, sizeof(gitSha));
    char dirty[8];
    GetEnvOr("ACCMOD_GIT_DIRTY", "0", dirty, sizeof(dirty));
    LogFormat("ACCMOD_BUILD layer git=%s dirty=%s built=%s phase=%s run_id=%s scenario=%s adhoc=%d",
        gitSha, dirty, __DATE__ " " __TIME__, g_phase, g_runId, g_scenario,
        g_runIdSynthesized ? 1 : 0);
}

void EmitToggles(int useGpuRasterizer, int dirtyFlag, int swapW, int swapH, int mapDiscard) {
    if (!g_init) Init();
    if (!g_init) return;
    g_tUseGpu = useGpuRasterizer;
    g_tDirtyFlag = dirtyFlag;
    g_tSwapW = swapW;
    g_tSwapH = swapH;
    g_tMapDiscard = mapDiscard;
    LogFormat("ACCMOD_TOGGLES useGpuRasterizer=%d dirtyFlag=%d swapW=%d swapH=%d mapDiscard=%d",
        useGpuRasterizer, dirtyFlag, swapW, swapH, mapDiscard);
}

void EmitState(double circles, double quadDistance, double quadTanHalfFov,
               double quadAspect, int useGpuRasterizer, double dirtyHitRatio) {
    if (!g_init) return;
    LogFormat("ACCMOD_STATE source=layer frame=%llu circles=%.0f quadDist=%.3f tanHalfFov=%.4f aspect=%.4f useGpu=%d dirtyHitRatio=%.3f swapW=%d swapH=%d",
        (unsigned long long)g_frameCounter, circles, quadDistance, quadTanHalfFov, quadAspect,
        useGpuRasterizer, dirtyHitRatio, g_tSwapW, g_tSwapH);
}

ScopedTimer::ScopedTimer(Key k) : key_(k), start_(Now()) {}
ScopedTimer::~ScopedTimer() { RecordDuration(key_, start_); }

} // namespace perf
