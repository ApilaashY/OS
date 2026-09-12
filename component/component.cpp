#include "component.h"

void Component::move(Point move) {
    topLeft.x += move.x;
    topLeft.y += move.y;
    bottomRight.x += move.x;
    bottomRight.y += move.y;
}

ScreenArea Component::getScreenArea() const {
    return ScreenArea(topLeft, bottomRight);
}
