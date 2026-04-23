package java.awt.image;

/**
 * Minimal AWT DataBuffer stub for Android compatibility with PDFBox
 */
public abstract class DataBuffer {
    protected int dataType;
    protected int banks;
    protected int offset;
    protected int size;
    protected int[] offsets;
    
    protected DataBuffer(int dataType, int size) {
        this.dataType = dataType;
        this.size = size;
        this.banks = 1;
        this.offset = 0;
        this.offsets = new int[1];
    }
    
    public int getDataType() {
        return dataType;
    }
    
    public int getSize() {
        return size;
    }
    
    public int getNumBanks() {
        return banks;
    }
    
    public int getOffset() {
        return offset;
    }
}

