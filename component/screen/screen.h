#pragma once
#include "../../graphics/graphics.h"
#include "../../point/point.h"
class Screen {
    
public:
    Screen() {}
    void render(Graphics* graphics, Point topLeft, Point bottomRight);
};