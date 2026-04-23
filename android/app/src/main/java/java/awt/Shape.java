package java.awt;

import java.awt.geom.AffineTransform;
import java.awt.geom.PathIterator;
import java.awt.geom.Point2D;
import java.awt.geom.Rectangle2D;

/**
 * Minimal AWT Shape interface stub for Android compatibility with PDFBox
 */
public interface Shape {
    Rectangle getBounds();
    Rectangle2D getBounds2D();
    boolean contains(double x, double y);
    boolean contains(Point2D p);
    boolean contains(double x, double y, double w, double h);
    boolean contains(Rectangle2D r);
    boolean intersects(double x, double y, double w, double h);
    boolean intersects(Rectangle2D r);
    PathIterator getPathIterator(AffineTransform at);
    PathIterator getPathIterator(AffineTransform at, double flatness);
}

