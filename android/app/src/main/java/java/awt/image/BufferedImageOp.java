package java.awt.image;

import java.awt.geom.Point2D;
import java.awt.geom.Rectangle2D;

/**
 * Minimal AWT BufferedImageOp interface stub for Android compatibility with PDFBox
 */
public interface BufferedImageOp {
    BufferedImage filter(BufferedImage src, BufferedImage dst);
    Rectangle2D getBounds2D(BufferedImage src);
    BufferedImage createCompatibleDestImage(BufferedImage src, ColorModel destCM);
    Point2D getPoint2D(Point2D srcPt, Point2D dstPt);
    java.awt.RenderingHints getRenderingHints();
}

