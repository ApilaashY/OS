#include "./desktop.h"
#include "../window/window.h"
#include <iostream>

Window* Desktop::addWindow(Window* window) {
    windows.push_back(window);

    graphics->copyBuffer();
    window->render(graphics);
    graphics->drawScreen();

    return window;
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
    for (auto it = windows.rbegin(); it != windows.rend(); ++it) {
        const auto& win = *it;
        if (win->getScreenArea().overlaps(oldMouseArea)) {
            win->render(graphics);
        }
    }

    mouse = p;

    // Paint the cursor at the NEW position (using a freshly-computed rect).
    const ScreenArea newMouseArea = ScreenArea(mouse-mouseRadius, mouse+mouseRadius);
    graphics->drawRectBuffer(newMouseArea, 0xFF0000FF);
    graphics->drawScreen();
}

void Desktop::click(MouseClickEvent event) {
    // Propagate the click event to the topmost window that contains the click position
    for (auto it = windows.rbegin(); it != windows.rend(); ++it) {
        const auto& win = *it;
        if (win->getScreenArea().contains(event.position)) {
            win->onClick(event);
            break;
        }
    }
}
void Desktop::drag(MouseDragEvent event) {
    // Propagate the drag event to the topmost window that contains the drag start position
    for (auto it = windows.rbegin(); it != windows.rend(); ++it) {
        const auto& win = *it;
        if (win->getScreenArea().contains(event.startPosition)) {
            win->onDrag(event);
            break;
        }
    }
}
