#include "./screen.h"
#include "../../graphics/graphics.h"
#include "../../point/point.h"

void Screen::render(Graphics* graphics, Point topLeft, Point bottomRight) {
    graphics->drawRectBuffer(topLeft, bottomRight, 0xFFFFFFFF); // Example color for the screen
}
