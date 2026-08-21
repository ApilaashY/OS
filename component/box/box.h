#include "../component.h"


class Box : public Component {
    uint32_t color;
    public:
        Box(Point x, Point y, uint32_t color): Component(x, y), color(color) {}
        uint32_t colorAt(Point p, int width, int height) const override {
            if (p.x >= x.x && p.x <= y.x && p.y >= x.y && p.y <= y.y) {
                return color;
            }
            return 0; // Transparent
        }
};
