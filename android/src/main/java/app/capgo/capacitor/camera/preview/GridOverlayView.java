package app.capgo.capacitor.camera.preview;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.util.AttributeSet;
import android.view.View;
import androidx.annotation.NonNull;

public class GridOverlayView extends View {

    private Paint gridPaint;
    private String gridMode = "none";
    private Rect cameraBounds = null;

    public GridOverlayView(Context context) {
        super(context);
        init();
    }

    public GridOverlayView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public GridOverlayView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }

    private void init() {
        gridPaint = new Paint();
        gridPaint.setColor(0x80FFFFFF); // Semi-transparent white
        gridPaint.setStrokeWidth(2f);
        gridPaint.setStyle(Paint.Style.STROKE);
        gridPaint.setAntiAlias(true);
    }

    public void setCameraBounds(Rect bounds) {
        this.cameraBounds = bounds;
        invalidate();
    }

    public void setGridMode(String mode) {
        String previousMode = this.gridMode;
        this.gridMode = mode != null ? mode : "none";
        setVisibility("none".equals(this.gridMode) ? View.GONE : View.VISIBLE);
        android.util.Log.d(
            "GridOverlayView",
            "setGridMode: Changed from '" +
            previousMode +
            "' to '" +
            this.gridMode +
            "', visibility: " +
            ("none".equals(this.gridMode) ? "GONE" : "VISIBLE")
        );
        invalidate();
    }

    @Override
    protected void onDraw(@NonNull Canvas canvas) {
        super.onDraw(canvas);

        if ("none".equals(gridMode)) {
            return;
        }

        // Use camera bounds if available, otherwise use full view bounds
        int left = 0;
        int top = 0;
        int width = getWidth();
        int height = getHeight();

        if (cameraBounds != null) {
            left = cameraBounds.left;
            top = cameraBounds.top;
            width = cameraBounds.width();
            height = cameraBounds.height();
        }

        if (width <= 0 || height <= 0) {
            return;
        }

        if ("3x3".equals(gridMode)) {
            drawGrid(canvas, left, top, width, height, 3);
        } else if ("4x4".equals(gridMode)) {
            drawGrid(canvas, left, top, width, height, 4);
        }
    }

    private void drawGrid(Canvas canvas, int left, int top, int width, int height, int divisions) {
        float stepX = (float) width / divisions;
        float stepY = (float) height / divisions;

        // Draw vertical lines
        for (int i = 1; i < divisions; i++) {
            float x = left + (i * stepX);
            canvas.drawLine(x, top, x, top + height, gridPaint);
        }

        // Draw horizontal lines
        for (int i = 1; i < divisions; i++) {
            float y = top + (i * stepY);
            canvas.drawLine(left, y, left + width, y, gridPaint);
        }
    }
}
