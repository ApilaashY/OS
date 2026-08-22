#pragma once

#include <vector>
#include "../graphics/graphics.h"

class Desktop {
    uint32_t background_color;
    std::vector<Window*> window;
    Point mouse = {-100, -100};
    Graphics* graphics; 
    uint32_t width, height;

public:
    Desktop(int width, int height, uint32_t background_color, Graphics* graphics): width(width), height(height), background_color(background_color), graphics(graphics) {
        graphics->drawRectBuffer({0,0}, {width, height}, background_color);
        graphics->drawScreen();
    }
    Window* addWindow(Window* window);
    void drawMouse(Point p);
    void drawWindow(Window* window);
};