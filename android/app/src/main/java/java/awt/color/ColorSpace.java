package java.awt.color;

/**
 * Minimal AWT ColorSpace stub for Android compatibility with PDFBox
 */
public abstract class ColorSpace {
    public static final int TYPE_RGB = 1;
    public static final int TYPE_XYZ = 2;
    public static final int TYPE_Lab = 3;
    public static final int TYPE_Luv = 4;
    public static final int TYPE_YCbCr = 5;
    public static final int TYPE_Yxy = 6;
    public static final int TYPE_HSV = 7;
    public static final int TYPE_HLS = 8;
    public static final int TYPE_CMYK = 9;
    public static final int TYPE_CMY = 11;
    public static final int TYPE_2CLR = 12;
    public static final int TYPE_3CLR = 13;
    public static final int TYPE_4CLR = 14;
    public static final int TYPE_5CLR = 15;
    public static final int TYPE_6CLR = 16;
    public static final int TYPE_7CLR = 17;
    public static final int TYPE_8CLR = 18;
    public static final int TYPE_9CLR = 19;
    public static final int TYPE_ACLR = 20;
    public static final int TYPE_BCLR = 21;
    public static final int TYPE_CCLR = 22;
    public static final int TYPE_DCLR = 23;
    public static final int TYPE_ECLR = 24;
    public static final int TYPE_FCLR = 25;
    public static final int TYPE_GRAY = 6;
    public static final int TYPE_LINEAR_RGB = 0x1000;
    public static final int TYPE_CS_sRGB = 1000;
    public static final int TYPE_CS_LINEAR_RGB = 1004;
    public static final int TYPE_CS_CIEXYZ = 1001;
    public static final int TYPE_CS_PYCC = 1002;
    public static final int TYPE_CS_GRAY = 1003;
    
    protected int type;
    protected int numComponents;
    
    protected ColorSpace(int type, int numcomponents) {
        this.type = type;
        this.numComponents = numcomponents;
    }
    
    public int getType() {
        return type;
    }
    
    public int getNumComponents() {
        return numComponents;
    }
    
    public abstract float[] toRGB(float[] colorvalue);
    public abstract float[] fromRGB(float[] rgbvalue);
    public abstract float[] toCIEXYZ(float[] colorvalue);
    public abstract float[] fromCIEXYZ(float[] colorvalue);
    
    public static ColorSpace getInstance(int colorspace) {
        // Return a stub implementation
        return new ColorSpace(TYPE_RGB, 3) {
            @Override
            public float[] toRGB(float[] colorvalue) {
                return colorvalue != null && colorvalue.length >= 3 ? colorvalue : new float[]{0, 0, 0};
            }
            
            @Override
            public float[] fromRGB(float[] rgbvalue) {
                return rgbvalue != null && rgbvalue.length >= 3 ? rgbvalue : new float[]{0, 0, 0};
            }
            
            @Override
            public float[] toCIEXYZ(float[] colorvalue) {
                return colorvalue != null && colorvalue.length >= 3 ? colorvalue : new float[]{0, 0, 0};
            }
            
            @Override
            public float[] fromCIEXYZ(float[] colorvalue) {
                return colorvalue != null && colorvalue.length >= 3 ? colorvalue : new float[]{0, 0, 0};
            }
        };
    }
}

