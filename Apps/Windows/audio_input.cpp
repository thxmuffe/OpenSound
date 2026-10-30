// WASAPI loopback input. PCM stays local; only meter summaries go to BEAM.
#define NOMINMAX
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <wrl/client.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;
static std::atomic<bool> running{true};
static void check(HRESULT hr) { if (FAILED(hr)) throw hr; }
static double db(double value) { return 20 * std::log10(std::max(value, 0.0000158489319)); }

static std::string json_string(const wchar_t* text) {
    int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
    std::string utf8(static_cast<size_t>(size), '\0'), result = "\"";
    WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8.data(), size, nullptr, nullptr);
    for (int i = 0; i < size - 1; ++i) {
        unsigned char c = static_cast<unsigned char>(utf8[i]);
        if (c == '"' || c == '\\') result += '\\';
        if (c < 32) { char escaped[7]; sprintf_s(escaped, "\\u%04x", c); result += escaped; }
        else result += static_cast<char>(c);
    }
    return result + '"';
}

static double sample(const BYTE* p, WORD bits, bool floating) {
    if (floating) { float value; std::memcpy(&value, p, 4); return std::isfinite(value) ? value : 0; }
    if (bits == 16) { short value; std::memcpy(&value, p, 2); return value / 32768.0; }
    if (bits == 24) {
        int value = p[0] | (p[1] << 8) | (p[2] << 16);
        if (value & 0x800000) value -= 0x1000000;
        return value / 8388608.0;
    }
    int value; std::memcpy(&value, p, 4); return value / 2147483648.0;
}

static void capture() {
    ComPtr<IMMDeviceEnumerator> devices;
    check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&devices)));
    ComPtr<IMMDevice> device;
    check(devices->GetDefaultAudioEndpoint(eRender, eMultimedia, &device));
    ComPtr<IPropertyStore> properties;
    check(device->OpenPropertyStore(STGM_READ, &properties));
    PROPVARIANT name; PropVariantInit(&name);
    check(properties->GetValue(PKEY_Device_FriendlyName, &name));
    std::string source = json_string(name.vt == VT_LPWSTR ? name.pwszVal : L"Windows default output");
    PropVariantClear(&name);
    ComPtr<IAudioClient> client;
    check(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client));
    WAVEFORMATEX* allocated = nullptr;
    check(client->GetMixFormat(&allocated));
    std::vector<BYTE> format(sizeof(WAVEFORMATEX) + allocated->cbSize);
    std::memcpy(format.data(), allocated, format.size()); CoTaskMemFree(allocated);
    auto* wave = reinterpret_cast<WAVEFORMATEX*>(format.data());
    bool floating = wave->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    bool pcm = wave->wFormatTag == WAVE_FORMAT_PCM;
    if (wave->wFormatTag == WAVE_FORMAT_EXTENSIBLE && wave->cbSize >= 22) {
        auto* extended = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(wave);
        floating = IsEqualGUID(extended->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
        pcm = IsEqualGUID(extended->SubFormat, KSDATAFORMAT_SUBTYPE_PCM);
    }
    if ((!floating || wave->wBitsPerSample != 32) &&
        (!pcm || (wave->wBitsPerSample != 16 && wave->wBitsPerSample != 24 && wave->wBitsPerSample != 32)))
        throw AUDCLNT_E_UNSUPPORTED_FORMAT;
    check(client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                            1000000, 0, wave, nullptr));
    ComPtr<IAudioCaptureClient> input;
    check(client->GetService(IID_PPV_ARGS(&input)));
    check(client->Start());
    unsigned long long framesSeen = 0, count = 0, discontinuities = 0;
    double peak = 0, squares = 0;
    ULONGLONG report = GetTickCount64();
    const WORD bytes = wave->wBitsPerSample / 8;
    while (running) {
        Sleep(10);
        UINT32 available = 0;
        check(input->GetNextPacketSize(&available));
        while (available) {
            BYTE* data = nullptr; UINT32 frames = 0; DWORD flags = 0;
            check(input->GetBuffer(&data, &frames, &flags, nullptr, nullptr));
            if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) ++discontinuities;
            for (UINT32 frame = 0; frame < frames; ++frame) {
                for (WORD channel = 0; channel < wave->nChannels; ++channel) {
                    double value = (flags & AUDCLNT_BUFFERFLAGS_SILENT) ? 0 :
                        sample(data + frame * wave->nBlockAlign + channel * bytes, wave->wBitsPerSample, floating);
                    peak = std::max(peak, std::abs(value)); squares += value * value; ++count;
                }
            }
            framesSeen += frames;
            check(input->ReleaseBuffer(frames));
            check(input->GetNextPacketSize(&available));
        }
        if (GetTickCount64() - report >= 100) {
            printf("{\"source\":%s,\"rate\":%lu,\"channels\":%u,\"peak_db\":%.2f,\"rms_db\":%.2f,"
                   "\"frames\":%llu,\"discontinuities\":%llu}\n", source.c_str(), wave->nSamplesPerSec,
                   wave->nChannels, db(peak), db(count ? std::sqrt(squares / static_cast<double>(count)) : 0),
                   framesSeen, discontinuities);
            fflush(stdout); peak = 0; squares = 0; count = 0; report = GetTickCount64();
        }
    }
    client->Stop();
}

int main() {
    // Closing the owning Erlang port closes stdin and ends the helper too.
    std::thread([] { while (getchar() != EOF) {} running = false; }).detach();
    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    try {
        check(init); capture(); CoUninitialize(); return 0;
    } catch (HRESULT hr) {
        printf("{\"error\":\"WASAPI input failed (0x%08lx). Check the default output, then stop/start input.\"}\n",
               static_cast<unsigned long>(hr));
        fflush(stdout); if (SUCCEEDED(init)) CoUninitialize(); return 1;
    }
}
