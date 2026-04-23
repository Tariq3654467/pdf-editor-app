package java.awt.image;

import java.awt.Graphics;
import java.awt.Image;
import java.awt.Point;

/**
 * Minimal AWT BufferedImage stub for Android compatibility with PDFBox
 */
public class BufferedImage extends Image {
    protected int width;
    protected int height;
    protected int imageType;
    protected WritableRaster raster;
    protected ColorModel colorModel;
    
    public BufferedImage(int width, int height, int imageType) {
        this.width = width;
        this.height = height;
        this.imageType = imageType;
    }
    
    public BufferedImage(ColorModel cm, WritableRaster raster, boolean isRasterPremultiplied, java.util.Hashtable<?, ?> properties) {
        this.colorModel = cm;
        this.raster = raster;
        if (raster != null) {
            this.width = raster.getWidth();
            this.height = raster.getHeight();
        }
    }
    
    public int getWidth() {
        return width;
    }
    
    public int getHeight() {
        return height;
    }
    
    public int getType() {
        return imageType;
    }
    
    public WritableRaster getRaster() {
        return raster;
    }
    
    public ColorModel getColorModel() {
        return colorModel;
    }
    
    public Graphics getGraphics() {
        // Stub - return null
        // Note: This method doesn't exist in Image superclass, so no @Override
        return null;
    }
    
    /**
     * Set the raster data for this BufferedImage
     * Required by PDFBox 3.0.1
     */
    public void setData(Raster raster) {
        // Stub - store the raster
        if (raster instanceof WritableRaster) {
            this.raster = (WritableRaster) raster;
            if (raster != null) {
                this.width = raster.getWidth();
                this.height = raster.getHeight();
            }
        }
    }
}

