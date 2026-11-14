// Isolated drawing-preparation benchmark using synthetic routes on macOS.
// Not an ARKit, GPS, rendered-frame, or physical walking measurement.
// Run: swiftc -Onone scripts/benchmark_indoor_map.swift -o /tmp/indoor-map-bench
//      /tmp/indoor-map-bench

import SwiftUI
import Foundation
struct Point { let x: Float; let z: Float }
@inline(never) func prepare(_ points: [Point]) -> (CGRect, Path) {
    let xs = points.map { CGFloat($0.x) }, zs = points.map { CGFloat($0.z) }
    let bounds = CGRect(x: (xs.min() ?? 0)-3, y: (zs.min() ?? 0)-3,
        width: max(6,(xs.max() ?? 0)-(xs.min() ?? 0)+6), height: max(6,(zs.max() ?? 0)-(zs.min() ?? 0)+6))
    var path = Path()
    for (i,p) in points.enumerated() {
        let q = CGPoint(x: CGFloat(p.x), y: CGFloat(p.z))
        if i == 0 { path.move(to:q) } else { path.addLine(to:q) }
    }
    return (bounds,path)
}
@inline(never) func consume(_ drawing: (CGRect,Path)) -> CGFloat { drawing.1.isEmpty ? 0 : drawing.0.width }
for count in [5000,50000] {
 let points=(0..<count).map { Point(x:Float($0)*0.02,z:sin(Float($0)*0.001)*3) }
 let iterations=1000
 var check:CGFloat=0
 let oldStart=CFAbsoluteTimeGetCurrent()
 for _ in 0..<iterations { check += consume(prepare(points)) }
 let oldMS=(CFAbsoluteTimeGetCurrent()-oldStart)*1000
 let newStart=CFAbsoluteTimeGetCurrent()
 let cached=prepare(points)
 for _ in 0..<iterations { check += consume(cached) }
 let newMS=(CFAbsoluteTimeGetCurrent()-newStart)*1000
 print(String(format:"SYNTHETIC_MAC_DRAWING: points=%d updates=%d rebuild=%.3f_ms cache_including_first_build=%.3f_ms checksum=%.0f",count,iterations,oldMS,newMS,Double(check)))
}
