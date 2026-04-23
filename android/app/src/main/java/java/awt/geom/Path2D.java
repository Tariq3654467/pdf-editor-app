package java.awt.geom;

import java.awt.Shape;
import java.awt.Rectangle;
import java.awt.geom.Point2D;
import java.util.ArrayList;
import java.util.List;

/**
 * Minimal AWT Path2D stub for Android compatibility with PDFBox
 * Represents a geometric path constructed from straight lines, quadratic curves, and cubic curves
 */
public abstract class Path2D implements Shape, Cloneable {
    
    public static final int WIND_EVEN_ODD = 0;
    public static final int WIND_NON_ZERO = 1;
    
    protected int windingRule;
    protected List<Segment> segments;
    
    protected Path2D() {
        this(WIND_NON_ZERO);
    }
    
    protected Path2D(int rule) {
        this.windingRule = rule;
        this.segments = new ArrayList<>();
    }
    
    protected Path2D(int rule, int initialCapacity) {
        this.windingRule = rule;
        this.segments = new ArrayList<>(initialCapacity);
    }
    
    protected Path2D(Shape s) {
        this();
        if (s != null) {
            append(s, false);
        }
    }
    
    protected Path2D(Shape s, AffineTransform at) {
        this();
        if (s != null) {
            append(s, at);
        }
    }
    
    public abstract void moveTo(double x, double y);
    public abstract void lineTo(double x, double y);
    public abstract void quadTo(double x1, double y1, double x2, double y2);
    public abstract void curveTo(double x1, double y1, double x2, double y2, double x3, double y3);
    public abstract void closePath();
    
    public void append(Shape s, boolean connect) {
        if (s instanceof Path2D) {
            Path2D p2d = (Path2D) s;
            // Copy segments
            if (connect && !segments.isEmpty()) {
                // Connect paths
            }
            segments.addAll(p2d.segments);
        }
    }
    
    public void append(PathIterator pi, boolean connect) {
        // Stub implementation
    }
    
    public void append(Shape s, AffineTransform at) {
        // Stub implementation
    }
    
    public void append(PathIterator pi, AffineTransform at) {
        // Stub implementation
    }
    
    public void transform(AffineTransform at) {
        // Stub implementation
    }
    
    public void reset() {
        segments.clear();
    }
    
    public int getWindingRule() {
        return windingRule;
    }
    
    public void setWindingRule(int rule) {
        this.windingRule = rule;
    }
    
    @Override
    public Rectangle getBounds() {
        Rectangle2D bounds2D = getBounds2D();
        return new Rectangle((int)bounds2D.getX(), (int)bounds2D.getY(), 
                           (int)bounds2D.getWidth(), (int)bounds2D.getHeight());
    }
    
    @Override
    public Rectangle2D getBounds2D() {
        if (segments.isEmpty()) {
            return new Rectangle2D.Double();
        }
        double minX = java.lang.Double.MAX_VALUE;
        double minY = java.lang.Double.MAX_VALUE;
        double maxX = java.lang.Double.MIN_VALUE;
        double maxY = java.lang.Double.MIN_VALUE;
        
        for (Segment seg : segments) {
            minX = Math.min(minX, seg.minX);
            minY = Math.min(minY, seg.minY);
            maxX = Math.max(maxX, seg.maxX);
            maxY = Math.max(maxY, seg.maxY);
        }
        
        return new Rectangle2D.Double(minX, minY, maxX - minX, maxY - minY);
    }
    
    @Override
    public boolean contains(double x, double y) {
        // Stub - simple bounds check
        Rectangle2D bounds = getBounds2D();
        return bounds.contains(x, y);
    }
    
    @Override
    public boolean contains(Point2D p) {
        return contains(p.getX(), p.getY());
    }
    
    @Override
    public boolean contains(double x, double y, double w, double h) {
        Rectangle2D bounds = getBounds2D();
        return bounds.contains(x, y, w, h);
    }
    
    @Override
    public boolean contains(Rectangle2D r) {
        return contains(r.getX(), r.getY(), r.getWidth(), r.getHeight());
    }
    
    @Override
    public boolean intersects(double x, double y, double w, double h) {
        Rectangle2D bounds = getBounds2D();
        return bounds.intersects(x, y, w, h);
    }
    
    @Override
    public boolean intersects(Rectangle2D r) {
        return intersects(r.getX(), r.getY(), r.getWidth(), r.getHeight());
    }
    
    @Override
    public PathIterator getPathIterator(AffineTransform at) {
        return new PathIteratorImpl(at);
    }
    
    @Override
    public PathIterator getPathIterator(AffineTransform at, double flatness) {
        return getPathIterator(at);
    }
    
    @Override
    public Object clone() {
        try {
            Path2D p = (Path2D) super.clone();
            p.segments = new ArrayList<>(this.segments);
            return p;
        } catch (CloneNotSupportedException e) {
            throw new InternalError();
        }
    }
    
    /**
     * Double precision implementation
     */
    public static class Double extends Path2D {
        public Double() {
            super();
        }
        
        public Double(int rule) {
            super(rule);
        }
        
        public Double(int rule, int initialCapacity) {
            super(rule, initialCapacity);
        }
        
        public Double(Shape s) {
            super(s);
        }
        
        public Double(Shape s, AffineTransform at) {
            super(s, at);
        }
        
        @Override
        public void moveTo(double x, double y) {
            segments.add(new MoveToSegment(x, y));
        }
        
        @Override
        public void lineTo(double x, double y) {
            segments.add(new LineToSegment(x, y));
        }
        
        @Override
        public void quadTo(double x1, double y1, double x2, double y2) {
            segments.add(new QuadToSegment(x1, y1, x2, y2));
        }
        
        @Override
        public void curveTo(double x1, double y1, double x2, double y2, double x3, double y3) {
            segments.add(new CurveToSegment(x1, y1, x2, y2, x3, y3));
        }
        
        @Override
        public void closePath() {
            segments.add(new ClosePathSegment());
        }
    }
    
    /**
     * Float precision implementation
     */
    public static class Float extends Path2D {
        public Float() {
            super();
        }
        
        public Float(int rule) {
            super(rule);
        }
        
        public Float(int rule, int initialCapacity) {
            super(rule, initialCapacity);
        }
        
        public Float(Shape s) {
            super(s);
        }
        
        public Float(Shape s, AffineTransform at) {
            super(s, at);
        }
        
        @Override
        public void moveTo(double x, double y) {
            segments.add(new MoveToSegment(x, y));
        }
        
        // Float overloads for Path2D.Float - required by PDFBox
        public void moveTo(float x, float y) {
            moveTo((double)x, (double)y);
        }
        
        @Override
        public void lineTo(double x, double y) {
            segments.add(new LineToSegment(x, y));
        }
        
        // Float overloads for Path2D.Float
        public void lineTo(float x, float y) {
            lineTo((double)x, (double)y);
        }
        
        @Override
        public void quadTo(double x1, double y1, double x2, double y2) {
            segments.add(new QuadToSegment(x1, y1, x2, y2));
        }
        
        // Float overloads for Path2D.Float
        public void quadTo(float x1, float y1, float x2, float y2) {
            quadTo((double)x1, (double)y1, (double)x2, (double)y2);
        }
        
        @Override
        public void curveTo(double x1, double y1, double x2, double y2, double x3, double y3) {
            segments.add(new CurveToSegment(x1, y1, x2, y2, x3, y3));
        }
        
        // Float overloads for Path2D.Float
        public void curveTo(float x1, float y1, float x2, float y2, float x3, float y3) {
            curveTo((double)x1, (double)y1, (double)x2, (double)y2, (double)x3, (double)y3);
        }
        
        @Override
        public void closePath() {
            segments.add(new ClosePathSegment());
        }
    }
    
    // Segment types
    protected abstract static class Segment {
        double minX, minY, maxX, maxY;
    }
    
    protected static class MoveToSegment extends Segment {
        double x, y;
        MoveToSegment(double x, double y) {
            this.x = x;
            this.y = y;
            this.minX = this.maxX = x;
            this.minY = this.maxY = y;
        }
    }
    
    protected static class LineToSegment extends Segment {
        double x, y;
        LineToSegment(double x, double y) {
            this.x = x;
            this.y = y;
            this.minX = this.maxX = x;
            this.minY = this.maxY = y;
        }
    }
    
    protected static class QuadToSegment extends Segment {
        double x1, y1, x2, y2;
        QuadToSegment(double x1, double y1, double x2, double y2) {
            this.x1 = x1;
            this.y1 = y1;
            this.x2 = x2;
            this.y2 = y2;
            this.minX = Math.min(x1, x2);
            this.minY = Math.min(y1, y2);
            this.maxX = Math.max(x1, x2);
            this.maxY = Math.max(y1, y2);
        }
    }
    
    protected static class CurveToSegment extends Segment {
        double x1, y1, x2, y2, x3, y3;
        CurveToSegment(double x1, double y1, double x2, double y2, double x3, double y3) {
            this.x1 = x1;
            this.y1 = y1;
            this.x2 = x2;
            this.y2 = y2;
            this.x3 = x3;
            this.y3 = y3;
            this.minX = Math.min(Math.min(x1, x2), x3);
            this.minY = Math.min(Math.min(y1, y2), y3);
            this.maxX = Math.max(Math.max(x1, x2), x3);
            this.maxY = Math.max(Math.max(y1, y2), y3);
        }
    }
    
    protected static class ClosePathSegment extends Segment {
        ClosePathSegment() {
            // No bounds
        }
    }
    
    // PathIterator implementation
    private class PathIteratorImpl implements PathIterator {
        private AffineTransform transform;
        private int index;
        
        PathIteratorImpl(AffineTransform at) {
            this.transform = at;
            this.index = 0;
        }
        
        @Override
        public int getWindingRule() {
            return Path2D.this.windingRule;
        }
        
        @Override
        public boolean isDone() {
            return index >= segments.size();
        }
        
        @Override
        public void next() {
            index++;
        }
        
        @Override
        public int currentSegment(float[] coords) {
            if (isDone()) {
                throw new java.util.NoSuchElementException();
            }
            Segment seg = segments.get(index);
            // Stub implementation
            return SEG_MOVETO;
        }
        
        @Override
        public int currentSegment(double[] coords) {
            if (isDone()) {
                throw new java.util.NoSuchElementException();
            }
            Segment seg = segments.get(index);
            // Stub implementation
            return SEG_MOVETO;
        }
    }
}

