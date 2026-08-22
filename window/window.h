#pragma once

#include "../graphics/graphics.h"
#include "../application/application.h"

class Window {
    Point topLeft;
    Point bottomRight;
    Application application;

    public:
    Window(Point topLeft, Point bottomRight): topLeft(topLeft), bottomRight(bottomRight) {}
    Point getTopLeft() const { return topLeft; }
    Point getBottomRight() const { return bottomRight; }
    ScreenArea getScreenArea() const;
};
