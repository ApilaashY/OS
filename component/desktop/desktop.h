#pragma once

#include <vector>
#include "../component.h"

class Desktop: public Component {
    uint32_t background_color;
    std::vector<Component*> components;
    Point mouse = {-100, -100};
public:
    Desktop(Point x, Point y, uint32_t background_color): Component(x, y), background_color(background_color) {}
    uint32_t colorAt(Point p, int width, int height) const override;
    Component* addComponent(Component* component);
    void drawMouse(Point p);
};