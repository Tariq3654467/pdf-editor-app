package java.awt.geom;

import java.awt.geom.Point2D;

/**
 * Minimal AWT AffineTransform stub for Android compatibility with PDFBox
 * Represents a 2D affine transformation matrix
 */
public class AffineTransform implements Cloneable {
    // Transformation matrix: [m00 m01 m02]
    //                         [m10 m11 m12]
    //                         [0   0   1  ]
    private double m00;
    private double m10;
    private double m01;
    private double m11;
    private double m02;
    private double m12;
    
    // Type flags
    public static final int TYPE_IDENTITY = 0;
    public static final int TYPE_TRANSLATION = 1;
    public static final int TYPE_UNIFORM_SCALE = 2;
    public static final int TYPE_GENERAL_SCALE = 4;
    public static final int TYPE_FLIP = 64;
    public static final int TYPE_QUADRANT_ROTATION = 8;
    public static final int TYPE_GENERAL_ROTATION = 16;
    public static final int TYPE_GENERAL_TRANSFORM = 32;
    
    /**
     * Identity transformation
     */
    public AffineTransform() {
        m00 = m11 = 1.0;
        m10 = m01 = m02 = m12 = 0.0;
    }
    
    /**
     * Create from matrix values
     */
    public AffineTransform(double m00, double m10, double m01, double m11, double m02, double m12) {
        this.m00 = m00;
        this.m10 = m10;
        this.m01 = m01;
        this.m11 = m11;
        this.m02 = m02;
        this.m12 = m12;
    }
    
    /**
     * Copy constructor
     */
    public AffineTransform(AffineTransform tx) {
        if (tx != null) {
            this.m00 = tx.m00;
            this.m10 = tx.m10;
            this.m01 = tx.m01;
            this.m11 = tx.m11;
            this.m02 = tx.m02;
            this.m12 = tx.m12;
        } else {
            m00 = m11 = 1.0;
            m10 = m01 = m02 = m12 = 0.0;
        }
    }
    
    /**
     * Create from float array [m00, m10, m01, m11, m02, m12]
     */
    public AffineTransform(float[] flatmatrix) {
        if (flatmatrix != null && flatmatrix.length >= 6) {
            m00 = flatmatrix[0];
            m10 = flatmatrix[1];
            m01 = flatmatrix[2];
            m11 = flatmatrix[3];
            m02 = flatmatrix[4];
            m12 = flatmatrix[5];
        } else {
            m00 = m11 = 1.0;
            m10 = m01 = m02 = m12 = 0.0;
        }
    }
    
    /**
     * Create from double array [m00, m10, m01, m11, m02, m12]
     */
    public AffineTransform(double[] flatmatrix) {
        if (flatmatrix != null && flatmatrix.length >= 6) {
            m00 = flatmatrix[0];
            m10 = flatmatrix[1];
            m01 = flatmatrix[2];
            m11 = flatmatrix[3];
            m02 = flatmatrix[4];
            m12 = flatmatrix[5];
        } else {
            m00 = m11 = 1.0;
            m10 = m01 = m02 = m12 = 0.0;
        }
    }
    
    public double getScaleX() {
        return m00;
    }
    
    public double getScaleY() {
        return m11;
    }
    
    public double getShearX() {
        return m01;
    }
    
    public double getShearY() {
        return m10;
    }
    
    public double getTranslateX() {
        return m02;
    }
    
    public double getTranslateY() {
        return m12;
    }
    
    public void setToIdentity() {
        m00 = m11 = 1.0;
        m10 = m01 = m02 = m12 = 0.0;
    }
    
    public void setToTranslation(double tx, double ty) {
        m00 = m11 = 1.0;
        m10 = m01 = 0.0;
        m02 = tx;
        m12 = ty;
    }
    
    public void setToScale(double sx, double sy) {
        m00 = sx;
        m11 = sy;
        m10 = m01 = m02 = m12 = 0.0;
    }
    
    public void setToRotation(double theta) {
        double sin = Math.sin(theta);
        double cos = Math.cos(theta);
        m00 = cos;
        m10 = sin;
        m01 = -sin;
        m11 = cos;
        m02 = m12 = 0.0;
    }
    
    public void setToRotation(double theta, double anchorx, double anchory) {
        setToRotation(theta);
        double sin = m10;
        double cos = m00;
        m02 = anchorx * (1.0 - cos) + anchory * sin;
        m12 = anchory * (1.0 - cos) - anchorx * sin;
    }
    
    public void setToShear(double shx, double shy) {
        m00 = 1.0;
        m01 = shx;
        m10 = shy;
        m11 = 1.0;
        m02 = m12 = 0.0;
    }
    
    public void setTransform(double m00, double m10, double m01, double m11, double m02, double m12) {
        this.m00 = m00;
        this.m10 = m10;
        this.m01 = m01;
        this.m11 = m11;
        this.m02 = m02;
        this.m12 = m12;
    }
    
    public void setTransform(AffineTransform tx) {
        if (tx != null) {
            this.m00 = tx.m00;
            this.m10 = tx.m10;
            this.m01 = tx.m01;
            this.m11 = tx.m11;
            this.m02 = tx.m02;
            this.m12 = tx.m12;
        } else {
            setToIdentity();
        }
    }
    
    public void getMatrix(double[] flatmatrix) {
        if (flatmatrix != null && flatmatrix.length >= 6) {
            flatmatrix[0] = m00;
            flatmatrix[1] = m10;
            flatmatrix[2] = m01;
            flatmatrix[3] = m11;
            flatmatrix[4] = m02;
            flatmatrix[5] = m12;
        }
    }
    
    public void translate(double tx, double ty) {
        m02 += tx * m00 + ty * m01;
        m12 += tx * m10 + ty * m11;
    }
    
    public void scale(double sx, double sy) {
        m00 *= sx;
        m10 *= sx;
        m01 *= sy;
        m11 *= sy;
    }
    
    public void rotate(double theta) {
        double sin = Math.sin(theta);
        double cos = Math.cos(theta);
        double m00_new = m00 * cos + m01 * sin;
        double m10_new = m10 * cos + m11 * sin;
        double m01_new = m00 * -sin + m01 * cos;
        double m11_new = m10 * -sin + m11 * cos;
        m00 = m00_new;
        m10 = m10_new;
        m01 = m01_new;
        m11 = m11_new;
    }
    
    public void rotate(double theta, double anchorx, double anchory) {
        translate(-anchorx, -anchory);
        rotate(theta);
        translate(anchorx, anchory);
    }
    
    public void shear(double shx, double shy) {
        double m00_new = m00 + m01 * shy;
        double m10_new = m10 + m11 * shy;
        double m01_new = m01 + m00 * shx;
        double m11_new = m11 + m10 * shx;
        m00 = m00_new;
        m10 = m10_new;
        m01 = m01_new;
        m11 = m11_new;
    }
    
    public void concatenate(AffineTransform tx) {
        if (tx != null) {
            double m00_new = m00 * tx.m00 + m01 * tx.m10;
            double m10_new = m10 * tx.m00 + m11 * tx.m10;
            double m01_new = m00 * tx.m01 + m01 * tx.m11;
            double m11_new = m10 * tx.m01 + m11 * tx.m11;
            double m02_new = m00 * tx.m02 + m01 * tx.m12 + m02;
            double m12_new = m10 * tx.m02 + m11 * tx.m12 + m12;
            
            m00 = m00_new;
            m10 = m10_new;
            m01 = m01_new;
            m11 = m11_new;
            m02 = m02_new;
            m12 = m12_new;
        }
    }
    
    public void preConcatenate(AffineTransform tx) {
        if (tx != null) {
            double m00_new = tx.m00 * m00 + tx.m01 * m10;
            double m10_new = tx.m10 * m00 + tx.m11 * m10;
            double m01_new = tx.m00 * m01 + tx.m01 * m11;
            double m11_new = tx.m10 * m01 + tx.m11 * m11;
            double m02_new = tx.m00 * m02 + tx.m01 * m12 + tx.m02;
            double m12_new = tx.m10 * m02 + tx.m11 * m12 + tx.m12;
            
            m00 = m00_new;
            m10 = m10_new;
            m01 = m01_new;
            m11 = m11_new;
            m02 = m02_new;
            m12 = m12_new;
        }
    }
    
    public Point2D transform(Point2D ptSrc, Point2D ptDst) {
        if (ptDst == null) {
            ptDst = new Point2D.Double();
        }
        double x = ptSrc.getX();
        double y = ptSrc.getY();
        ptDst.setLocation(
            x * m00 + y * m01 + m02,
            x * m10 + y * m11 + m12
        );
        return ptDst;
    }
    
    public void transform(double[] srcPts, int srcOff, double[] dstPts, int dstOff, int numPts) {
        for (int i = 0; i < numPts; i++) {
            double x = srcPts[srcOff + i * 2];
            double y = srcPts[srcOff + i * 2 + 1];
            dstPts[dstOff + i * 2] = x * m00 + y * m01 + m02;
            dstPts[dstOff + i * 2 + 1] = x * m10 + y * m11 + m12;
        }
    }
    
    public void transform(float[] srcPts, int srcOff, float[] dstPts, int dstOff, int numPts) {
        for (int i = 0; i < numPts; i++) {
            float x = srcPts[srcOff + i * 2];
            float y = srcPts[srcOff + i * 2 + 1];
            dstPts[dstOff + i * 2] = (float)(x * m00 + y * m01 + m02);
            dstPts[dstOff + i * 2 + 1] = (float)(x * m10 + y * m11 + m12);
        }
    }
    
    public Point2D inverseTransform(Point2D ptSrc, Point2D ptDst) {
        double det = getDeterminant();
        if (Math.abs(det) < Double.MIN_VALUE) {
            // Singular matrix - return identity transform result
            if (ptDst == null) {
                ptDst = new Point2D.Double();
            }
            ptDst.setLocation(ptSrc.getX(), ptSrc.getY());
            return ptDst;
        }
        
        double x = ptSrc.getX() - m02;
        double y = ptSrc.getY() - m12;
        
        if (ptDst == null) {
            ptDst = new Point2D.Double();
        }
        ptDst.setLocation(
            (x * m11 - y * m01) / det,
            (y * m00 - x * m10) / det
        );
        return ptDst;
    }
    
    public double getDeterminant() {
        return m00 * m11 - m01 * m10;
    }
    
    public int getType() {
        int type = 0;
        if (m00 != 1.0 || m11 != 1.0 || m01 != 0.0 || m10 != 0.0) {
            type |= TYPE_GENERAL_TRANSFORM;
        }
        if (m02 != 0.0 || m12 != 0.0) {
            type |= TYPE_TRANSLATION;
        }
        return type;
    }
    
    public boolean isIdentity() {
        return m00 == 1.0 && m11 == 1.0 && m01 == 0.0 && m10 == 0.0 && m02 == 0.0 && m12 == 0.0;
    }
    
    public AffineTransform createInverse() {
        double det = getDeterminant();
        if (Math.abs(det) < Double.MIN_VALUE) {
            // Return identity if singular
            return new AffineTransform();
        }
        double invDet = 1.0 / det;
        return new AffineTransform(
            m11 * invDet, -m10 * invDet,
            -m01 * invDet, m00 * invDet,
            (m01 * m12 - m11 * m02) * invDet,
            (m10 * m02 - m00 * m12) * invDet
        );
    }
    
    @Override
    public Object clone() {
        return new AffineTransform(this);
    }
    
    @Override
    public String toString() {
        return "AffineTransform[" + m00 + ", " + m10 + ", " + m01 + ", " + m11 + ", " + m02 + ", " + m12 + "]";
    }
}

