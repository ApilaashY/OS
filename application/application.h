#pragma once

#include "../component/screen/screen.h"
#include "../point/point.h"
#include <vector>

class Graphics;

class Application {
    std::vector<Screen*> screens;
    Screen* activeScreen;
    ScreenArea screenArea;
    
public:
    Application() : activeScreen(nullptr), screenArea({{0, 0}, {0, 0}}) {}
    void addScreen(Screen* screen);
    void render(Graphics* graphics, Point topLeft, Point bottomRight);
    void updateResolution();
};
