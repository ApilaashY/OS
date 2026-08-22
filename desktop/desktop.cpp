#include "./desktop.h"
#include <iostream>

Window* Desktop::addWindow(Window* window) {
    this->window.push_back(window);

    graphics->copyBuffer();
    drawWindow(window);
    graphics->drawScreen();

    return window;
}

void Desktop::drawWindow(Window* window) {
    // Logic to draw a window
    Point topLeft = window->getTopLeft();
    Point bottomRight = window->getBottomRight();
    for (int i = topLeft.y; i < bottomRight.y; i++) {
        for (int j = topLeft.x; j < bottomRight.x; j++) {
            Point p{j, i};
            graphics->drawRectBuffer(p, p+1, 0xFFFFFFFF); // Example color
        }
    }
}


void Desktop::drawMouse(Point p) {
    const int mouseRadius = 10;

    // Clone the currently displayed buffer into the back buffer so partial
    // updates don't leave stale pixels behind the double-buffer flip.
    graphics->copyBuffer();

    // Fill in the old spot with the background to allow the window to fill in correctly if needed
    graphics->drawRectBuffer(ScreenArea(mouse-mouseRadius, mouse+mouseRadius), background_color);

    // Erase the cursor at its OLD position by repainting any window it covered.
    // Do it in reverse order to make sure the topmost components are drawn last and appear above the others.
    const ScreenArea oldMouseArea = ScreenArea(mouse-mouseRadius, mouse+mouseRadius);
    for (auto it = window.rbegin(); it != window.rend(); ++it) {
        const auto& win = *it;
        if (win->getScreenArea().overlaps(oldMouseArea)) {
            drawWindow(win);
        }
    }

    mouse = p;

    // Paint the cursor at the NEW position (using a freshly-computed rect).
    const ScreenArea newMouseArea = ScreenArea(mouse-mouseRadius, mouse+mouseRadius);
    graphics->drawRectBuffer(newMouseArea, 0xFF0000FF);
    graphics->drawScreen();
}
