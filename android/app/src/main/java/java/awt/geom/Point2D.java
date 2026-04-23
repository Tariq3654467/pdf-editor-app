package java.awt.geom;

/**
 * Minimal AWT Point2D stub for Android compatibility with PDFBox
 */
public abstract class Point2D {
    public abstract double getX();
    public abstract double getY();
    public abstract void setLocation(double x, double y);
    
    public static class Double extends Point2D {
        public double x;
        public double y;
        
        public Double() {
            this(0.0, 0.0);
        }
        
        public Double(double x, double y) {
            this.x = x;
            this.y = y;
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
        public void setLocation(double x, double y) {
            this.x = x;
            this.y = y;
        }
    }
    
    public static class Float extends Point2D {
        public float x;
        public float y;
        
        public Float() {
            this(0.0f, 0.0f);
        }
        
        public Float(float x, float y) {
            this.x = x;
            this.y = y;
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
        public void setLocation(double x, double y) {
            this.x = (float) x;
            this.y = (float) y;
        }
    }
}

