#include "component.h"

void Component::move(Point move) {
    x.x += move.x;
    x.y += move.y;
    y.x += move.x;
    y.y += move.y;
}