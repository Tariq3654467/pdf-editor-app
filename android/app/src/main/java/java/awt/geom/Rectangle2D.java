package java.awt.geom;

import java.awt.Rectangle;

/**
 * Minimal AWT Rectangle2D stub for Android compatibility with PDFBox
 */
public abstract class Rectangle2D {
    public abstract double getX();
    public abstract double getY();
    public abstract double getWidth();
    public abstract double getHeight();
    
    public static class Double extends Rectangle2D {
        public double x;
        public double y;
        public double width;
        public double height;
        
        public Double() {
            this(0.0, 0.0, 0.0, 0.0);
        }
        
        public Double(double x, double y, double width, double height) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
        }
        
        @Override
        public double getX() {
            return x;
        }
        
        @Override
        public double getY() {
            return y;
        }
        
        @Override
        public double getWidth() {
            return width;
        }
        
        @Override
        public double getHeight() {
            return height;
        }
    }
    
    public static class Float extends Rectangle2D {
        public float x;
        public float y;
        public float width;
        public float height;
        
        public Float() {
            this(0.0f, 0.0f, 0.0f, 0.0f);
        }
        
        public Float(float x, float y, float width, float height) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
        }
        
        @Override
        public double getX() {
            return x;
        }
        
        @Override
        public double getY() {
            return y;
        }
        
        @Override
        public double getWidth() {
            return width;
        }
        
        @Override
        public double getHeight() {
            return height;
        }
    }
    
    // Common methods for all Rectangle2D implementations
    public Rectangle getBounds() {
        return new Rectangle((int)getX(), (int)getY(), (int)getWidth(), (int)getHeight());
    }
    
    public boolean contains(double x, double y) {
        return x >= getX() && x < getX() + getWidth() && 
               y >= getY() && y < getY() + getHeight();
    }
    
    public boolean contains(double x, double y, double w, double h) {
        return contains(x, y) && contains(x + w, y) && 
               contains(x, y + h) && contains(x + w, y + h);
    }
    
    public boolean intersects(double x, double y, double w, double h) {
        return !(x + w < getX() || x > getX() + getWidth() ||
                 y + h < getY() || y > getY() + getHeight());
    }
}

