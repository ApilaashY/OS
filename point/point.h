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

