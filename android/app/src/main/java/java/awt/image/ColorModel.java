package java.awt.image;

/**
 * Minimal AWT ColorModel stub for Android compatibility with PDFBox
 */
public abstract class ColorModel {
    protected int pixel_bits;
    protected int transferType;
    
    protected ColorModel(int bits) {
        this.pixel_bits = bits;
    }
    
    public int getPixelSize() {
        return pixel_bits;
    }
    
    public int getTransferType() {
        return transferType;
    }
}

