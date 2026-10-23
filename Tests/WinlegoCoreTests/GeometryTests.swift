import CoreGraphics
import Testing
@testable import WinlegoCore

@Suite struct GeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1000, height: 600)

    @Test func normalizedRectResolvesInsideFrame() {
        let r = NormRect(x: 0.5, y: 0, width: 0.5, height: 1).resolved(in: screen)
        #expect(r == CGRect(x: 500, y: 25, width: 500, height: 600))
    }

    @Test func gapShrinksEachZoneByHalfTheGap() {
        let r = NormRect.full.resolved(in: screen, gap: 10)
        #expect(r == CGRect(x: 5, y: 30, width: 990, height: 590))
    }

    @Test func flipIsAnInvolution() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flipped = Geometry.flip(r, primaryHeight: 1000)
        #expect(flipped == CGRect(x: 10, y: 780, width: 300, height: 200))
        #expect(Geometry.flip(flipped, primaryHeight: 1000) == r)
    }

    @Test func zoneUnderPointAndBestOverlap() {
        let zones = Presets.halves.frames(in: screen)
        #expect(Geometry.zoneIndex(containing: CGPoint(x: 10, y: 100), in: zones) == 0)
        #expect(Geometry.zoneIndex(containing: CGPoint(x: 900, y: 100), in: zones) == 1)
        #expect(Geometry.zoneIndex(containing: CGPoint(x: 10, y: 5), in: zones) == nil)
        let window = CGRect(x: 400, y: 100, width: 300, height: 200)   // 100 px left, 200 px right
        #expect(Geometry.bestZone(for: window, in: zones) == 1)
        #expect(Geometry.bestZone(for: CGRect(x: 2000, y: 0, width: 10, height: 10), in: zones) == nil)
    }

    @Test func neighbouringZonesMeetWithoutOverlap() {
        let odd = CGRect(x: 0, y: 30, width: 3008, height: 1572)
        let zones = Presets.wideLeft.frames(in: odd)
        #expect(zones[0].maxX == zones[1].minX)
        #expect(zones[0].minX == 0 && zones[1].maxX == 3008)
        let thirds = Presets.thirds.frames(in: CGRect(x: 0, y: 0, width: 1000, height: 100))
        #expect(thirds.map(\.width) == [333, 334, 333])
        #expect(thirds[0].maxX == thirds[1].minX && thirds[1].maxX == thirds[2].minX)
    }

    @Test func stepWrapsAround() {
        #expect(Geometry.step(zone: 2, count: 3, by: 1) == 0)
        #expect(Geometry.step(zone: 0, count: 3, by: -1) == 2)
        #expect(Geometry.step(zone: 0, count: 0, by: 1) == 0)
    }

    @Test func presetsStayInsideTheUnitSquare() {
        for layout in Presets.all {
            #expect(!layout.zones.isEmpty)
            for zone in layout.zones {
                let r = zone.rect
                #expect(r.x >= 0 && r.y >= 0 && r.x + r.width <= 1.0001 && r.y + r.height <= 1.0001, "\(layout.id)/\(zone.name)")
            }
        }
        #expect(Set(Presets.all.map(\.id)).count == Presets.all.count)
    }
}
