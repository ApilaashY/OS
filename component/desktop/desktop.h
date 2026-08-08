#pragma once
#include "../component.h"

class Desktop: public Component {
    uint32_t background_color;
public:
    Desktop(Point x, Point y, uint32_t background_color): Component(x, y), background_color(background_color) {}
    uint32_t colorAt(Point p, int width, int height) const override;
};