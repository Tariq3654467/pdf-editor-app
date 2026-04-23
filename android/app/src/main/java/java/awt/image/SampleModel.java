package java.awt.image;

/**
 * Minimal AWT SampleModel stub for Android compatibility with PDFBox
 */
public abstract class SampleModel {
    protected int width;
    protected int height;
    protected int numBands;
    protected int dataType;
    
    protected SampleModel(int dataType, int width, int height, int numBands) {
        this.dataType = dataType;
        this.width = width;
        this.height = height;
        this.numBands = numBands;
    }
    
    public int getWidth() {
        return width;
    }
    
    public int getHeight() {
        return height;
    }
    
    public int getNumBands() {
        return numBands;
    }
    
    public int getDataType() {
        return dataType;
    }
    
    public int getNumDataElements() {
        return numBands;
    }
}

