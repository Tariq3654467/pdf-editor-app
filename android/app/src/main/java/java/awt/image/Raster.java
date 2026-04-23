package java.awt.image;

import java.awt.Point;

/**
 * Minimal AWT Raster stub for Android compatibility with PDFBox
 */
public class Raster {
    protected DataBuffer dataBuffer;
    protected SampleModel sampleModel;
    protected int width;
    protected int height;
    protected int minX;
    protected int minY;
    protected int numBands;
    protected int numDataElements;
    
    protected Raster(SampleModel sampleModel, DataBuffer dataBuffer, Point origin) {
        this.sampleModel = sampleModel;
        this.dataBuffer = dataBuffer;
        if (origin != null) {
            this.minX = origin.x;
            this.minY = origin.y;
        }
        this.width = sampleModel != null ? sampleModel.getWidth() : 0;
        this.height = sampleModel != null ? sampleModel.getHeight() : 0;
        this.numBands = sampleModel != null ? sampleModel.getNumBands() : 0;
        this.numDataElements = sampleModel != null ? sampleModel.getNumDataElements() : 0;
    }
    
    public int getWidth() {
        return width;
    }
    
    public int getHeight() {
        return height;
    }
    
    public int getMinX() {
        return minX;
    }
    
    public int getMinY() {
        return minY;
    }
    
    public int getNumBands() {
        return numBands;
    }
    
    public int getNumDataElements() {
        return numDataElements;
    }
    
    public DataBuffer getDataBuffer() {
        return dataBuffer;
    }
    
    public SampleModel getSampleModel() {
        return sampleModel;
    }
    
    /**
     * Static factory method for creating banded raster
     * Required by PDFBox 3.0.1
     */
    public static WritableRaster createBandedRaster(int dataType, int w, int h, int bands, Point location) {
        // Create a minimal writable raster
        // This is a stub - PDFBox uses this during initialization but may not actually use the result
        return new WritableRaster(null, null, location);
    }
    
    /**
     * Static factory method for creating banded raster (no location)
     */
    public static WritableRaster createBandedRaster(int dataType, int w, int h, int bands) {
        return createBandedRaster(dataType, w, h, bands, new Point(0, 0));
    }
}

