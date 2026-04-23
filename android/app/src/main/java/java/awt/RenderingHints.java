package java.awt;

import java.util.Map;

/**
 * Minimal AWT RenderingHints stub for Android compatibility with PDFBox
 */
public class RenderingHints implements Map<Object, Object>, Cloneable {
    
    public RenderingHints(Map<Key, ?> init) {
        // Stub constructor
    }
    
    public RenderingHints(Key key, Object value) {
        // Stub constructor
    }
    
    // Minimal Map implementation stubs
    @Override
    public int size() { return 0; }
    
    @Override
    public boolean isEmpty() { return true; }
    
    @Override
    public boolean containsKey(Object key) { return false; }
    
    @Override
    public boolean containsValue(Object value) { return false; }
    
    @Override
    public Object get(Object key) { return null; }
    
    @Override
    public Object put(Object key, Object value) { return null; }
    
    @Override
    public Object remove(Object key) { return null; }
    
    @Override
    public void putAll(Map<? extends Object, ? extends Object> m) {}
    
    @Override
    public void clear() {}
    
    @Override
    public java.util.Set<Object> keySet() { return java.util.Collections.emptySet(); }
    
    @Override
    public java.util.Collection<Object> values() { return java.util.Collections.emptyList(); }
    
    @Override
    public java.util.Set<Map.Entry<Object, Object>> entrySet() { return java.util.Collections.emptySet(); }
    
    public static class Key {
        private String name;
        protected Key(String name) {
            this.name = name;
        }
    }
}

