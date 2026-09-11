#include "./window.h"
#include "../application/application.h"
#include "../graphics/graphics.h"

ScreenArea Window::getScreenArea() const {
    return ScreenArea(topLeft, bottomRight);
}

void Window::render(Graphics* graphics) {
    Point barBottomRight = {bottomRight.x, topLeft.y + BARHEIGHT};
    graphics->drawRectBuffer(topLeft, barBottomRight, 0xFF0000FF); // Example color for the bar

    // Draw the application in the rest of the window
    Point appTopLeft = {topLeft.x, topLeft.y + BARHEIGHT};
    application->render(graphics, appTopLeft, bottomRight);
}