package app.capgo.capacitor.camera.preview;

/**
 * Utility class to validate face alignment for optimal capture.
 * Checks head pose angles (pitch, roll, yaw) and face size.
 */
public class FaceAlignmentValidator {

    // Default thresholds for face alignment validation
    private static final double DEFAULT_MAX_ROLL_DEGREES = 15.0;
    private static final double DEFAULT_MAX_PITCH_DEGREES = 15.0;
    private static final double DEFAULT_MAX_YAW_DEGREES = 20.0;
    private static final double DEFAULT_MIN_FACE_SIZE = 0.20; // 20% of frame
    private static final double DEFAULT_MAX_FACE_SIZE = 0.80; // 80% of frame
    private static final double DEFAULT_MIN_CENTER_X = 0.35; // Face center should be 35-65% horizontally
    private static final double DEFAULT_MAX_CENTER_X = 0.65;
    private static final double DEFAULT_MIN_CENTER_Y = 0.30; // Face center should be 30-70% vertically
    private static final double DEFAULT_MAX_CENTER_Y = 0.70;

    private final double maxRollDegrees;
    private final double maxPitchDegrees;
    private final double maxYawDegrees;
    private final double minFaceSize;
    private final double maxFaceSize;
    private final double minCenterX;
    private final double maxCenterX;
    private final double minCenterY;
    private final double maxCenterY;

    /**
     * Create validator with default thresholds
     */
    public FaceAlignmentValidator() {
        this(
            DEFAULT_MAX_ROLL_DEGREES,
            DEFAULT_MAX_PITCH_DEGREES,
            DEFAULT_MAX_YAW_DEGREES,
            DEFAULT_MIN_FACE_SIZE,
            DEFAULT_MAX_FACE_SIZE,
            DEFAULT_MIN_CENTER_X,
            DEFAULT_MAX_CENTER_X,
            DEFAULT_MIN_CENTER_Y,
            DEFAULT_MAX_CENTER_Y
        );
    }

    /**
     * Constructs a FaceAlignmentValidator using the provided threshold and bound values.
     *
     * @param maxRollDegrees maximum allowed absolute roll angle in degrees before roll is considered misaligned
     * @param maxPitchDegrees maximum allowed absolute pitch angle in degrees before pitch is considered misaligned
     * @param maxYawDegrees maximum allowed absolute yaw angle in degrees before yaw is considered misaligned
     * @param minFaceSize minimum allowed face size (fraction of frame width/height) before the face is considered too small
     * @param maxFaceSize maximum allowed face size (fraction of frame width/height) before the face is considered too large
     * @param minCenterX minimum allowed normalized X coordinate of the face center
     * @param maxCenterX maximum allowed normalized X coordinate of the face center
     * @param minCenterY minimum allowed normalized Y coordinate of the face center
     * @param maxCenterY maximum allowed normalized Y coordinate of the face center
     */
    public FaceAlignmentValidator(
        double maxRollDegrees,
        double maxPitchDegrees,
        double maxYawDegrees,
        double minFaceSize,
        double maxFaceSize,
        double minCenterX,
        double maxCenterX,
        double minCenterY,
        double maxCenterY
    ) {
        this.maxRollDegrees = maxRollDegrees;
        this.maxPitchDegrees = maxPitchDegrees;
        this.maxYawDegrees = maxYawDegrees;
        this.minFaceSize = minFaceSize;
        this.maxFaceSize = maxFaceSize;
        this.minCenterX = minCenterX;
        this.maxCenterX = maxCenterX;
        this.minCenterY = minCenterY;
        this.maxCenterY = maxCenterY;
    }

    /**
     * Validate face alignment and produce per-aspect validity flags and feedback.
     *
     * @param rollAngle   Head roll angle in degrees; positive values indicate tilt to the right.
     * @param pitchAngle  Head pitch angle in degrees; positive values indicate looking down.
     * @param yawAngle    Head yaw angle in degrees; positive values indicate turning to the right.
     * @param boundsX     Face bounding box X coordinate normalized to [0,1] relative to the frame.
     * @param boundsY     Face bounding box Y coordinate normalized to [0,1] relative to the frame.
     * @param boundsWidth Face bounding box width normalized to [0,1] relative to the frame.
     * @param boundsHeight Face bounding box height normalized to [0,1] relative to the frame.
     * @return AlignmentResult containing overall validity, individual validation flags (roll, pitch, yaw, size, centering),
     *         and optional human-readable feedback messages for any failing checks.
     */
    public AlignmentResult validate(
        float rollAngle,
        float pitchAngle,
        float yawAngle,
        double boundsX,
        double boundsY,
        double boundsWidth,
        double boundsHeight
    ) {
        AlignmentResult result = new AlignmentResult();

        // Validate roll (head tilt)
        if (Math.abs(rollAngle) > maxRollDegrees) {
            result.isRollValid = false;
            result.rollFeedback = rollAngle > 0 ? "Tilt your head less to the right" : "Tilt your head less to the left";
        } else {
            result.isRollValid = true;
        }

        // Validate pitch (head nod)
        if (Math.abs(pitchAngle) > maxPitchDegrees) {
            result.isPitchValid = false;
            result.pitchFeedback = pitchAngle > 0 ? "Look down less" : "Look up less";
        } else {
            result.isPitchValid = true;
        }

        // Validate yaw (head turn)
        if (Math.abs(yawAngle) > maxYawDegrees) {
            result.isYawValid = false;
            result.yawFeedback = yawAngle > 0 ? "Turn your head less to the right" : "Turn your head less to the left";
        } else {
            result.isYawValid = true;
        }

        // Validate face size
        double faceSize = Math.max(boundsWidth, boundsHeight);
        if (faceSize < minFaceSize) {
            result.isSizeValid = false;
            result.sizeFeedback = "Move closer to the camera";
        } else if (faceSize > maxFaceSize) {
            result.isSizeValid = false;
            result.sizeFeedback = "Move farther from the camera";
        } else {
            result.isSizeValid = true;
        }

        // Validate face centering
        double centerX = boundsX + boundsWidth / 2.0;
        double centerY = boundsY + boundsHeight / 2.0;

        if (centerX < minCenterX) {
            result.isCenteringValid = false;
            result.centeringFeedback = "Move right";
        } else if (centerX > maxCenterX) {
            result.isCenteringValid = false;
            result.centeringFeedback = "Move left";
        } else if (centerY < minCenterY) {
            result.isCenteringValid = false;
            result.centeringFeedback = "Move down";
        } else if (centerY > maxCenterY) {
            result.isCenteringValid = false;
            result.centeringFeedback = "Move up";
        } else {
            result.isCenteringValid = true;
        }

        // Overall validation
        result.isValid = result.isRollValid && result.isPitchValid && result.isYawValid && result.isSizeValid && result.isCenteringValid;

        return result;
    }

    /**
     * Result of face alignment validation
     */
    public static class AlignmentResult {

        public boolean isValid = false;

        // Individual validations
        public boolean isRollValid = false;
        public boolean isPitchValid = false;
        public boolean isYawValid = false;
        public boolean isSizeValid = false;
        public boolean isCenteringValid = false;

        // Feedback messages
        public String rollFeedback = null;
        public String pitchFeedback = null;
        public String yawFeedback = null;
        public String sizeFeedback = null;
        public String centeringFeedback = null;

        /**
         * Selects the most important face-alignment feedback message.
         *
         * @return the first non-null specific feedback in this order: roll, pitch, yaw, size, centering;
         *         if no specific feedback is present, returns "Face aligned perfectly".
         */
        public String getPrimaryFeedback() {
            if (rollFeedback != null) return rollFeedback;
            if (pitchFeedback != null) return pitchFeedback;
            if (yawFeedback != null) return yawFeedback;
            if (sizeFeedback != null) return sizeFeedback;
            if (centeringFeedback != null) return centeringFeedback;
            return "Face aligned perfectly";
        }

        /**
         * Collects all non-null per-aspect feedback messages in priority order.
         *
         * @return an array containing all non-null feedback messages in priority order: roll, pitch, yaw, size, centering
         */
        public String[] getAllFeedback() {
            java.util.ArrayList<String> feedback = new java.util.ArrayList<>();
            if (rollFeedback != null) feedback.add(rollFeedback);
            if (pitchFeedback != null) feedback.add(pitchFeedback);
            if (yawFeedback != null) feedback.add(yawFeedback);
            if (sizeFeedback != null) feedback.add(sizeFeedback);
            if (centeringFeedback != null) feedback.add(centeringFeedback);
            return feedback.toArray(new String[0]);
        }
    }
}