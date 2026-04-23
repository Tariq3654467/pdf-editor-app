package java.awt.image;

import java.awt.geom.Point2D;
import java.awt.geom.Rectangle2D;

/**
 * Minimal AWT RasterOp interface stub for Android compatibility with PDFBox
 */
public interface RasterOp {
    WritableRaster filter(Raster src, WritableRaster dst);
    Rectangle2D getBounds2D(Raster src);
    WritableRaster createCompatibleDestRaster(Raster src);
    Point2D getPoint2D(Point2D srcPt, Point2D dstPt);
    java.awt.RenderingHints getRenderingHints();
}

