#pragma once
#include <cstdint>
#include "../point/point.h"

struct MouseClickEvent {
    Point position;
};

struct MouseDragEvent {
    Point startPosition;
    Point endPosition;
};

class Component {
protected:
    Point topLeft;
    Point bottomRight;
public:
    Component(Point topLeft, Point bottomRight): topLeft(topLeft), bottomRight(bottomRight) {}
    virtual ~Component() = default;
    void move(Point move);
    ScreenArea getScreenArea() const;
    virtual void onClick(MouseClickEvent event) = 0;
    virtual void onDrag(MouseDragEvent event) = 0;
};
