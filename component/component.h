#pragma once
#include <cstdint>
#include "../point/point.h"

class Component {
    Point x;
    Point y;
public:
    Component(Point x, Point y): x(x), y(y) {}
    virtual ~Component() = default;
    virtual uint32_t colorAt(Point p, int width, int height) const = 0;
};