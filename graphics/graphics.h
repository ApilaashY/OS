#pragma once

#include "../component/component.h"
#include "../window/window.h"
#include <cstdint>
#include <vector>
#include <drm/drm_mode.h>

struct Buf {
    uint32_t handle;
    uint32_t pitch;
    uint64_t size;
    uint32_t fb_id;
    void* pixels;
};

class Graphics {
public:
    Graphics(uint32_t width = 800, uint32_t height = 600, uint32_t background_color = 0xFF000000);
    void animate();
    void clearBuffer();
    void copyBuffer();
    void drawRectBuffer(Point x, Point y, uint32_t color);
    void drawRectBuffer(ScreenArea area, uint32_t color);
    void drawScreen();
    uint32_t width() const;
    uint32_t height() const;

private:
    std::vector<uint32_t> connector_ids;
    std::vector<uint32_t> crtc_ids;
    Buf bufs[2] = {};
    drm_mode_modeinfo mode{};
    int fd = -1;
    uint32_t crtc_id = 0;
    int back = 1;
    uint32_t background_color;
};