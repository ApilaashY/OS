#include "./window.h"
#include "../application/application.h"
#include "../graphics/graphics.h"

void Window::render(Graphics* graphics) {
    Point barBottomRight = {bottomRight.x, topLeft.y + BARHEIGHT};
    graphics->drawRectBuffer(topLeft, barBottomRight, 0xFF0000FF); // Example color for the bar

    // Draw the application in the rest of the window
    Point appTopLeft = {topLeft.x, topLeft.y + BARHEIGHT};
    application->render(graphics, appTopLeft, bottomRight);
}


void Window::onClick(MouseClickEvent event) {
    // Handle click event
}

void Window::onDrag(MouseDragEvent event) {
    if (event.startPosition.x >= topLeft.x && event.startPosition.x <= bottomRight.x &&
        event.startPosition.y >= topLeft.y && event.startPosition.y <= topLeft.y + BARHEIGHT) {
        // Handle drag event within the top window bar
        topLeft.x += event.endPosition.x - event.startPosition.x;
        topLeft.y += event.endPosition.y - event.startPosition.y;
        bottomRight.x += event.endPosition.x - event.startPosition.x;
        bottomRight.y += event.endPosition.y - event.startPosition.y;
        // render(graphics);
    }
}
