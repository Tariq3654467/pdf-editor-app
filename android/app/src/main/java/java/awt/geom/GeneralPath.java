package java.awt.geom;

import java.awt.Shape;

/**
 * Minimal AWT GeneralPath stub for Android compatibility with PDFBox
 * GeneralPath is a concrete implementation of Path2D using float precision
 */
public final class GeneralPath extends Path2D.Float {
    
    public GeneralPath() {
        super();
    }
    
    public GeneralPath(int rule) {
        super(rule);
    }
    
    public GeneralPath(int rule, int initialCapacity) {
        super(rule, initialCapacity);
    }
    
    public GeneralPath(Shape s) {
        super(s);
    }
    
    public GeneralPath(Shape s, AffineTransform at) {
        super(s, at);
    }
}

