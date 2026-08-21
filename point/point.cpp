#include "point.h"

Point operator+(const Point& a, const Point& b) {
    return Point(a.x + b.x, a.y + b.y);
}

Point operator+(const Point& a, const int& b) {
    return Point(a.x + b, a.y + b);
}

Point operator+(const int& a, const Point& b) {
    return Point(a + b.x, a + b.y);
}

Point operator-(const Point& a) {
    return Point(-a.x, -a.y);
}