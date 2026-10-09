package app.capgo.capacitor.camera.preview;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import androidx.annotation.Nullable;

/** Subsampled JPEG decode for capture resize paths. */
final class CaptureBitmapDecoding {

    private CaptureBitmapDecoding() {}

    @Nullable
    static Bitmap decodeJpegSubsamplingToMaxDimensions(byte[] jpegBytes, @Nullable Integer maxWidth, @Nullable Integer maxHeight) {
        if (jpegBytes == null || jpegBytes.length == 0) {
            return null;
        }
        BitmapFactory.Options boundsOptions = new BitmapFactory.Options();
        boundsOptions.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length, boundsOptions);
        int sourceWidth = boundsOptions.outWidth;
        int sourceHeight = boundsOptions.outHeight;
        if (sourceWidth <= 0 || sourceHeight <= 0) {
            return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length);
        }

        BitmapFactory.Options decodeOptions = new BitmapFactory.Options();
        decodeOptions.inSampleSize = computeInSampleSize(sourceWidth, sourceHeight, maxWidth, maxHeight);
        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length, decodeOptions);
    }

    static int computeInSampleSize(int sourceWidth, int sourceHeight, @Nullable Integer maxWidth, @Nullable Integer maxHeight) {
        if (maxWidth == null && maxHeight == null) {
            return 1;
        }

        int reqWidth;
        int reqHeight;
        if (maxWidth != null && maxHeight != null) {
            reqWidth = maxWidth;
            reqHeight = maxHeight;
        } else if (maxWidth != null) {
            reqWidth = maxWidth;
            reqHeight = Math.max(1, (int) (((long) sourceHeight * maxWidth) / sourceWidth));
        } else {
            reqHeight = maxHeight;
            reqWidth = Math.max(1, (int) (((long) sourceWidth * maxHeight) / sourceHeight));
        }
        if (reqWidth <= 0 || reqHeight <= 0) {
            return 1;
        }

        int inSampleSize = 1;
        if (sourceHeight > reqHeight || sourceWidth > reqWidth) {
            final int halfHeight = sourceHeight / 2;
            final int halfWidth = sourceWidth / 2;
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2;
            }
        }
        return Math.max(1, inSampleSize);
    }
}
