#pragma once

#include "../point/point.h"
#include "../component/component.h"

class Application;
class Graphics;

class Window : public Component {
    Application* application;
    static const int BARHEIGHT = 30; // pixel height of upper window bar

    public:
    Window(Point topLeft, Point bottomRight, Application* application): Component(topLeft, bottomRight), application(application) {}
    void render(Graphics* graphics);
    virtual void onClick(MouseClickEvent event);
    virtual void onDrag(MouseDragEvent event);
};
