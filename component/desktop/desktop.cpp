#include "./desktop.h"


uint32_t Desktop::colorAt(Point p, int width, int height) const {
    if (p.y > height - 35) {
        uint32_t alpha = background_color & 0xFF000000;
        uint32_t r = (background_color >> 16) & 0xFF;
        uint32_t g = (background_color >> 8) & 0xFF;
        uint32_t b = background_color & 0xFF;

        r = (r > 0x55) ? (r - 0x55) : 0;
        g = (g > 0x55) ? (g - 0x55) : 0;
        b = (b > 0x55) ? (b - 0x55) : 0;

        return alpha | (r << 16) | (g << 8) | b;
    }
    return background_color;
}