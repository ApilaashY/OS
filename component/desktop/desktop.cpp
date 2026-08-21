#include "./desktop.h"


uint32_t Desktop::colorAt(Point p, int width, int height) const {
    uint32_t color = background_color;

    for (const auto& component : components) {
        uint32_t componentColor = component->colorAt(p, width, height);
        if (componentColor != 0) {
            color = componentColor;
        }
    }

    if (p.x >= mouse.x-10 && p.x <= mouse.x+10 && p.y >= mouse.y-10 && p.y <= mouse.y+10) {
        return 0xFF0000FF; // Blue color for the mouse cursor
    }

    if (p.y > height - 35) {
        uint32_t alpha = color & 0xFF000000;
        uint32_t r = (color >> 16) & 0xFF;
        uint32_t g = (color >> 8) & 0xFF;
        uint32_t b = color & 0xFF;

        r = (r > 0x55) ? (r - 0x55) : 0;
        g = (g > 0x55) ? (g - 0x55) : 0;
        b = (b > 0x55) ? (b - 0x55) : 0;

        return alpha | (r << 16) | (g << 8) | b;
    }
    return color;
}

Component* Desktop::addComponent(Component* component) {
    components.push_back(component);
    return component;
}

void Desktop::drawMouse(Point p) {
    mouse = p;
}
