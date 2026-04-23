package java.awt;

/**
 * Minimal AWT Point stub for Android compatibility with PDFBox
 * This provides the Point class that PDFBox 3.0.1 references but isn't available on Android
 */
public class Point {
    public int x;
    public int y;
    
    public Point() {
        this(0, 0);
    }
    
    public Point(int x, int y) {
        this.x = x;
        this.y = y;
    }
    
    public Point(Point p) {
        this(p.x, p.y);
    }
    
    public void setLocation(int x, int y) {
        this.x = x;
        this.y = y;
    }
    
    public void setLocation(Point p) {
        this.x = p.x;
        this.y = p.y;
    }
    
    public void setLocation(double x, double y) {
        this.x = (int) x;
        this.y = (int) y;
    }
    
    public double getX() {
        return x;
    }
    
    public double getY() {
        return y;
    }
    
    @Override
    public String toString() {
        return "Point[x=" + x + ",y=" + y + "]";
    }
    
    @Override
    public boolean equals(Object obj) {
        if (obj instanceof Point) {
            Point p = (Point) obj;
            return x == p.x && y == p.y;
        }
        return false;
    }
    
    @Override
    public int hashCode() {
        return x * 31 + y;
    }
}

