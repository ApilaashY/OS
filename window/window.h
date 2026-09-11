#pragma once

#include "../point/point.h"

class Application;
class Graphics;

class Window {
    Point topLeft;
    Point bottomRight;
    Application* application;
    static const int BARHEIGHT = 30; // pixel height of upper window bar

    public:
    Window(Point topLeft, Point bottomRight, Application* application): topLeft(topLeft), bottomRight(bottomRight), application(application) {}
    Point getTopLeft() const { return topLeft; }
    Point getBottomRight() const { return bottomRight; }
    ScreenArea getScreenArea() const;
    void render(Graphics* graphics);
};
