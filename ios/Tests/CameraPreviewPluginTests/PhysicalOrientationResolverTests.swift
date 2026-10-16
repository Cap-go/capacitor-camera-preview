import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class PhysicalOrientationResolverTests: XCTestCase {
    private func accel(x: Double, y: Double, z: Double) -> PhysicalOrientationResolver.Acceleration {
        PhysicalOrientationResolver.Acceleration(x: x, y: y, z: z)
    }

    func testNearFlatUsesFallbackWhenNoLastReliable() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.04, y: -0.03, z: -0.99),
            lastReliableOrientation: nil,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .portrait)
        XCTAssertFalse(result.isReliable)
    }

    func testNearFlatKeepsLastReliableOrientation() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.05, y: 0.02, z: 0.92),
            lastReliableOrientation: .landscapeLeft,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .landscapeLeft)
        XCTAssertFalse(result.isReliable)
    }

    func testClearPortrait() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.08, y: -0.95, z: 0.15),
            lastReliableOrientation: nil,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .portrait)
        XCTAssertTrue(result.isReliable)
    }

    func testClearLandscapeLeft() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.92, y: 0.08, z: 0.05),
            lastReliableOrientation: nil,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .landscapeLeft)
        XCTAssertTrue(result.isReliable)
    }

    func testClearLandscapeRight() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: -0.9, y: 0.1, z: 0.05),
            lastReliableOrientation: nil,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .landscapeRight)
        XCTAssertTrue(result.isReliable)
    }

    func testUpsideDownPortrait() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.05, y: 0.94, z: 0.1),
            lastReliableOrientation: nil,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .portraitUpsideDown)
        XCTAssertTrue(result.isReliable)
    }

    func testAmbiguousAxisUsesLastReliable() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.52, y: -0.48, z: 0.2),
            lastReliableOrientation: .portrait,
            fallbackOrientation: .landscapeLeft
        )
        XCTAssertEqual(result.orientation, .portrait)
        XCTAssertFalse(result.isReliable)
    }

    func testWeakHorizontalGravityTreatedAsFlat() {
        let result = PhysicalOrientationResolver.resolve(
            acceleration: accel(x: 0.12, y: -0.18, z: 0.55),
            lastReliableOrientation: .landscapeRight,
            fallbackOrientation: .portrait
        )
        XCTAssertEqual(result.orientation, .landscapeRight)
        XCTAssertFalse(result.isReliable)
    }
}
