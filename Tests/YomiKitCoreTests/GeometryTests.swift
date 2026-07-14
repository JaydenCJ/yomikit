import XCTest
@testable import YomiKitCore

final class GeometryTests: XCTestCase {

    func testUnionAndArea() {
        let a = BoundingBox(x: 0, y: 0, width: 10, height: 10)
        let b = BoundingBox(x: 5, y: 5, width: 10, height: 10)
        let union = a.union(b)
        XCTAssertEqual(union.minX, 0)
        XCTAssertEqual(union.minY, 0)
        XCTAssertEqual(union.maxX, 15)
        XCTAssertEqual(union.maxY, 15)
        XCTAssertEqual(a.area, 100)
        XCTAssertNil(BoundingBox.union(of: []))
    }

    func testOverlapRatios() {
        let a = BoundingBox(x: 0, y: 0, width: 100, height: 10)
        let b = BoundingBox(x: 50, y: 5, width: 100, height: 10)
        XCTAssertEqual(a.horizontalOverlap(with: b), 50)
        XCTAssertEqual(a.horizontalOverlapRatio(with: b), 0.5)
        XCTAssertEqual(a.verticalOverlap(with: b), 5)
        XCTAssertEqual(a.verticalOverlapRatio(with: b), 0.5)

        let disjoint = BoundingBox(x: 300, y: 100, width: 10, height: 10)
        XCTAssertEqual(a.horizontalOverlapRatio(with: disjoint), 0)
        XCTAssertEqual(a.horizontalGap(to: disjoint), 200)
        XCTAssertEqual(a.verticalGap(to: disjoint), 90)
        XCTAssertFalse(a.intersects(disjoint))
        XCTAssertTrue(a.intersects(b))
    }

    func testZeroSizeBoxesDoNotDivideByZero() {
        let point = BoundingBox(x: 5, y: 5, width: 0, height: 0)
        let other = BoundingBox(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(point.horizontalOverlapRatio(with: other), 0)
        XCTAssertEqual(point.verticalOverlapRatio(with: other), 0)
    }

    func testIntervalBands() {
        let intervals = [
            Interval(lowerBound: 0, upperBound: 10),
            Interval(lowerBound: 2, upperBound: 12),
            Interval(lowerBound: 30, upperBound: 40),
        ]
        let result = IntervalClustering.bands(of: intervals, minOverlapRatio: 0.5)
        XCTAssertEqual(result.bands.count, 2)
        XCTAssertEqual(result.assignments, [0, 0, 1])
        XCTAssertEqual(result.bands[0].lowerBound, 0)
        XCTAssertEqual(result.bands[0].upperBound, 12)
    }

    func testIntervalGaps() {
        let intervals = [
            Interval(lowerBound: 0, upperBound: 10),
            Interval(lowerBound: 5, upperBound: 15),
            Interval(lowerBound: 25, upperBound: 30),
            Interval(lowerBound: 50, upperBound: 60),
        ]
        let gaps = IntervalClustering.gaps(in: intervals)
        XCTAssertEqual(gaps.count, 2)
        XCTAssertEqual(gaps[0], Interval(lowerBound: 15, upperBound: 25))
        XCTAssertEqual(gaps[1], Interval(lowerBound: 30, upperBound: 50))
        XCTAssertTrue(IntervalClustering.gaps(in: []).isEmpty)
    }
}
