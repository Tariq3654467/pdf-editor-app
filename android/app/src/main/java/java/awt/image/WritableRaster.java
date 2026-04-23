package java.awt.image;

import java.awt.Point;

/**
 * Minimal AWT WritableRaster stub for Android compatibility with PDFBox
 */
public class WritableRaster extends Raster {
    
    protected WritableRaster(SampleModel sampleModel, DataBuffer dataBuffer, Point origin) {
        super(sampleModel, dataBuffer, origin);
    }
    
    /**
     * Set pixel data (stub implementation)
     */
    public void setDataElements(int x, int y, Object inData) {
        // Stub - not actually used by PDFBox in our use case
    }
    
    /**
     * Set pixel data for a region (stub implementation)
     */
    public void setRect(int dx, int dy, Raster srcRaster) {
        // Stub - not actually used by PDFBox in our use case
    }
}

