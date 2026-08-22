class Point {
    public:
    int x;
    int y;
    Point(int x, int y): x(x), y(y) {}
};

Point operator+(const Point& a, const Point& b);
Point operator+(const Point& a, const int& b);
Point operator*(const Point& a, const int& b);
Point operator-(const Point& a);
Point operator-(const Point& a, const Point& b);
Point operator-(const Point& a, const int& b);
Point operator-(const int& a, const Point& b);

class ScreenArea {
    public:
    Point topLeft;
    Point bottomRight;

    ScreenArea(Point topLeft, Point bottomRight): topLeft(topLeft), bottomRight(bottomRight) {}
    bool overlaps(const ScreenArea& other) const;
};
