#include "./application.h"
#include "../graphics/graphics.h"

void Application::addScreen(Screen* screen) {
    screens.push_back(screen);

    // if there is no active screen, set the newly added screen as the active screen
    if (activeScreen == nullptr) {
        activeScreen = screen;
    }
}

void Application::render(Graphics* graphics, Point topLeft, Point bottomRight) {
    if (activeScreen) {
        activeScreen->render(graphics, topLeft, bottomRight);
    } else {
        graphics->drawRectBuffer(topLeft, bottomRight, 0x00FFFFFF); // Example color for empty screen
    }
}

void Application::updateResolution() {
}