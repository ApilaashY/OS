#include "../component.h"


class Box : public Component {
    uint32_t color;
    public:
        Box(Point x, Point y, uint32_t color): Component(x, y), color(color) {}
};
