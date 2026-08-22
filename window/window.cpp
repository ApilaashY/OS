#include "./window.h"

const uint32_t windowBarHeight = 40;

ScreenArea Window::getScreenArea() const {
    return ScreenArea(topLeft, bottomRight);
}
