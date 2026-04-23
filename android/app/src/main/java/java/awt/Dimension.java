package java.awt;

/**
 * Minimal AWT Dimension stub for Android compatibility with PDFBox
 */
public class Dimension {
    public int width;
    public int height;
    
    public Dimension() {
        this(0, 0);
    }
    
    public Dimension(int width, int height) {
        this.width = width;
        this.height = height;
    }
    
    public Dimension(Dimension d) {
        this(d.width, d.height);
    }
    
    public void setSize(int width, int height) {
        this.width = width;
        this.height = height;
    }
    
    public void setSize(Dimension d) {
        this.width = d.width;
        this.height = d.height;
    }
    
    public Dimension getSize() {
        return new Dimension(width, height);
    }
    
    @Override
    public String toString() {
        return "Dimension[width=" + width + ",height=" + height + "]";
    }
}

